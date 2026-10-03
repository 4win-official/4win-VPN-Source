//! DNS-over-HTTPS (RFC 8484).
//!
//! Runs on the tunnel's own userspace stack for the same reason DoT does: a
//! real socket plus VpnService.protect() would bypass the tunnel entirely, and
//! the resolver the user picked is often reachable only through it.
//!
//! Wire format: a single HTTP/2 POST to the `/dns-query` path with
//! `application/dns-message` in both directions, body = a raw DNS message.
//! GET with the query in a urlsafe-base64 `?dns=` parameter is also valid but
//! POST is simpler and universally supported.

use crate::error::{AetherError, Result};
use crate::netstack::StackHandle;
use crate::stackstream::StackStream;

use std::sync::Mutex;
use std::time::Instant;

/// Same frame ceiling as the h2 tunnel path.
const H2_MAX_FRAME_SIZE: u32 = 64 * 1024;

/// A DNS-over-HTTPS endpoint parsed from an `https://` entry.
#[derive(Clone, Debug)]
pub struct DohServer {
    /// Where the TCP connection goes. Port defaults to 443.
    pub addr: std::net::SocketAddr,
    /// Host:authority — used for SNI and the HTTP/2 :authority pseudo-header.
    pub host: String,
    /// Path after the host, defaulting to `/dns-query`.
    pub path: String,
}

impl DohServer {
    /// Parse `https://1.2.3.4`, `https://1.2.3.4/dns-query`, or with an explicit
    /// host `https://dns.example/dns-query`. Returns None when the entry is not
    /// a DoH entry, so the caller can fall through.
    pub fn parse(entry: &str) -> Option<Self> {
        let rest = entry.strip_prefix("https://")?;
        let rest = rest.trim();
        if rest.is_empty() {
            return None;
        }

        // Split authority from path. The authority never contains a '/'.
        let (authority, path) = match rest.split_once('/') {
            Some((a, p)) => (a.trim(), format!("/{}", p.trim())),
            None => (rest, "/dns-query".to_string()),
        };
        if authority.is_empty() {
            return None;
        }

        // Authority may be host:port, [v6]:port, [v6], or bare host.
        let (host_part, port) = if let Some(rest) = authority.strip_prefix('[') {
            // bracketed v6
            let (h, rest) = rest.split_once(']')?;
            let port = rest.strip_prefix(':').and_then(|p| p.parse::<u16>().ok());
            (h.trim(), port)
        } else if authority.matches(':').count() > 1 {
            // bare v6 — no port
            (authority, None)
        } else {
            match authority.split_once(':') {
                Some((h, p)) => (h.trim(), p.trim().parse::<u16>().ok()),
                None => (authority, None),
            }
        };
        if host_part.is_empty() {
            return None;
        }

        // DoH needs an IP to open the socket. The entry may be a hostname
        // (https://cloudflare-dns.com/dns-query) — resolve it via the tunnel's
        // UDP path at query time, exactly the mechanism DoT uses now. Keeping
        // the entry here (instead of dropping it) is what makes a hostname DoH
        // resolver work at all through a foreign egress.
        match host_part.parse::<std::net::IpAddr>() {
            Ok(ip) => Some(DohServer {
                addr: std::net::SocketAddr::new(ip, port.unwrap_or(443)),
                host: host_part.to_string(),
                path,
            }),
            Err(_) => {
                // Hostname. We can't resolve synchronously here (parse is not
                // async), so store a placeholder and let resolve_a do the
                // lookup. Use 0.0.0.0 as the sentinel; the port is real.
                if host_part.contains('.') && !host_part.contains(' ') {
                    Some(DohServer {
                        addr: std::net::SocketAddr::new("0.0.0.0".parse().unwrap(), port.unwrap_or(443)),
                        host: host_part.to_string(),
                        path,
                    })
                } else {
                    None
                }
            }
        }
    }
}

