use super::*;
use std::net::SocketAddr;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, UdpSocket};
use tokio::sync::oneshot;

/// Exercises the complete Mix transport path: WgTunnel performs a real
/// boringtun handshake and encrypted payload exchange, while every datagram
/// traverses the local SOCKS5 UDP relay. This deliberately uses a local peer,
/// not a public WARP account or Cloudflare endpoint.
#[tokio::test]
async fn mix_wg_data_plane_round_trips_through_socks_udp_and_real_peer() {
    let proxy_listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let proxy_addr = proxy_listener.local_addr().unwrap();
    let peer_socket = UdpSocket::bind("127.0.0.1:0").await.unwrap();
    let peer_addr = peer_socket.local_addr().unwrap();
    let (ready_tx, ready_rx) = oneshot::channel::<SocketAddr>();

    let proxy = tokio::spawn(async move {
        let (mut control, _) = proxy_listener.accept().await.unwrap();
        let mut greeting = [0u8; 3];
        control.read_exact(&mut greeting).await.unwrap();
        assert_eq!(greeting, [5, 1, 0]);
        control.write_all(&[5, 0]).await.unwrap();
        let mut associate = [0u8; 10];
        control.read_exact(&mut associate).await.unwrap();
        assert_eq!(associate, [5, 3, 0, 1, 0, 0, 0, 0, 0, 0]);

        let relay = UdpSocket::bind("127.0.0.1:0").await.unwrap();
        let relay_addr = relay.local_addr().unwrap();
        let mut reply = vec![5, 0, 0, 1];
        reply.extend_from_slice(
            &relay_addr
                .ip()
                .to_string()
                .parse::<std::net::Ipv4Addr>()
                .unwrap()
                .octets(),
        );
        reply.extend_from_slice(&relay_addr.port().to_be_bytes());
        control.write_all(&reply).await.unwrap();
        ready_tx.send(relay_addr).unwrap();
        let peer_forward = UdpSocket::bind("127.0.0.1:0").await.unwrap();

        let mut client_addr: Option<SocketAddr> = None;
        let mut frame = vec![0u8; 65536];
        loop {
            tokio::select! {
                result = relay.recv_from(&mut frame) => {
                    let (n, source) = result.unwrap();
                    if client_addr.is_none() { client_addr = Some(source); }
                    if source == client_addr.unwrap() {
                        assert!(n >= 10, "short SOCKS UDP request");
                        assert_eq!(&frame[..3], &[0, 0, 0]);
                        let atyp = frame[3];
                        assert_eq!(atyp, 1, "WireGuard peer must be IPv4 in this test");
                        peer_forward.send_to(&frame[10..n], peer_addr).await.unwrap();
                    } else {
                        let client = client_addr.unwrap();
                        let mut wrapped = Vec::with_capacity(n + 10);
                        wrapped.extend_from_slice(&[0, 0, 0, 1]);
                        wrapped.extend_from_slice(&[127, 0, 0, 1]);
                        wrapped.extend_from_slice(&peer_addr.port().to_be_bytes());
                        wrapped.extend_from_slice(&frame[..n]);
                        relay.send_to(&wrapped, client).await.unwrap();
                    }
                }
                // Keep the SOCKS control stream alive for the lifetime of the
                // transport; WgUdpSocket treats its closure as terminal.
                result = control.readable() => {
                    result.unwrap();
                    let mut one = [0u8; 1];
                    match control.try_read(&mut one) {
                        Ok(0) => break,
                        Ok(_) => panic!("unexpected SOCKS control data"),
                        Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => continue,
                        Err(error) => panic!("SOCKS control failure: {error}"),
                    }
                }
            }
        }
    });

    let client_secret = [7u8; 32];
    let peer_secret = [9u8; 32];
    let client_public = PublicKey::from(&StaticSecret::from(client_secret)).to_bytes();
    let peer_public = PublicKey::from(&StaticSecret::from(peer_secret)).to_bytes();
    let mut peer_tunn = Tunn::new(
        StaticSecret::from(peer_secret),
        PublicKey::from(client_public),
        None,
        None,
        0,
        None,
    );

    let (inbound_tx, mut inbound_rx) = mpsc::channel(1);
    let cfg = WgConfig {
        local_private_key: client_secret,
        peer_public_key: peer_public,
        peer_endpoint: peer_addr,
        local_ipv4: "172.16.0.2".parse().unwrap(),
        local_ipv6: Ipv6Addr::UNSPECIFIED,
        client_id: [0, 0, 3],
        preshared_key: None,
        persistent_keepalive: None,
        aethernoize: Arc::new(AetherNoizeConfig::off()),
    };
    let tunnel = tokio::time::timeout(
        Duration::from_secs(5),
        WgTunnel::new_with_upstream(cfg, inbound_tx, Some(&format!("socks5h://{proxy_addr}"))),
    )
    .await
    .expect("SOCKS setup timed out")
    .unwrap();
    let relay_addr = ready_rx.await.expect("SOCKS relay did not become ready");
    let (outbound_tx, outbound_rx) = mpsc::channel(2);
    let tunnel_task = tokio::spawn(tunnel.run(outbound_rx));

    let payload = vec![
        0x45, 0, 0, 28, 0, 1, 0, 0, 64, 17, 0, 0, 172, 16, 0, 2, 192, 0, 2, 1, 0x30, 0x39, 0x00,
        0x35, 0, 8, 0, 0,
    ];
    tokio::time::timeout(Duration::from_secs(5), outbound_tx.send(payload.clone()))
        .await
        .expect("outbound queue send timed out")
        .unwrap();
    // WgTunnel emits the initial handshake in response to the first packet;
    // retry the IP packet once that handshake has completed.
    tokio::time::sleep(Duration::from_millis(100)).await;
    outbound_tx.send(payload.clone()).await.unwrap();
    let retry_tx = outbound_tx.clone();
    let retry_payload = payload.clone();
    let retry_task = tokio::spawn(async move {
        for _ in 0..20 {
            tokio::time::sleep(Duration::from_millis(100)).await;
            if retry_tx.send(retry_payload.clone()).await.is_err() {
                break;
            }
        }
    });

    let mut encrypted = vec![0u8; 65536];
    let plaintext = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let n = peer_socket.recv(&mut encrypted).await.unwrap();
            let mut clear = vec![0u8; 65536];
            let mut peer_packet = encrypted[..n].to_vec();
            peer_packet[1..4].copy_from_slice(&[0, 0, 0]);
            match peer_tunn.decapsulate(None, &peer_packet, &mut clear) {
                TunnResult::WriteToNetwork(packet) => {
                    let mut response = packet.to_vec();
                    response[1..4].copy_from_slice(&[0, 0, 3]);
                    peer_socket.send_to(&response, relay_addr).await.unwrap();
                }
                TunnResult::WriteToTunnelV4(packet, _) | TunnResult::WriteToTunnelV6(packet, _) => {
                    break packet.to_vec();
                }
                TunnResult::Done => {}
                TunnResult::Err(error) => panic!("local peer failed to decrypt: {error:?}"),
            }
        }
    })
    .await
    .unwrap();
    assert_eq!(
        plaintext, payload,
        "peer decrypted the exact outbound IP packet"
    );

    let mut reply = payload.clone();
    reply[19] = 99;
    let mut encrypted_reply = vec![0u8; 65536];
    let encrypted_reply = match peer_tunn.encapsulate(&reply, &mut encrypted_reply) {
        TunnResult::WriteToNetwork(packet) => {
            let mut response = packet.to_vec();
            response[1..4].copy_from_slice(&[0, 0, 3]);
            response
        }
        other => panic!("local peer did not encrypt reply: {other:?}"),
    };
    peer_socket
        .send_to(&encrypted_reply, relay_addr)
        .await
        .unwrap();
    let received = tokio::time::timeout(Duration::from_secs(5), inbound_rx.recv())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        received, reply,
        "encrypted peer reply reached WgTunnel inbound"
    );

    retry_task.abort();
    drop(outbound_tx);
    tunnel_task.abort();
    proxy.abort();
}
