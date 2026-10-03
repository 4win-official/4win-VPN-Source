// Smoke test the DNS query builders and DoT/DoH parsers without a network.
//
// Run:  cargo test --manifest-path core/aether/Cargo.toml --lib
//       (the integration test in main.rs exercises the real stack)
#[cfg(test)]
mod tests {
    // The functions under test live in socks/dot/doh, not in the crate root;
    // name them explicitly so `use super::*` confusion cannot hide a missing
    // import as a compile error far from the test.
    use crate::dot::{dot_servers, DotServer};
    use crate::doh::{doh_servers, DohServer};
    use crate::socks::{
        build_dns_query_public, dns_response_matches_public, parse_dns_a_public, QTYPE_A,
    };
    use std::net::IpAddr;

    #[test]
    fn dot_parses_bare_ip() {
        let s = DotServer::parse("tls://1.2.3.4").unwrap();
        assert_eq!(s.addr, "1.2.3.4:853".parse().unwrap());
        assert_eq!(s.sni, "1.2.3.4");
    }

    #[test]
    fn dot_parses_explicit_port_and_sni() {
        let s = DotServer::parse("tls://1.2.3.4:5353#resolver.example").unwrap();
        assert_eq!(s.addr, "1.2.3.4:5353".parse().unwrap());
        assert_eq!(s.sni, "resolver.example");
    }

    #[test]
    fn dot_rejects_plain_ip() {
        assert!(DotServer::parse("1.2.3.4").is_none());
        assert!(DotServer::parse("https://1.2.3.4").is_none());
    }

    #[test]
    fn dot_rejects_empty() {
        assert!(DotServer::parse("tls://").is_none());
        assert!(DotServer::parse("tls://  ").is_none());
    }

    #[test]
    fn doh_parses_bare_ip() {
        let s = DohServer::parse("https://1.2.3.4").unwrap();
        assert_eq!(s.addr, "1.2.3.4:443".parse().unwrap());
        assert_eq!(s.host, "1.2.3.4");
        assert_eq!(s.path, "/dns-query");
    }

    #[test]
    fn doh_parses_host_port_and_path() {
        let s = DohServer::parse("https://1.2.3.4:8443/custom").unwrap();
        assert_eq!(s.addr, "1.2.3.4:8443".parse().unwrap());
        assert_eq!(s.host, "1.2.3.4");
        assert_eq!(s.path, "/custom");
    }

    #[test]
    fn doh_keeps_hostname_and_defers_resolution() {
        // A hostname entry (https://dns.example/dns-query) must be KEPT — it is
        // resolved at query time via the tunnel's UDP path, the same way DoT
        // handles tls://host. Dropping it here would make hostname DoH a silent
        // no-op, which is exactly the bug this guard prevents.
        let s = DohServer::parse("https://dns.example/dns-query").unwrap();
        assert_eq!(s.host, "dns.example");
        assert_eq!(s.path, "/dns-query");
        assert_eq!(s.addr.port(), 443);
        // The address itself is a placeholder until resolve_a fills it in.
        assert_eq!(s.addr.ip().to_string(), "0.0.0.0");
    }

    #[test]
    fn doh_keeps_cloudflare_family_hostname() {
        // The real entry from the bug report: hostname + no path.
        let s = DohServer::parse("https://cloudflare-dns.com").unwrap();
        assert_eq!(s.host, "cloudflare-dns.com");
        assert_eq!(s.path, "/dns-query");
    }

    #[test]
    fn doh_keeps_two_different_hostnames() {
        // Two hostname entries used to collapse into one because both got the
        // same 0.0.0.0 placeholder and dedup keyed on the address alone.
        std::env::set_var(
            "AETHER_DNS",
            "https://one.example/dns-query, https://two.example/dns-query",
        );
        let dohs = doh_servers();
        assert_eq!(dohs.len(), 2);
    }

    #[test]
    fn doh_rejects_plain_ip() {
        assert!(DohServer::parse("1.2.3.4").is_none());
        assert!(DohServer::parse("tls://1.2.3.4").is_none());
    }

    #[test]
    fn doh_rejects_empty() {
        assert!(DohServer::parse("https://").is_none());
        assert!(DohServer::parse("https:///dns-query").is_none());
    }

