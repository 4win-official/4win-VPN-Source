//! TLS ClientHello SNI extraction, without a TLS stack.
//!
//! ## Why this exists
//!
//! The routing rules a user writes are expressed as *domains*, but inside a
//! TUN front end a connection is addressed as an IP. The name was resolved
//! before the packet reached us, and is gone by the time we see a SYN. So a
//! rule like "instagram.com goes direct" has nothing to match against, and
//! the only rules that work are CIDRs.
//!
//! The fix is to read the name off the wire: the first thing the client sends
//! is a TLS ClientHello that carries the name in the clear (that is the point
//! of SNI). We do not terminate TLS, decrypt, or even parse past the
//! extensions we care about — we only locate the SNI extension and read its
//! single hostname field. On a non-TLS flow, or a flow whose ClientHello is
//! fragmented across packets, we return [None] and the caller keeps its
//! existing IP-based decision. Nothing about the connection changes.
//!
//! ## Where it is called
//!
//! Only in the outbound path of [crate::tun], on the *first* segment of a
//! flow, when routing rules that name domains are actually configured. That
//! gate matters: the peek costs one extra read per new connection, and there
//! is no reason to pay it when nobody wrote a domain rule.
//!
//! ## The trade-off, stated plainly
//!
//! The ClientHello is not guaranteed to arrive in the first segment. TLS 1.3
//! with a large key-share and a long certificate list can exceed one TCP
//! segment, and if the SNI happens to sit in the part that has not arrived
//! yet we see [None] and fall back to the IP rule. That is a miss, not a
//! misroute: the fallback is the exact behaviour that existed before, so a
//! fragmented ClientHello costs a domain rule it would otherwise have won.
//!
//! It is also why the peek is bounded by [PEEK_BUDGET]: we read at most this
//! many bytes, and if the name is further in than that we do not chase it.
use std::io;

/// The TLS record type for a handshake.
const TLS_HANDSHAKE: u8 = 0x16;
/// The handshake message type for a ClientHello.
const TLS_CLIENT_HELLO: u8 = 0x01;
/// The extension type that carries the server name.
const EXT_SERVER_NAME: u16 = 0x0000;
/// The ServerNameEntry type for a hostname.
const SNI_HOST_NAME: u8 = 0x00;

/// The longest a DNS name may be, RFC 1035.
const MAX_HOST_LEN: usize = 253;

/// How many bytes to read looking for a name.
///
/// A ClientHello comfortably fits inside this in practice — the SNI extension
/// sits early in the extension list — and the budget also bounds how much a
/// misbehaving peer can make us buffer before we give up.
pub const PEEK_BUDGET: usize = 4096;

fn be16(buf: &[u8], at: usize) -> Option<usize> {
    let hi = *buf.get(at)? as usize;
    let lo = *buf.get(at + 1)? as usize;
    Some((hi << 8) | lo)
}

fn be24(buf: &[u8], at: usize) -> Option<usize> {
    let a = *buf.get(at)? as usize;
    let b = *buf.get(at + 1)? as usize;
    let c = *buf.get(at + 2)? as usize;
    Some((a << 16) | (b << 8) | c)
}

/// Is this a plausible hostname, and not an IP address in disguise?
///
/// A DPI filter or a malformed ClientHello can put bytes in the SNI field that
/// are not a name at all. Accepting them would mean matching a user's domain
/// rule against garbage, which is how a rule acquires a false positive. So the
/// name must be ASCII, must contain a dot, must not parse as an IP, and must
/// be within the DNS length limit.
fn plausible_host(raw: &[u8]) -> Option<String> {
    if raw.is_empty() || raw.len() > MAX_HOST_LEN {
        return None;
    }

    let name = std::str::from_utf8(raw).ok()?.trim().trim_end_matches('.');
    if name.is_empty() || name.len() > MAX_HOST_LEN {
        return None;
    }

    let allowed = name
        .bytes()
        .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'.' || b == b'_');
    if !allowed || !name.contains('.') {
        return None;
    }

    // An IP literal in the SNI is not a domain rule target. Some clients do
    // send it, and it must not be treated as a name.
    if name.parse::<std::net::IpAddr>().is_ok() {
        return None;
    }

    Some(name.to_lowercase())
}