/// Resolve a name over DNS-over-HTTPS. Returns the first A record.
pub async fn resolve_a(stack: &StackHandle, server: &DohServer, name: &str) -> Result<std::net::IpAddr> {
    let started = std::time::Instant::now();
    let addr = if server.addr.ip().to_string() == "0.0.0.0" {
        // Hostname DoH entry (e.g. https://cloudflare-dns.com/dns-query).
        // Resolve it via the tunnel's UDP path first — same mechanism DoT uses,
        // same egress, and the only way the hostname is reachable at all.
        let before_hostname = std::time::Instant::now();
        let ip = match resolve_doh_hostname_via_udp(stack, &server.host).await {
            Ok(ip) => {
                let ms = before_hostname.elapsed().as_millis();
                if ms > 1500 {
                    log::info!(
                        "doh: hostname {} → {ip} ({ms}ms) — resolving {name}",
                        server.host
                    );
                }
                ip
            }
            Err(e) => {
                log::warn!(
                    "doh: hostname {} failed ({ms}ms): {e} — resolving {name}",
                    server.host,
                    ms = before_hostname.elapsed().as_millis()
                );
                return Err(e);
            }
        };
        std::net::SocketAddr::new(ip, server.addr.port())
    } else {
        server.addr
    };
    let stream = StackStream::open(stack, addr).await?;

    // Mirrors the DoT module: the first lookup against a resolver the user
    // typed by hand deserves a visible line, otherwise a DoH failure looks
    // identical to "DoH is working" in the app log.
    if started.elapsed() > std::time::Duration::from_millis(2500) {
        log::info!(
            "doh: slow setup {host} ({ms}ms) — resolving {name}",
            host = server.host,
            ms = started.elapsed().as_millis(),
            name = name
        );
    }

    let (query, id) = crate::socks::build_dns_query_public(name, crate::socks::QTYPE_A);

    let tls = crate::tls::connect_doh(&server.host, stream).await?;

    // h2 drives the TLS stream from its own connection future; this task owns
    // it and is aborted when resolve_a returns so the stack connection closes.
    // Mirrors the DoT path: success → info (so a DoH failure does not look like
    // "DoH is not there"), stall → info marked slow so the user sees "DoH
    // did fire, just after the edge warmed up".
    let (h2_send, h2_conn) = h2::client::Builder::new()
        .initial_window_size(crate::sysprofile::h2_stream_window_bytes())
        .initial_connection_window_size(crate::sysprofile::h2_connection_window_bytes())
        .max_frame_size(H2_MAX_FRAME_SIZE)
        .handshake(tls)
        .await
        .map_err(|e| AetherError::Other(format!("doh: h2 handshake: {e}")))?;

    let drive = tokio::spawn(async move {
        if let Err(e) = h2_conn.await {
            log::debug!("doh h2 connection ended: {e}");
        }
    });

    // h2::client refuses send_request until the connection is ready to open a
    // stream; ready() is the documented gate.
    let mut h2_send = h2_send
        .ready()
        .await
        .map_err(|e| AetherError::Other(format!("doh: h2 ready: {e}")))?;

    // RFC 8484: POST a raw DNS message with the DoH content types. A bare
    // request line would be rejected — h2 0.4 takes a real http::Request.
    let request = http::Request::builder()
        .method("POST")
        .uri(format!("https://{}{}", server.host, server.path))
        .header("content-type", "application/dns-message")
        .header("accept", "application/dns-message")
        .header("user-agent", "MSN-Guard/1.0")
        .body(())
        .map_err(|e| AetherError::Other(format!("doh: build request: {e}")))?;

    let (resp_fut, mut send_stream) = h2_send
        .send_request(request, false)
        .map_err(|e| AetherError::Other(format!("doh: send request: {e}")))?;

    send_stream
        .send_data(bytes::Bytes::from(query), true)
        .map_err(|e| AetherError::Other(format!("doh: send body: {e}")))?;

    let response = resp_fut
        .await
        .map_err(|e| AetherError::Other(format!("doh: no response: {e}")))?;

    // Only 2xx carries a DNS message; everything else is a server-side refusal
    // and the caller should move on to the next resolver rather than guess.
    if !response.status().is_success() {
        drive.abort();
        return Err(AetherError::Other(format!(
            "doh: {} returned status {}",
            server.host,
            response.status().as_u16()
        )));
    }

    let mut body = response.into_body();
    let mut buf = Vec::new();
    while let Some(frame) = body.data().await {
        let frame = frame.map_err(|e| AetherError::Other(format!("doh: read body: {e}")))?;
        buf.extend_from_slice(&frame);
        // A DoH response fits in one or two frames; cap the read so a
        // misbehaving server cannot pin this task forever.
        if buf.len() > 65535 {
            break;
        }
    }
    // Reading to END_STREAM lets the connection task see a clean close.
    let _ = drive.await;

    if buf.len() < 12 {
        return Err(AetherError::Other("doh: reply too short".into()));
    }

    if !crate::socks::dns_response_matches_public(&buf, id, name, crate::socks::QTYPE_A) {
        return Err(AetherError::Other("doh: reply did not match the query".into()));
    }
    crate::socks::parse_dns_a_public(&buf)
        .ok_or_else(|| AetherError::Other("doh: no A record in reply".into()))
}