    #[test]
    fn doh_parses_v6() {
        let s = DohServer::parse("https://[2606:4700::6810:f0f9]").unwrap();
        assert_eq!(
            s.addr,
            "[2606:4700::6810:f0f9]:443".parse().unwrap()
        );
        assert_eq!(s.host, "[2606:4700::6810:f0f9]");
    }

    #[test]
    fn doh_parses_v6_with_port() {
        let s = DohServer::parse("https://[2606:4700::6810:f0f9]:8443/").unwrap();
        assert_eq!(
            s.addr,
            "[2606:4700::6810:f0f9]:8443".parse().unwrap()
        );
        assert_eq!(s.host, "[2606:4700::6810:f0f9]");
    }

    #[test]
    fn dot_servers_reads_only_tls_entries() {
        // An https:// entry must not appear in the DoT list, and vice versa.
        let parsed = "111.88.96.50, tls://1.1.1.1, https://8.8.8.8/dns-query";
        std::env::set_var("AETHER_DNS", parsed);
        let dots = dot_servers();
        assert_eq!(dots.len(), 1);
        assert_eq!(dots[0].addr, "1.1.1.1:853".parse::<std::net::SocketAddr>().unwrap());
        let dohs = doh_servers();
        assert_eq!(dohs.len(), 1);
        assert_eq!(dohs[0].addr, "8.8.8.8:443".parse::<std::net::SocketAddr>().unwrap());
    }

    #[test]
    fn dot_servers_empty_when_no_encrypted_entries() {
        // The single most important property for the user: plain UDP config
        // must not accidentally become a DoT/DoH attempt.
        std::env::set_var("AETHER_DNS", "111.88.96.50 111.88.96.51");
        assert!(dot_servers().is_empty());
        assert!(doh_servers().is_empty());
    }

    #[test]
    fn dot_servers_dedupes() {
        std::env::set_var("AETHER_DNS", "tls://1.1.1.1, tls://1.1.1.1:853");
        assert_eq!(dot_servers().len(), 1);
    }

    /// Round-trip: build a query, turn it into a plausible DNS reply, and
    /// verify the parser pulls the address out. This is the code path DoT and
    /// DoH both rely on; if it breaks, both break.
    #[test]
    fn dns_reply_roundtrip() {
        let (query, id) = build_dns_query_public("example.com", QTYPE_A);
        assert!(!query.is_empty());
        let mut reply = query.clone();
        // Clear the QR bit + count fields, then write an answer.
        reply[2] |= 0x80; // QR = response
        reply[3] |= 0x80; // RA
        // QDCOUNT stays 1, ANCOUNT = 1
        reply[6] = 0;
        reply[7] = 1;
        // Append: compressed name pointer to offset 12, type A, class IN, TTL,
        // rdlength 4, and the address.
        reply.extend_from_slice(&[0xc0, 0x0c]); // name pointer to question
        reply.extend_from_slice(&[0x00, 0x01]); // type A
        reply.extend_from_slice(&[0x00, 0x01]); // class IN
        reply.extend_from_slice(&[0x00, 0x00, 0x01, 0x00]); // TTL
        reply.extend_from_slice(&[0x00, 0x04]); // rdlength
        reply.extend_from_slice(&[1, 2, 3, 4]); // address

        assert!(dns_response_matches_public(&reply, id, "example.com", QTYPE_A));
        let parsed = parse_dns_a_public(&reply).unwrap();
        assert_eq!(parsed, IpAddr::V4(std::net::Ipv4Addr::new(1, 2, 3, 4)));
    }

    #[test]
    fn dns_reply_rejects_wrong_id() {
        let (query, id) = build_dns_query_public("example.com", QTYPE_A);
        let mut reply = query;
        reply[2] |= 0x80;
        reply[7] = 1;
        reply.extend_from_slice(&[0xc0, 0x0c, 0x00, 0x01, 0x00, 0x01, 0, 0, 0, 60, 0, 4, 1, 2, 3, 4]);
        // Flip the transaction id so the reply is not ours.
        let bad = id ^ 0xffff;
        assert!(!dns_response_matches_public(&reply, bad, "example.com", QTYPE_A));
    }
}
