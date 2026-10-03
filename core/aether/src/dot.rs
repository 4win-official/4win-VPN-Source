//! DNS-over-TLS (RFC 7858) transport for the resolver path.
//!
//! The plain UDP/53 resolver in socks.rs is the default and stays the default;
//! this module only kicks in when the user writes an entry with a `tls://`
//! prefix in the custom DNS field. The entry is resolved through the tunnel's
//! own TCP stack, so an Iran-only resolver reachable on port 853 works over the
//! same egress as everything else.
//!
//! Verification is relaxed by default (no hostname pin, certificate accepted
//! as presented). The resolver address already came from the user, the query
//! is padded, and a TLS failure falls back to the plain resolvers behind it —
//! same posture as the UDP path, which has no authentication at all.

use std::io;
use std::net::SocketAddr;
use std::sync::Mutex;
use std::time::Instant;

use tokio::io::{AsyncReadExt, AsyncWriteExt};

use crate::error::{AetherError, Result};
use crate::netstack::StackHandle;
use crate::stackstream::StackStream;

/// A DNS-over-TLS endpoint parsed from a `tls://` entry.
#[derive(Clone, Debug)]
pub struct DotServer {
    /// Where the TCP connection goes. Port defaults to 853 per RFC 7858.
    pub addr: SocketAddr,
    /// SNI to present. Defaults to the address as a string.
    pub sni: String,
}

impl DotServer {
    /// Parse `tls://1.2.3.4`, `tls://1.2.3.4:853`, `tls://family.cloudflare-dns.com`
    /// or with an explicit SNI `tls://1.2.3.4#dns.example`.
    /// A hostname entry is kept (addr stays None-shaped but we store the host
    /// and resolve it at query time via the plain UDP path, same egress as
    /// the simple-UDP fix — that is what makes an exporter-hostname resolver
    /// reachable at all from this stack).
    pub fn parse(entry: &str) -> Option<Self> {
        let rest = entry.strip_prefix("tls://").or_else(|| entry.strip_prefix("dot://"))?;
        let rest = rest.trim();
        if rest.is_empty() {
            return None;
        }
        let (host_part, sni) = match rest.split_once('#') {
            Some((h, s)) => (h.trim(), s.trim().to_string()),
            None => (rest, String::new()),
        };
        // Try SocketAddr, then bare IP, then hostname.
        if let Ok(a) = host_part.parse::<SocketAddr>() {
            let sni = if sni.is_empty() { a.ip().to_string() } else { sni };
            return Some(DotServer { addr: a, sni });
        }
        if let Ok(ip) = host_part.parse::<std::net::IpAddr>() {
            let addr = SocketAddr::new(ip, 853);
            let sni = if sni.is_empty() { addr.ip().to_string() } else { sni };
            return Some(DotServer { addr, sni });
        }
        // Hostname: keep as SocketAddr placeholder; resolved at resolve time
        // via the tunnel's UDP path. Use a sentinel 0.0.0.1 + real hostname in sni.
        if host_part.contains('.') && !host_part.contains(' ') {
            let sni_host = if sni.is_empty() { host_part.to_string() } else { sni };
            // Parse host:port if they gave tls://family.cloudflare-dns.com:853
            let (_h, p) = match host_part.rsplit_once(':') {
                Some((hh, pp)) if pp.parse::<u16>().is_ok() => (hh, pp.parse().unwrap()),
                _ => (host_part, 853),
            };
            // Store hostname in sni, address as 0.0.0.0 placeholder — resolve_a will fix it
            let addr = SocketAddr::new("0.0.0.0".parse().unwrap(), p);
            // keep original hostname via sni; if sni was the IP-string case above it differs,
            // here sni IS the hostname (or the # override). stash host in sni_host
            return Some(DotServer { addr, sni: sni_host });
        }
        None
    }

    fn is_hostname_placeholder(&self) -> bool {
        self.addr.ip().to_string() == "0.0.0.0"
    }
}

