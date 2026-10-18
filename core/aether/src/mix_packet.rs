//! Per-instance raw-IP packet ↔ smoltcp/SOCKS bridge for Mix adapters.
use serde::Deserialize;
use std::collections::HashMap;
use std::ffi::{c_char, CStr, CString};
use std::net::{IpAddr, SocketAddr};
use std::os::fd::RawFd;
use std::sync::{
    atomic::{AtomicBool, AtomicU64, Ordering},
    Arc, Mutex, OnceLock,
};
use std::thread::JoinHandle;
use tokio::io::unix::AsyncFd;
use tokio::sync::{mpsc, oneshot};

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
struct Config {
    ipv4: String,
    #[serde(default)]
    ipv6: String,
    mtu: usize,
    listen: String,
}
struct FdGuard(RawFd);
impl Drop for FdGuard {
    fn drop(&mut self) {
        if self.0 >= 0 {
            unsafe {
                libc::close(self.0);
            }
        }
    }
}
struct Instance {
    stop: Mutex<Option<oneshot::Sender<()>>>,
    join: Mutex<Option<JoinHandle<()>>>,
    cancelled: AtomicBool,
    ready: AtomicBool,
    error: Mutex<String>,
}
static INSTANCES: OnceLock<Mutex<HashMap<u64, Arc<Instance>>>> = OnceLock::new();
static NEXT: AtomicU64 = AtomicU64::new(1);
fn instances() -> &'static Mutex<HashMap<u64, Arc<Instance>>> {
    INSTANCES.get_or_init(|| Mutex::new(HashMap::new()))
}
fn set_error(i: &Instance, e: impl ToString) {
    *i.error.lock().unwrap() = e.to_string();
}
fn parse(c: &Config) -> Result<SocketAddr, String> {
    if !(576..=65535).contains(&c.mtu) {
        return Err("mtu must be between 576 and 65535".into());
    }
    if c.ipv4.trim().is_empty() && c.ipv6.trim().is_empty() {
        return Err("ipv4 or ipv6 is required".into());
    }
    if !c.ipv4.trim().is_empty() {
        let ip = c
            .ipv4
            .split('/')
            .next()
            .unwrap()
            .parse::<IpAddr>()
            .map_err(|_| format!("invalid ipv4: {}", c.ipv4))?;
        if !ip.is_ipv4() {
            return Err("ipv4 must be an IPv4 address".into());
        }
    }
    if !c.ipv6.trim().is_empty() {
        let ip = c
            .ipv6
            .split('/')
            .next()
            .unwrap()
            .parse::<IpAddr>()
            .map_err(|_| format!("invalid ipv6: {}", c.ipv6))?;
        if !ip.is_ipv6() {
            return Err("ipv6 must be an IPv6 address".into());
        }
    }
    let listen: SocketAddr = c
        .listen
        .parse()
        .map_err(|_| format!("invalid listen address: {}", c.listen))?;
    if !listen.ip().is_loopback() {
        return Err("listen must be loopback".into());
    }
    Ok(listen)
}
fn set_nonblocking(fd: RawFd) -> Result<(), String> {
    let flags = unsafe { libc::fcntl(fd, libc::F_GETFL) };
    if flags < 0 {
        return Err(std::io::Error::last_os_error().to_string());
    }
    if unsafe { libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK) } < 0 {
        return Err(std::io::Error::last_os_error().to_string());
    }
    Ok(())
}
async fn pump(
    fd: RawFd,
    mut inbound: mpsc::Sender<Vec<u8>>,
    mut outbound: mpsc::Receiver<Vec<u8>>,
) -> Result<(), String> {
    let afd = AsyncFd::new(fd).map_err(|e| e.to_string())?;
    let mut buf = vec![0u8; 65535];
    loop {
        tokio::select! {
            r = afd.readable() => { let mut guard = r.map_err(|e| e.to_string())?; loop { let n = unsafe { libc::recv(fd, buf.as_mut_ptr().cast(), buf.len(), libc::MSG_DONTWAIT) }; if n < 0 { let e=std::io::Error::last_os_error(); if e.kind()==std::io::ErrorKind::WouldBlock { break; } return Err(e.to_string()); } if n==0 { return Ok(()); } if inbound.send(buf[..n as usize].to_vec()).await.is_err() { return Ok(()); } } guard.clear_ready(); }
            Some(pkt) = outbound.recv() => { let mut guard = afd.writable().await.map_err(|e| e.to_string())?; let n = unsafe { libc::send(fd, pkt.as_ptr().cast(), pkt.len(), libc::MSG_DONTWAIT) }; if n < 0 { let e=std::io::Error::last_os_error(); if e.kind()==std::io::ErrorKind::WouldBlock { guard.clear_ready(); continue; } return Err(e.to_string()); } if n as usize != pkt.len() { return Err("packet fd performed a partial datagram write".into()); } guard.clear_ready(); }
            else => return Ok(()),
        }
    }
}
fn start_thread(
    id: u64,
    inst: Arc<Instance>,
    owned_fd: FdGuard,
    c: Config,
    listen: SocketAddr,
) -> JoinHandle<()> {
    // Capture ownership before spawn so a failed spawn also closes the duplicate.
    let fd = owned_fd.0;
    std::thread::Builder::new().name(format!("mix-packet-{id}")).spawn(move || {
        let _fd = owned_fd;
        let rt = match tokio::runtime::Builder::new_current_thread().enable_all().build() {
            Ok(runtime) => runtime,
            Err(error) => { set_error(&inst, error); return; }
        };
        rt.block_on(async move {
            if let Err(error) = set_nonblocking(fd) { set_error(&inst, error); return; }
            let listener = match tokio::net::TcpListener::bind(listen).await {
                Ok(listener) => listener,
                Err(error) => { set_error(&inst, error); return; }
            };
            let (in_tx, in_rx) = mpsc::channel(256);
            let (out_tx, out_rx) = mpsc::channel(256);
            let stack = match crate::netstack::spawn(&c.ipv4, &c.ipv6, c.mtu, in_rx, out_tx) {
                Ok(stack) => stack,
                Err(error) => { set_error(&inst, error); return; }
            };
            let (stop_tx, mut stop_rx) = oneshot::channel();
            {
                let mut pending = inst.stop.lock().unwrap();
                if inst.cancelled.load(Ordering::Acquire) { return; }
                *pending = Some(stop_tx);
            }
            let mut socks = tokio::spawn(crate::socks::serve_bound_stack(listener, stack));
            let mut packet = tokio::spawn(pump(fd, in_tx, out_rx));
            inst.ready.store(true, Ordering::Release);
            let completed = tokio::select! {
                _ = &mut stop_rx => 0,
                result = &mut socks => { if let Ok(Err(error)) = result { set_error(&inst, error); } 1 },
                result = &mut packet => { if let Ok(Err(error)) = result { set_error(&inst, error); } 2 },
            };
            inst.ready.store(false, Ordering::Release);
            let _ = inst.stop.lock().unwrap().take();
            socks.abort();
            packet.abort();
            // A JoinHandle already consumed by select must never be polled again.
            if completed != 1 { let _ = socks.await; }
            if completed != 2 { let _ = packet.await; }
        });
    }).expect("failed to spawn Mix packet thread")
}
unsafe fn cstr(p: *const c_char) -> Result<String, String> {
    if p.is_null() {
        return Err("null config".into());
    }
    CStr::from_ptr(p)
        .to_str()
        .map(str::to_owned)
        .map_err(|_| "config is not utf-8".into())
}
#[no_mangle]
pub unsafe extern "C" fn aether_mix_packet_create(json: *const c_char, fd: i32) -> i64 {
    match std::panic::catch_unwind(|| {
        if fd < 0 {
            return Err("invalid packet fd".into());
        };
        let text = unsafe { cstr(json)? };
        let c: Config = serde_json::from_str(&text).map_err(|e| e.to_string())?;
        let listen = parse(&c)?;
        let dup = unsafe { libc::dup(fd) };
        if dup < 0 {
            return Err(std::io::Error::last_os_error().to_string());
        };
        let id = NEXT.fetch_add(1, Ordering::Relaxed);
        let inst = Arc::new(Instance {
            stop: Mutex::new(None),
            join: Mutex::new(None),
            cancelled: AtomicBool::new(false),
            ready: AtomicBool::new(false),
            error: Mutex::new(String::new()),
        });
        let join = start_thread(id, inst.clone(), FdGuard(dup), c, listen);
        *inst.join.lock().unwrap() = Some(join);
        instances().lock().unwrap().insert(id, inst);
        Ok(id as i64)
    }) {
        Ok(Ok(id)) => id,
        Ok(Err(_)) => -1,
        Err(_) => -2,
    }
}
#[no_mangle]
pub extern "C" fn aether_mix_packet_is_ready(id: i64) -> i32 {
    instances()
        .lock()
        .unwrap()
        .get(&(id as u64))
        .map(|i| i.ready.load(Ordering::Acquire) as i32)
        .unwrap_or(0)
}
#[no_mangle]
pub extern "C" fn aether_mix_packet_start(id: i64) -> i32 {
    if instances().lock().unwrap().contains_key(&(id as u64)) {
        0
    } else {
        -1
    }
}
#[no_mangle]
pub extern "C" fn aether_mix_packet_last_error(id: i64) -> *const c_char {
    let s = instances()
        .lock()
        .unwrap()
        .get(&(id as u64))
        .map(|i| i.error.lock().unwrap().clone())
        .unwrap_or_else(|| "unknown handle".into());
    thread_local! {static LAST:std::cell::RefCell<CString>=std::cell::RefCell::new(CString::default());}
    LAST.with(|slot| {
        *slot.borrow_mut() = CString::new(s).unwrap_or_default();
        slot.borrow().as_ptr()
    })
}
#[no_mangle]
pub extern "C" fn aether_mix_packet_stop(id: i64) -> i32 {
    let inst = instances().lock().unwrap().remove(&(id as u64));
    let Some(inst) = inst else { return -1 };
    inst.cancelled.store(true, Ordering::Release);
    if let Some(tx) = inst.stop.lock().unwrap().take() {
        let _ = tx.send(());
    }
    if let Some(join) = inst.join.lock().unwrap().take() {
        let _ = join.join();
    }
    0
}
#[cfg(test)]
mod tests {
    use super::*;
    #[cfg(unix)]
    use std::io::{Read, Write};
    #[cfg(unix)]
    use std::net::{Ipv4Addr, TcpListener, TcpStream, UdpSocket};
    #[cfg(unix)]
    use std::os::fd::AsRawFd;
    #[cfg(unix)]
    use std::os::unix::net::UnixDatagram;
    #[cfg(unix)]
    use std::time::{Duration, Instant};

