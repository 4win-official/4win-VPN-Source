use std::io;
use std::net::SocketAddr;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpStream, UdpSocket};

/// A connected UDP transport carried through a SOCKS5 UDP ASSOCIATE relay.
/// The TCP control stream is retained and monitored; it is never replaced by a
/// direct socket after association failure.
pub struct MixUdpSocket {
    udp: UdpSocket,
    control: TcpStream,
    peer: SocketAddr,
}

pub enum WgUdpSocket {
    Direct(UdpSocket),
    Socks(MixUdpSocket),
}

impl WgUdpSocket {
    pub async fn bind(peer: SocketAddr, upstream: Option<&str>) -> io::Result<Self> {
        match upstream.map(str::trim).filter(|s| !s.is_empty()) {
            Some(url) => Ok(Self::Socks(MixUdpSocket::connect(url, peer).await?)),
            None => {
                let socket = UdpSocket::bind(if peer.is_ipv4() {
                    "0.0.0.0:0"
                } else {
                    "[::]:0"
                })
                .await?;
                socket.connect(peer).await?;
                Ok(Self::Direct(socket))
            }
        }
    }
    pub async fn send(&self, packet: &[u8]) -> io::Result<usize> {
        match self {
            Self::Direct(s) => s.send(packet).await,
            Self::Socks(s) => s.send(packet).await,
        }
    }
    pub async fn recv(&self, buf: &mut [u8]) -> io::Result<usize> {
        match self {
            Self::Direct(s) => s.recv(buf).await,
            Self::Socks(s) => s.recv(buf).await,
        }
    }
    pub fn direct(&self) -> Option<&UdpSocket> {
        match self {
            Self::Direct(s) => Some(s),
            Self::Socks(_) => None,
        }
    }
}

impl MixUdpSocket {
    pub async fn connect(proxy: &str, peer: SocketAddr) -> io::Result<Self> {
        let proxy_addr = parse_proxy_addr(proxy)?;
        let mut control = TcpStream::connect(proxy_addr).await?;
        control.write_all(&[5, 1, 0]).await?;
        let mut hello = [0u8; 2];
        control.read_exact(&mut hello).await?;
        if hello != [5, 0] {
            return Err(io::Error::new(
                io::ErrorKind::PermissionDenied,
                "SOCKS5 upstream does not allow no-auth",
            ));
        }
        // UDP ASSOCIATE with wildcard destination; WireGuard's destination is
        // carried in each datagram and is therefore not resolved locally.
        control.write_all(&[5, 3, 0, 1, 0, 0, 0, 0, 0, 0]).await?;
        let mut head = [0u8; 4];
        control.read_exact(&mut head).await?;
        if head[0] != 5 || head[1] != 0 {
            return Err(io::Error::new(
                io::ErrorKind::ConnectionRefused,
                format!("SOCKS UDP ASSOCIATE failed: reply {}", head[1]),
            ));
        }
        let relay = read_addr(&mut control, head[3]).await?;
        let udp = UdpSocket::bind(if relay.is_ipv4() {
            "0.0.0.0:0"
        } else {
            "[::]:0"
        })
        .await?;
        udp.connect(relay).await?;
        Ok(Self { udp, control, peer })
    }

    pub async fn send(&self, packet: &[u8]) -> io::Result<usize> {
        // A failed control channel must be terminal: never retry the packet on
        // the physical network, which would violate the upstream privacy rule.
        self.control_check().await?;
        let mut frame = Vec::with_capacity(packet.len() + 32);
        frame.extend_from_slice(&[0, 0, 0]);
        append_addr(&mut frame, self.peer);
        frame.extend_from_slice(packet);
        self.udp.send(&frame).await?;
        Ok(packet.len())
    }