/// Resolve a DoH hostname via the tunnel's plain UDP path — same egress as
/// the simple-UDP DNS that already works, so a hostname DoH resolver is
/// reachable through a foreign Cloudflare edge too. Tuned the same way as DoT:
/// bounded, with a quick fallback so a slow Iran-only resolver does not stall
/// the whole name lookup.
///
/// Note: tls::connect_doh itself uses a TCP stack connection, so the UDP
/// lookup here + the TCP for DoH are both inside the userspace stack.
/// That is why the UDP-simple fix and the DoT fix are the model — they are
/// the same egress, the same socket family, the same stack.
async fn resolve_doh_hostname_via_udp(stack: &StackHandle, host: &str) -> Result<std::net::IpAddr> {
    // Cheap win on a slow edge: the DoH server's own hostname never changes
    // across the session. Without this every single name lookup pays an extra
    // UDP round trip (10 s on this edge, see log 9) before the TCP/TLS/h2
    // handshake even starts.
    if let Some(ip) = cached_hostname(host) {
        if crate::socks::resolver_addresses().is_empty() {
            // UDP fallback path still there, so the cached IP is usable
        }
        log::debug!("doh: hostname {host} hit {ip} (cache)");
        return Ok(ip);
    }
    let udp = stack.open_udp().await?;
    let (sender, mut rx) = udp.into_split();
    let r = crate::socks::dns_exchange_doh_hostname(&sender, &mut rx, host).await;
    sender.close().await;
    if let Ok(ip) = r {
        remember_hostname(host, ip);
    }
    r
}

fn hostname_cache() -> &'static Mutex<std::collections::HashMap<String, (std::net::IpAddr, Instant)>> {
    use std::sync::OnceLock;
    static C: OnceLock<Mutex<std::collections::HashMap<String, (std::net::IpAddr, Instant)>>> =
        OnceLock::new();
    C.get_or_init(|| Mutex::new(std::collections::HashMap::new()))
}

fn cached_hostname(host: &str) -> Option<std::net::IpAddr> {
    let now = Instant::now();
    hostname_cache()
        .lock()
        .ok()
        .and_then(|m| m.get(host).filter(|(_, exp)| *exp > now).map(|(ip, _)| *ip))
}

fn remember_hostname(host: &str, ip: std::net::IpAddr) {
    let _ = hostname_cache().lock().map(|mut m| {
        if m.len() > 32 {
            m.clear();
        }
        m.insert(host.to_string(), (ip, Instant::now() + CACHE_TTL));
    });
}

/// How long a successful lookup is reused, and how long a failed server is
/// skipped. DoH pays UDP+TCP+TLS+h2 per cold lookup — four round trips on a
/// slow edge — so it is the one resolver here that genuinely benefits from
/// remembering an answer. Cache the success, not the failure.
const CACHE_TTL: std::time::Duration = std::time::Duration::from_secs(60);
const BACKOFF: std::time::Duration = std::time::Duration::from_secs(30);