/// Resolve a name over DNS-over-TLS. Returns the first A record.
///
/// The whole exchange is framed with the two-byte length prefix from RFC 7858;
/// without it the server cannot tell where one message ends.
pub async fn resolve_a(stack: &StackHandle, server: &DotServer, name: &str) -> Result<std::net::IpAddr> {
    let (addr, sni_for_tls) = if server.is_hostname_placeholder() {
        let ip = resolve_dot_hostname_via_udp(stack, &server.sni).await?;
        (std::net::SocketAddr::new(ip, server.addr.port()), server.sni.clone())
    } else {
        (server.addr, server.sni.clone())
    };
    let stream = StackStream::open(stack, addr).await?;

    let (query, id) = crate::socks::build_dns_query_public(name, crate::socks::QTYPE_A);

    // tokio_boring takes ownership of the stream; the TLS layer wraps it and
    // the underlying stack connection is closed when the SslStream drops.
    let mut tls = crate::tls::connect_dot(&sni_for_tls, stream).await?;

    // RFC 7858 framing: 2-byte big-endian length before each message.
    let len = (query.len() as u16).to_be_bytes();
    tls.write_all(&len).await.map_err(map_io)?;
    tls.write_all(&query).await.map_err(map_io)?;
    tls.flush().await.map_err(map_io)?;

    let mut hdr = [0u8; 2];
    tls.read_exact(&mut hdr).await.map_err(map_io)?;
    let reply_len = u16::from_be_bytes(hdr) as usize;
    if reply_len < 12 {
        return Err(AetherError::Other("dot: reply too short".into()));
    }

    let mut buf = vec![0u8; reply_len];
    tls.read_exact(&mut buf).await.map_err(map_io)?;

    // Dropping closes the stack connection; flush first so the query is not
    // left half-sent when the resolver is slow.
    let _ = tls.flush().await;

    if !crate::socks::dns_response_matches_public(&buf, id, name, crate::socks::QTYPE_A) {
        return Err(AetherError::Other("dot: reply did not match the query".into()));
    }
    crate::socks::parse_dns_a_public(&buf)
        .ok_or_else(|| AetherError::Other("dot: no A record in reply".into()))
}

/// Every DoT endpoint the user configured, in the order they wrote them.
///
/// Deliberately returns an empty list when the user has not written a single
/// `tls://` entry. Public DoT endpoints are intentionally NOT added as a
/// fallback here: `dns_resolve` tries this list before the plain UDP resolvers,
/// and a hardcoded fallback would mean every lookup of every user pays a TLS
/// handshake to Cloudflare even though they asked for plain UDP. Users who want
/// DoT opt in with `tls://`; users who do not get UDP, exactly as before.
pub(crate) fn dot_servers() -> Vec<DotServer> {
    let configured = std::env::var("AETHER_DNS").unwrap_or_default();
    let mut out = Vec::new();
    for token in configured.split([',', ' ', ';']) {
        if let Some(server) = DotServer::parse(token) {
            // Placeholder 0.0.0.0 is not unique per hostname, so dedup on
            // (addr, sni) — otherwise two hostname DoT entries would
            // collapse into one and the other would silently vanish.
            if !out.iter().any(|s: &DotServer| s.addr == server.addr && s.sni == server.sni) {
                out.push(server);
            }
        }
    }
    out
}

fn map_io(e: io::Error) -> AetherError {
    AetherError::Other(format!("dot: {e}"))
}

async fn resolve_dot_hostname_via_udp(stack: &crate::netstack::StackHandle, host: &str) -> crate::error::Result<std::net::IpAddr> {
    let udp = stack.open_udp().await?;
    let (sender, mut rx) = udp.into_split();
    let r = crate::socks::dns_exchange_public(&sender, &mut rx, host).await;
    sender.close().await;
    r
}

/// How long a failed server is skipped before it is retried.
const BACKOFF: std::time::Duration = std::time::Duration::from_secs(30);

fn backoff_state() -> &'static Mutex<std::collections::HashMap<String, Instant>> {
    use std::sync::OnceLock;
    static STATE: OnceLock<Mutex<std::collections::HashMap<String, Instant>>> = OnceLock::new();
    STATE.get_or_init(|| Mutex::new(std::collections::HashMap::new()))
}

fn backoff_key(server: &DotServer) -> String {
    if server.addr.ip().to_string() == "0.0.0.0" {
        // hostname placeholder — key on the authority so two different
        // hostnames don't share one backoff slot
        format!("{}:{}", server.sni, server.addr.port())
    } else {
        server.addr.to_string()
    }
}

/// True while a failed server is still in its cooldown, so `dns_resolve`
/// skips it instead of paying its timeout on every connection.
pub(crate) fn is_backing_off(server: &DotServer) -> bool {
    let now = Instant::now();
    let key = backoff_key(server);
    backoff_state()
        .lock()
        .map(|map| {
            map.get(&key)
                .is_some_and(|until| *until > now)
        })
        .unwrap_or(false)
}

/// Record a failure and start the cooldown.
pub(crate) fn mark_failure(server: &DotServer) {
    let _ = backoff_state()
        .lock()
        .map(|mut map| map.insert(backoff_key(server), Instant::now() + BACKOFF));
}
