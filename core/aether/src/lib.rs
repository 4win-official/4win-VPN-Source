mod account;
mod aethernoize;
mod apifront;
mod cli;
mod config;
mod consts;
mod dns;
mod dns_tests;
mod doh;
mod dot;
pub mod error;
mod exitip;
mod ffi;
mod fragment;
mod lastconn;
mod masque;
mod masque_h2;
mod netstack;
mod noize;
pub mod platform;
mod prober;
mod quic;
mod routing;
mod socks;
mod stackstream;
pub(crate) mod socks_upstream;
mod sysprofile;
mod tls;
mod tun;
mod tunnelping;
mod wg_prober;
mod wireguard;
mod zerotrust;

/// TLS SNI and HTTP Host extraction, used so domain routing rules work inside
/// a TUN front end where only an IP is visible. See [sniff].
mod sniff;

/// mixed-case SNI, an optional anti-DPI measure. See [sni_case].
mod sni_case;

#[path = "main.rs"]
mod app;

pub use app::{
    initialize, prepare, run_cli, start, EndpointDiscovery, IpScan, MasqueTransport, Protocol,
    ScanMode, StartOptions, TlsCurvePreset, TunnelAddresses,
};
pub use platform::{set_socket_protector, SocketProtector};