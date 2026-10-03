//! Async adapter over the userspace netstack's TCP channel.
//!
//! `StackHandle::open_tcp` returns a `(TcpSender, Receiver<Vec<u8>>)` pair of
//! raw message channels, but tokio-boring needs a single `AsyncRead +
//! AsyncWrite` object to run a TLS handshake on. This module bridges the two:
//! writes are forwarded to the stack as whole chunks, reads pull queued chunks
//! back out. No splitting, no coalescing beyond what the stack already does —
//! TLS is a byte stream and the stack delivers it in order.
//!
//! The only user is the DNS-over-TLS resolver; regular proxy traffic talks to
//! the stack through its own halves directly.

use std::io;
use std::pin::Pin;
use std::task::{Context, Poll};

use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};
use tokio::sync::mpsc;

use crate::error::Result;
use crate::netstack::{StackHandle, TcpSender};

pub struct StackStream {
    sender: TcpSender,
    inbound: mpsc::Receiver<Vec<u8>>,
    pending: Vec<u8>,
    closed: bool,
}

impl StackStream {
    /// Open a TCP connection through the tunnel's userspace stack.
    ///
    /// This deliberately uses the stack rather than a real socket + protect():
    /// a protected socket leaves the tunnel, and a resolver reachable only
    /// from the tunnel's egress (e.g. an Iran-only DoT server behind a foreign
    /// WARP edge) would never answer. The stack routes the connection through
    /// the same gateway as every other byte.
    pub async fn open(stack: &StackHandle, dst: std::net::SocketAddr) -> Result<Self> {
        let conn = stack.open_tcp(dst).await?;
        // into_split takes ownership of the real inbound channel. take_inbound
        // before it would leave into_split holding a throwaway channel(1)
        // receiver that never receives anything.
        let (sender, inbound) = conn.into_split();
        Ok(StackStream {
            sender,
            inbound,
            pending: Vec::new(),
            closed: false,
        })
    }

    pub async fn close(&mut self) {
        self.sender.close().await;
    }
}

impl AsyncRead for StackStream {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        // Serve whatever was left over from the last chunk first; a single
        // stack chunk is often bigger than the 16-byte TLS record header the
        // caller is asking for, and dropping the tail would corrupt the stream.
        if !self.pending.is_empty() {
            let n = std::cmp::min(self.pending.len(), buf.remaining());
            let data = self.pending.drain(..n).collect::<Vec<_>>();
            buf.put_slice(&data);
            return Poll::Ready(Ok(()));
        }

        if self.closed {
            // EOF. Report it the way a real socket does — a read of zero bytes
            // — so read_exact and the TLS layer see the end of stream instead
            // of looping forever on Ready(Ok(())) with an empty ReadBuf.
            return Poll::Ready(Ok(()));
        }

        match self.inbound.poll_recv(cx) {
            Poll::Ready(Some(chunk)) => {
                if chunk.is_empty() {
                    // The stack sends an empty chunk when the peer half-closes.
                    self.closed = true;
                    return Poll::Ready(Ok(()));
                }
                let n = std::cmp::min(chunk.len(), buf.remaining());
                buf.put_slice(&chunk[..n]);
                if n < chunk.len() {
                    self.pending.extend_from_slice(&chunk[n..]);
                }
                Poll::Ready(Ok(()))
            }
            Poll::Ready(None) => {
                self.closed = true;
                Poll::Ready(Ok(()))
            }
            Poll::Pending => Poll::Pending,
        }
    }
}

impl AsyncWrite for StackStream {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        if buf.is_empty() {
            return Poll::Ready(Ok(0));
        }
        // tokio-boring writes whole records; sending them as one chunk keeps
        // the stack from fragmenting a TLS record across datagrams.
        let chunk = buf.to_vec();
        match self.sender.poll_send(cx, chunk) {
            Poll::Ready(Ok(())) => Poll::Ready(Ok(buf.len())),
            Poll::Ready(Err(_)) => {
                Poll::Ready(Err(io::Error::other("netstack closed during write")))
            }
            Poll::Pending => Poll::Pending,
        }
    }

    fn poll_flush(self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Poll::Ready(Ok(()))
    }

    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        self.sender.poll_close(cx)
    }
}

// tokio-boring requires the underlying stream to be Unpin, and so do
// AsyncReadExt/AsyncWriteExt. `StackStream` owns a TcpConn and a Receiver, both
// of which are !Unpin, so the auto-impl does not fire. All access goes through
// Pin<&mut Self>, never through pin-projection of a !Unpin field, so the
// unconditional impl is sound.
impl Unpin for StackStream {}

impl Drop for StackStream {
    fn drop(&mut self) {
        // tokio-boring owns the stream once the handshake succeeds and drops it
        // when the SslStream goes away. The stack connection underneath must be
        // torn down here too, otherwise it lingers in the userspace stack until
        // the whole tunnel stops. try_send never blocks, which is what Drop
        // requires; a full channel just means the stack is already shutting
        // down and will discard the connection on its own.
        use tokio::sync::mpsc::error::TrySendError;
        let _ = self
            .sender
            .try_send_close()
            .map_err(|e| match e {
                TrySendError::Full(_) => (),
                TrySendError::Closed(_) => (),
            });
    }
}