    pub async fn recv(&self, buf: &mut [u8]) -> io::Result<usize> {
        let mut frame = vec![0u8; buf.len() + 300];
        let n = tokio::select! {
            result = self.udp.recv(&mut frame) => result?,
            result = self.control_closed() => { result?; return Err(io::Error::new(io::ErrorKind::ConnectionReset, "SOCKS5 control connection closed")); }
        };
        if n < 4 || frame[..3] != [0, 0, 0] {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "invalid SOCKS5 UDP frame",
            ));
        }
        let (offset, _) = parse_addr(&frame[..n], 3)?;
        let payload = &frame[offset..n];
        if payload.len() > buf.len() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "SOCKS5 UDP datagram too large",
            ));
        }
        buf[..payload.len()].copy_from_slice(payload);
        Ok(payload.len())
    }

    async fn control_closed(&self) -> io::Result<()> {
        loop {
            self.control.readable().await?;
            let mut one = [0u8; 1];
            match self.control.try_read(&mut one) {
                Ok(0) => return Ok(()),
                Ok(_) => {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "unexpected SOCKS5 control data",
                    ))
                }
                Err(e) if e.kind() == io::ErrorKind::WouldBlock => continue,
                Err(e) => return Err(e),
            }
        }
    }
    async fn control_check(&self) -> io::Result<()> {
        match self.control.ready(tokio::io::Interest::READABLE).await {
            Ok(ready) if ready.is_readable() => {
                let mut one = [0u8; 1];
                match self.control.try_read(&mut one) {
                    Ok(0) => Err(io::Error::new(
                        io::ErrorKind::ConnectionReset,
                        "SOCKS5 control connection closed",
                    )),
                    Ok(_) => Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "unexpected SOCKS5 control data",
                    )),
                    Err(e) if e.kind() == io::ErrorKind::WouldBlock => Ok(()),
                    Err(e) => Err(e),
                }
            }
            Ok(_) => Ok(()),
            Err(e) => Err(e),
        }
    }
}

fn parse_proxy_addr(raw: &str) -> io::Result<SocketAddr> {
    let value = raw.trim();
    let value = value
        .strip_prefix("socks5h://")
        .or_else(|| value.strip_prefix("socks5://"))
        .or_else(|| value.strip_prefix("socks://"))
        .unwrap_or(value);
    let value = value.strip_prefix("//").unwrap_or(value);
    let authority = value.rsplit_once('@').map(|(_, a)| a).unwrap_or(value);
    authority.parse().map_err(|_| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "SOCKS upstream must be ip:port",
        )
    })
}

async fn read_addr(stream: &mut TcpStream, atyp: u8) -> io::Result<SocketAddr> {
    let mut raw = vec![atyp];
    match atyp {
        1 => {
            let mut b = [0; 4];
            stream.read_exact(&mut b).await?;
            raw.extend_from_slice(&b);
        }
        3 => {
            let mut l = [0];
            stream.read_exact(&mut l).await?;
            let mut b = vec![0; l[0] as usize];
            stream.read_exact(&mut b).await?;
            raw.push(l[0]);
            raw.extend_from_slice(&b);
        }
        4 => {
            let mut b = [0; 16];
            stream.read_exact(&mut b).await?;
            raw.extend_from_slice(&b);
        }
        _ => {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "bad SOCKS address type",
            ))
        }
    }
    let mut p = [0; 2];
    stream.read_exact(&mut p).await?;
    raw.extend_from_slice(&p);
    parse_addr(&raw, 0).map(|(_, a)| a)
}

fn append_addr(out: &mut Vec<u8>, addr: SocketAddr) {
    match addr {
        SocketAddr::V4(a) => {
            out.push(1);
            out.extend_from_slice(&a.ip().octets());
            out.extend_from_slice(&a.port().to_be_bytes());
        }
        SocketAddr::V6(a) => {
            out.push(4);
            out.extend_from_slice(&a.ip().octets());
            out.extend_from_slice(&a.port().to_be_bytes());
        }
    }
}