    #[cfg(unix)]
    struct HandleGuard(i64);

    #[cfg(unix)]
    impl Drop for HandleGuard {
        fn drop(&mut self) {
            if self.0 > 0 {
                let _ = aether_mix_packet_stop(self.0);
                self.0 = -1;
            }
        }
    }

    #[cfg(unix)]
    fn checksum(data: &[u8]) -> u16 {
        let mut sum = 0u32;
        for word in data.chunks(2) {
            sum += u16::from_be_bytes([word[0], *word.get(1).unwrap_or(&0)]) as u32;
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xffff) + (sum >> 16);
        }
        !(sum as u16)
    }

    #[cfg(unix)]
    fn make_udp_packet(src: (Ipv4Addr, u16), dst: (Ipv4Addr, u16), data: &[u8]) -> Vec<u8> {
        let udp_len = 8 + data.len();
        let total_len = 20 + udp_len;
        let mut packet = vec![0u8; total_len];
        packet[0] = 0x45;
        packet[2..4].copy_from_slice(&(total_len as u16).to_be_bytes());
        packet[8] = 64;
        packet[9] = 17;
        packet[12..16].copy_from_slice(&src.0.octets());
        packet[16..20].copy_from_slice(&dst.0.octets());
        packet[20..22].copy_from_slice(&src.1.to_be_bytes());
        packet[22..24].copy_from_slice(&dst.1.to_be_bytes());
        packet[24..26].copy_from_slice(&(udp_len as u16).to_be_bytes());
        packet[28..].copy_from_slice(data);
        let mut pseudo = Vec::with_capacity(12 + udp_len);
        pseudo.extend_from_slice(&src.0.octets());
        pseudo.extend_from_slice(&dst.0.octets());
        pseudo.extend_from_slice(&[0, 17]);
        pseudo.extend_from_slice(&(udp_len as u16).to_be_bytes());
        pseudo.extend_from_slice(&packet[20..]);
        let udp_sum = checksum(&pseudo);
        packet[26..28].copy_from_slice(&udp_sum.to_be_bytes());
        let ip_sum = checksum(&packet[..20]);
        packet[10..12].copy_from_slice(&ip_sum.to_be_bytes());
        packet
    }

    #[cfg(unix)]
    fn read_exact_timeout(stream: &mut TcpStream, buf: &mut [u8]) {
        stream.read_exact(buf).expect("SOCKS response within timeout");
    }

    #[cfg(unix)]
    fn read_udp_frame(socket: &UdpSocket) -> Vec<u8> {
        let mut frame = vec![0u8; 2048];
        let n = socket.recv(&mut frame).expect("SOCKS UDP reply within timeout");
        frame.truncate(n);
        frame
    }

    #[test]
    fn config_validation() {
        assert!(parse(&Config {
            ipv4: "bad".into(),
            ipv6: "".into(),
            mtu: 1500,
            listen: "127.0.0.1:1".into()
        })
        .is_err());
        assert!(parse(&Config {
            ipv4: "10.0.0.2/24".into(),
            ipv6: "".into(),
            mtu: 1500,
            listen: "127.0.0.1:1".into()
        })
        .is_ok());
        assert!(parse(&Config {
            ipv4: "::1".into(),
            ipv6: "".into(),
            mtu: 1500,
            listen: "127.0.0.1:1".into()
        })
        .is_err());
    }

    /// Exercises the real native packet bridge, rather than only validating its JSON.
    /// The peer is an AF_UNIX SOCK_DGRAM socket because that is the same raw packet
    /// contract used by the SSTP/OpenVPN adapters, and all traffic remains offline.
    #[cfg(target_os = "linux")]
    #[test]
    fn native_unix_datagram_socks_udp_raw_ipv4_roundtrip() {
        for iteration in 0..3 {
            eprintln!("mix_packet integration iteration {iteration}: create");
            let (peer, bridge) = UnixDatagram::pair().expect("AF_UNIX datagram pair");
            peer.set_read_timeout(Some(Duration::from_secs(3))).unwrap();
            peer.set_write_timeout(Some(Duration::from_secs(3))).unwrap();

            let reservation = TcpListener::bind("127.0.0.1:0").unwrap();
            let listen = reservation.local_addr().unwrap();
            drop(reservation);
            let json = CString::new(format!(
                r#"{{"ipv4":"10.0.0.2","ipv6":"","mtu":1280,"listen":"{}"}}"#,
                listen
            ))
            .unwrap();
            let id = unsafe { aether_mix_packet_create(json.as_ptr(), bridge.as_raw_fd()) };
            assert!(id > 0, "iteration {iteration}: create failed");
            let mut guard = HandleGuard(id);
            drop(bridge);

            let deadline = Instant::now() + Duration::from_secs(5);
            while aether_mix_packet_is_ready(id) == 0 {
                assert!(Instant::now() < deadline, "iteration {iteration}: bridge not ready");
                std::thread::sleep(Duration::from_millis(10));
            }
            eprintln!("mix_packet integration iteration {iteration}: ready");

            let mut control = TcpStream::connect(listen).expect("real SOCKS listener");
            control.set_read_timeout(Some(Duration::from_secs(3))).unwrap();
            control.set_write_timeout(Some(Duration::from_secs(3))).unwrap();
            control.write_all(&[5, 1, 0]).unwrap();
            let mut method = [0u8; 2];
            read_exact_timeout(&mut control, &mut method);
            assert_eq!(method, [5, 0]);
            eprintln!("mix_packet integration iteration {iteration}: socks hello");

            let udp = UdpSocket::bind("127.0.0.1:0").unwrap();
            udp.set_read_timeout(Some(Duration::from_secs(3))).unwrap();
            udp.set_write_timeout(Some(Duration::from_secs(3))).unwrap();
            control.write_all(&[5, 3, 0, 1, 0, 0, 0, 0, 0, 0]).unwrap();
            let mut associate = [0u8; 10];
            read_exact_timeout(&mut control, &mut associate);
            assert_eq!(&associate[..4], &[5, 0, 0, 1]);
            eprintln!("mix_packet integration iteration {iteration}: udp associate");
            let relay = SocketAddr::new(
                Ipv4Addr::new(associate[4], associate[5], associate[6], associate[7]).into(),
                u16::from_be_bytes([associate[8], associate[9]]),
            );

            let mut request = vec![0, 0, 0, 1, 198, 51, 100, 7, 0x23, 0x28];
            request.extend_from_slice(b"hello");
            udp.send_to(&request, relay).unwrap();
            let mut raw = vec![0u8; 2048];
            let raw_len = peer.recv(&mut raw).expect("raw outbound IPv4 UDP packet");
            eprintln!("mix_packet integration iteration {iteration}: raw outbound");
            raw.truncate(raw_len);
            assert_eq!(raw[0] >> 4, 4);
            let ihl = (raw[0] & 0x0f) as usize * 4;
            assert_eq!(raw[9], 17);
            assert_eq!(&raw[16..20], &[198, 51, 100, 7]);
            assert_eq!(u16::from_be_bytes([raw[ihl + 2], raw[ihl + 3]]), 9000);
            assert_eq!(&raw[ihl + 8..], b"hello");
            assert_eq!(checksum(&raw[..ihl]), 0);
            let mut pseudo = Vec::new();
            pseudo.extend_from_slice(&raw[12..16]);
            pseudo.extend_from_slice(&raw[16..20]);
            pseudo.extend_from_slice(&[0, 17]);
            pseudo.extend_from_slice(&raw[ihl + 4..ihl + 6]);
            pseudo.extend_from_slice(&raw[ihl..]);
            assert_eq!(checksum(&pseudo), 0);

            let src_ip = Ipv4Addr::new(raw[12], raw[13], raw[14], raw[15]);
            let src_port = u16::from_be_bytes([raw[ihl], raw[ihl + 1]]);
            let reply = make_udp_packet(
                (Ipv4Addr::new(198, 51, 100, 7), 9000),
                (src_ip, src_port),
                b"world",
            );
            peer.send(&reply).unwrap();
            let frame = read_udp_frame(&udp);
            eprintln!("mix_packet integration iteration {iteration}: udp reply");
            assert_eq!(&frame[..4], &[0, 0, 0, 1]);
            assert_eq!(&frame[4..8], &[198, 51, 100, 7]);
            assert_eq!(u16::from_be_bytes([frame[8], frame[9]]), 9000);
            assert_eq!(&frame[10..], b"world");

            drop(udp);
            drop(control);
            assert_eq!(aether_mix_packet_stop(id), 0);
            guard.0 = -1;
            assert!(TcpStream::connect_timeout(&listen, Duration::from_millis(200)).is_err());
            eprintln!("mix_packet integration iteration {iteration}: stopped");
        }
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn cancellation_before_ready_and_packet_worker_exit_are_drained() {
        for iteration in 0..17 {
            let (peer, bridge) = UnixDatagram::pair().unwrap();
            let reservation = TcpListener::bind("127.0.0.1:0").unwrap();
            let listen = reservation.local_addr().unwrap();
            drop(reservation);
            let json = CString::new(format!(
                r#"{{"ipv4":"10.0.0.2","ipv6":"","mtu":1280,"listen":"{listen}"}}"#
            )).unwrap();
            let id = unsafe { aether_mix_packet_create(json.as_ptr(), bridge.as_raw_fd()) };
            assert!(id > 0);
            let mut guard = HandleGuard(id);
            drop(bridge);
            if iteration == 16 {
                let deadline = Instant::now() + Duration::from_secs(3);
                while aether_mix_packet_is_ready(id) == 0 {
                    assert!(Instant::now() < deadline, "bridge did not become ready");
                    std::thread::sleep(Duration::from_millis(5));
                }
                // A zero-length raw datagram ends the packet worker. The SOCKS
                // task must be aborted, and its completed peer never re-polled.
                peer.send(&[]).unwrap();
                while aether_mix_packet_is_ready(id) != 0 {
                    assert!(Instant::now() < deadline, "packet worker did not stop");
                    std::thread::sleep(Duration::from_millis(5));
                }
            }
            assert_eq!(aether_mix_packet_stop(id), 0);
            guard.0 = -1;
            assert!(TcpStream::connect_timeout(&listen, Duration::from_millis(200)).is_err());
        }
    }
}