/// Read the SNI hostname out of a TLS ClientHello.
///
/// Returns [None] for anything that is not a ClientHello carrying an SNI we
/// can trust: a non-handshake record, a non-ClientHello message, a truncated
/// extension list, a missing SNI extension, or a field that is not a
/// plausible hostname. Callers must treat [None] as "no name available" and
/// keep their existing behaviour.
///
/// `buf` holds the bytes received so far on this connection; it does not have
/// to be complete, only the leading part of the ClientHello.
pub fn tls_sni(buf: &[u8]) -> Option<String> {
    // TLS record header: type, version (2), length (2).
    if buf.len() < 5 || buf[0] != TLS_HANDSHAKE {
        return None;
    }

    // The handshake message begins after the 5-byte record header.
    let hs = &buf[5..];
    if hs.is_empty() || hs[0] != TLS_CLIENT_HELLO {
        return None;
    }

    // Handshake header: type (1), length (3), then the ClientHello body.
    if hs.len() < 4 {
        return None;
    }
    let _hs_len = be24(hs, 1)?;
    let mut cur = hs.get(4..)?;

    // legacy_version (2), random (32), legacy_session_id (1 + len).
    if cur.len() < 2 + 32 {
        return None;
    }
    cur = &cur[2 + 32..];
    let sid_len = *cur.first()? as usize;
    cur = cur.get(1 + sid_len..)?;

    // cipher_suites (2 + len), legacy_compression_methods (1 + len).
    let cs_len = be16(cur, 0)?;
    cur = cur.get(2 + cs_len..)?;
    let cm_len = *cur.first()? as usize;
    cur = cur.get(1 + cm_len..)?;

    // Extensions: 2-byte total length, then type (2) + length (2) each.
    let _ext_total = be16(cur, 0)?;
    cur = cur.get(2..)?;

    while cur.len() >= 4 {
        let ext_type = be16(cur, 0)?;
        let ext_len = be16(cur, 2)?;
        let ext = cur.get(4..4 + ext_len)?;
        cur = &cur[4 + ext_len..];

        if ext_type != EXT_SERVER_NAME as usize {
            continue;
        }

        // The server_name extension is itself a list: 2-byte total length,
        // then entries of type (1) + length (2) + name.
        let mut list = ext;
        let _list_len = be16(list, 0)?;
        list = list.get(2..)?;

        while list.len() >= 3 {
            let name_type = list[0];
            let name_len = be16(list, 1)?;
            let name = list.get(3..3 + name_len)?;
            list = &list[3 + name_len..];

            if name_type != SNI_HOST_NAME {
                // Other name types are not hostnames and we do not use them.
                continue;
            }

            return plausible_host(name);
        }
    }

    None
}

/// Extract a hostname from the first bytes of an HTTP/1 request, if that is
/// what this flow is.
///
/// `Host: example.com` is the cleartext equivalent of SNI for HTTP, and the
/// same domain rule should apply to it. Kept separate from [tls_sni] because
/// the two formats share nothing but the goal.
pub fn http_host(buf: &[u8]) -> Option<String> {
    let text = std::str::from_utf8(buf).ok()?;
    if !text.starts_with("GET ") && !text.starts_with("POST ")
        && !text.starts_with("HEAD ") && !text.starts_with("PUT ")
        && !text.starts_with("CONNECT ")
    {
        return None;
    }

    for line in text.split("\r\n") {
        if let Some(rest) = line.strip_prefix("Host:") {
            return plausible_host(rest.as_bytes());
        }
    }

    None
}

/// Whatever hostname these bytes announce, TLS or HTTP.
///
/// Returns the first format that yields a name. This is the one entry point
/// the caller needs: it does not have to know which kind of flow it has.
pub fn hostname(buf: &[u8]) -> Option<String> {
    tls_sni(buf).or_else(|| http_host(buf))
}

/// How many bytes of the head of a stream are worth reading.
///
/// Same value as [PEEK_BUDGET]; exists so a caller can name the intent
/// ("read the sniff head") rather than the constant.
pub fn read_budget() -> usize {
    PEEK_BUDGET
}