fn parse_addr(buf: &[u8], start: usize) -> io::Result<(usize, SocketAddr)> {
    if buf.len() <= start {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "missing SOCKS address",
        ));
    }
    let atyp = buf[start];
    let mut i = start + 1;
    let ip = match atyp {
        1 => {
            if buf.len() < i + 4 {
                return Err(io::Error::new(io::ErrorKind::UnexpectedEof, "short IPv4"));
            }
            let a = std::net::Ipv4Addr::new(buf[i], buf[i + 1], buf[i + 2], buf[i + 3]);
            i += 4;
            std::net::IpAddr::V4(a)
        }
        4 => {
            if buf.len() < i + 16 {
                return Err(io::Error::new(io::ErrorKind::UnexpectedEof, "short IPv6"));
            }
            let mut a = [0; 16];
            a.copy_from_slice(&buf[i..i + 16]);
            i += 16;
            std::net::IpAddr::V6(a.into())
        }
        3 => {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "SOCKS relay returned a domain address",
            ))
        }
        _ => {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "bad SOCKS address type",
            ))
        }
    };
    if buf.len() < i + 2 {
        return Err(io::Error::new(
            io::ErrorKind::UnexpectedEof,
            "missing SOCKS port",
        ));
    }
    Ok((
        i + 2,
        SocketAddr::new(ip, u16::from_be_bytes([buf[i], buf[i + 1]])),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::AsyncWriteExt;
    use tokio::net::TcpListener;

    async fn fake_socks(close_control: bool) -> (String, tokio::task::JoinHandle<()>) {
        let udp = UdpSocket::bind("127.0.0.1:0").await.unwrap();
        let relay = udp.local_addr().unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let task = tokio::spawn(async move {
            let (mut tcp, _) = listener.accept().await.unwrap();
            let mut hello = [0; 3];
            tcp.read_exact(&mut hello).await.unwrap();
            tcp.write_all(&[5, 0]).await.unwrap();
            let mut req = [0; 10];
            tcp.read_exact(&mut req).await.unwrap();
            let mut reply = vec![5, 0, 0, 1];
            if let SocketAddr::V4(a) = relay {
                reply.extend_from_slice(&a.ip().octets());
                reply.extend_from_slice(&a.port().to_be_bytes());
            }
            tcp.write_all(&reply).await.unwrap();
            if close_control {
                tcp.shutdown().await.unwrap();
                return;
            }
            let mut frame = [0; 2048];
            let (n, peer) = udp.recv_from(&mut frame).await.unwrap();
            udp.send_to(&frame[..n], peer).await.unwrap();
            // The association must stay alive until the client consumes the datagram.
            let mut eof = [0; 1];
            let _ = tcp.read(&mut eof).await;
        });
        (format!("socks5h://{addr}"), task)
    }

    #[tokio::test]
    async fn real_socks5_udp_associate_roundtrips_framed_data() {
        let (proxy, server) = fake_socks(false).await;
        let peer: SocketAddr = "127.0.0.1:51820".parse().unwrap();
        let socket = MixUdpSocket::connect(&proxy, peer).await.unwrap();
        assert_eq!(socket.send(b"payload").await.unwrap(), 7);
        let mut out = [0; 64];
        assert_eq!(socket.recv(&mut out).await.unwrap(), 7);
        assert_eq!(&out[..7], b"payload");
        drop(socket);
        server.await.unwrap();
    }

    #[tokio::test]
    async fn control_close_is_error_and_never_falls_back_direct() {
        let (proxy, server) = fake_socks(true).await;
        let socket = MixUdpSocket::connect(&proxy, "127.0.0.1:51820".parse().unwrap())
            .await
            .unwrap();
        let mut out = [0; 8];
        let err = socket.recv(&mut out).await.unwrap_err();
        assert_eq!(err.kind(), io::ErrorKind::ConnectionReset);
        server.await.unwrap();
    }
}