/// Per-name answer cache. A DoH handshake is four round trips; without this,
/// every connection on the device re-asks the same domain and the user sees
/// "sites did not load for the first few seconds" while the edge warms up.
fn answer_cache() -> &'static Mutex<std::collections::HashMap<String, (std::net::IpAddr, Instant)>> {
    use std::sync::OnceLock;
    static CACHE: OnceLock<Mutex<std::collections::HashMap<String, (std::net::IpAddr, Instant)>>> =
        OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(std::collections::HashMap::new()))
}

/// A cached answer that is still fresh, if any. Same shape as the DoT module's
/// needs: a hit avoids the whole handshake, a miss costs it once.
pub(crate) fn cached_answer(server: &DohServer, name: &str) -> Option<std::net::IpAddr> {
    let now = Instant::now();
    answer_cache()
        .lock()
        .ok()
        .and_then(|map| {
            map.get(&format!("{}|{name}", server.host))
                .filter(|(_, exp)| *exp > now)
                .map(|(ip, _)| *ip)
        })
}

/// Record a successful lookup so the next one is instant.
pub(crate) fn remember_answer(server: &DohServer, name: &str, ip: std::net::IpAddr) {
    use std::collections::HashMap;
    let _ = answer_cache().lock().map(|mut map| {
        // Bound the cache the way the tun2socks one does: clear wholesale at a
        // size cap rather than paying for eviction bookkeeping per insert.
        if map.len() > 512 {
            map.clear();
        }
        map.insert(
            format!("{}|{name}", server.host),
            (ip, Instant::now() + CACHE_TTL),
        );
        let _: &HashMap<String, (std::net::IpAddr, Instant)> = &map;
    });
}

fn backoff_state() -> &'static Mutex<std::collections::HashMap<String, Instant>> {
    use std::sync::OnceLock;
    static STATE: OnceLock<Mutex<std::collections::HashMap<String, Instant>>> =
        OnceLock::new();
    STATE.get_or_init(|| Mutex::new(std::collections::HashMap::new()))
}

/// Same key shape as DotServer's (addr, sni): for a hostname entry the
/// placeholder 0.0.0.0 would collapse every host into one slot, so we key on
/// the host authority instead. An IP entry keeps its full SocketAddr so two
/// different IPs are still independent.
fn backoff_key(server: &DohServer) -> String {
    if server.addr.ip().to_string() == "0.0.0.0" {
        format!("{}|{}", server.host, server.path)
    } else {
        format!("{}|{}", server.addr, server.path)
    }
}

/// True while a failed server is still in its cooldown, so `dns_resolve`
/// skips it instead of paying its timeout on every connection.
pub(crate) fn is_backing_off(server: &DohServer) -> bool {
    let now = Instant::now();
    let key = backoff_key(server);
    backoff_state()
        .lock()
        .map(|map| map.get(&key).is_some_and(|until| *until > now))
        .unwrap_or(false)
}

/// Record a failure and start the cooldown.
pub(crate) fn mark_failure(server: &DohServer) {
    let _ = backoff_state()
        .lock()
        .map(|mut map| map.insert(backoff_key(server), Instant::now() + BACKOFF));
}

/// Every DoH endpoint the user configured, in the order they wrote them.
///
/// Deliberately returns an empty list when the user has not written a single
/// `https://` entry, for the same reason as `dot_servers()`: it runs before the
/// plain UDP resolvers and a hardcoded fallback would make every lookup pay a
/// TLS + h2 handshake for a user who asked for UDP.
pub(crate) fn doh_servers() -> Vec<DohServer> {
    let configured = std::env::var("AETHER_DNS").unwrap_or_default();
    let mut out = Vec::new();
    for token in configured.split([',', ' ', ';']) {
        if let Some(server) = DohServer::parse(token) {
            // Placeholder 0.0.0.0 is not unique per hostname, so dedup on
            // the host+path too — otherwise two different https://hostname
            // entries would collapse into one and one would silently vanish.
            let key = (server.host.as_str(), server.path.as_str());
            if !out.iter().any(|s: &DohServer| (s.host.as_str(), s.path.as_str()) == key) {
                out.push(server);
            }
        }
    }
    out
}