/// Read from `stream` into `buf` without consuming it: TCP is a stream, and
/// the bytes we inspect to learn the name are the same bytes the tunnel must
/// forward afterwards. Available on Unix, where the TUN front end runs.
#[cfg(unix)]
pub async fn peek(stream: &mut tokio::net::TcpStream, buf: &mut Vec<u8>) -> io::Result<usize> {
    use tokio::io::AsyncReadExt;
    let read = stream.read(buf).await?;
    buf.truncate(read);
    Ok(read)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A minimal ClientHello carrying one SNI, built by hand so the test does
    /// not depend on any TLS library's layout.
    fn client_hello(sni: &str) -> Vec<u8> {
        let mut ext = Vec::new();
        let name = sni.as_bytes();
        // ServerNameEntry: type 0, length, name.
        ext.push(SNI_HOST_NAME);
        ext.extend_from_slice(&(name.len() as u16).to_be_bytes());
        ext.extend_from_slice(name);
        // server_name extension body: 2-byte list length, then the entries.
        let mut ext_body = Vec::new();
        ext_body.extend_from_slice(&(ext.len() as u16).to_be_bytes());
        ext_body.extend_from_slice(&ext);
        // The extension itself: type (2) + length (2) + body.
        let mut extensions = Vec::new();
        extensions.extend_from_slice(&EXT_SERVER_NAME.to_be_bytes());
        extensions.extend_from_slice(&(ext_body.len() as u16).to_be_bytes());
        extensions.extend_from_slice(&ext_body);

        let mut hello = Vec::new();
        hello.push(TLS_CLIENT_HELLO);
        let len = 2 + 32 + 1 + 0 + 2 + 0 + 1 + 0 + 2 + extensions.len();
        hello.extend_from_slice(&[(len >> 16) as u8, (len >> 8) as u8, len as u8]);
        hello.extend_from_slice(&[0x03, 0x03]); // legacy_version
        hello.extend_from_slice(&[0u8; 32]); // random
        hello.push(0); // legacy_session_id length
        hello.extend_from_slice(&[0x00, 0x00]); // cipher_suites length
        hello.push(0); // legacy_compression_methods length
        hello.extend_from_slice(&(extensions.len() as u16).to_be_bytes());
        hello.extend_from_slice(&extensions);

        let mut record = Vec::new();
        record.push(TLS_HANDSHAKE);
        record.extend_from_slice(&[0x03, 0x01]);
        record.extend_from_slice(&(hello.len() as u16).to_be_bytes());
        record.extend_from_slice(&hello);
        record
    }

    #[test]
    fn reads_the_sni_from_a_client_hello() {
        let pkt = client_hello("www.example.com");
        assert_eq!(tls_sni(&pkt).as_deref(), Some("www.example.com"));
    }

    #[test]
    fn lowercases_the_name() {
        let pkt = client_hello("WWW.Example.COM");
        assert_eq!(tls_sni(&pkt).as_deref(), Some("www.example.com"));
    }

    #[test]
    fn a_non_tls_record_gives_nothing() {
        let pkt = b"GET / HTTP/1.1\r\nHost: example.com\r\n\r\n";
        assert!(tls_sni(pkt).is_none());
    }

    #[test]
    fn a_truncated_client_hello_gives_nothing() {
        let pkt = client_hello("www.example.com");
        assert!(tls_sni(&pkt[..20]).is_none());
    }

    #[test]
    fn no_sni_extension_gives_nothing() {
        // The same ClientHello with the SNI extension removed.
        let pkt = client_hello("www.example.com");
        // Cut the extension list: take everything up to the extension length.
        let cut = pkt.len() - 6;
        assert!(tls_sni(&pkt[..cut]).is_none());
    }

    #[test]
    fn an_ip_literal_is_not_a_hostname() {
        let pkt = client_hello("1.2.3.4");
        assert_eq!(tls_sni(&pkt), None);
    }

    #[test]
    fn http_host_is_read() {
        let req = b"GET / HTTP/1.1\r\nHost: example.com\r\n\r\n";
        assert_eq!(http_host(req).as_deref(), Some("example.com"));
        assert_eq!(hostname(req).as_deref(), Some("example.com"));
    }

    #[test]
    fn a_binary_blob_gives_nothing() {
        assert!(tls_sni(&[0xff; 64]).is_none());
        assert!(http_host(&[0xff; 64]).is_none());
    }
}
