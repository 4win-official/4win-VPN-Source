# 4Win UDP-over-TLS relay

This is the optional remote half of Mix's UDP compatibility bridge. A running public server is **not bundled or automatically deployed**. Use your own VPS, domain and trusted TLS certificate. The service accepts authenticated UDP frames over TLS; it is not a general SOCKS proxy.

## What changes in the traffic path

TCP still leaves through the selected protocol. UDP is carried through that same protocol's TCP tunnel to this additional relay, then sent to its destination. For `Psiphon → WARP`, the relay forwards encrypted WireGuard datagrams and WARP remains the final internet exit. If Psiphon or HTTP is the final block, UDP exits from this relay while TCP exits from Psiphon/HTTP. The relay is an additional trust boundary: TLS protects the transport to it, not traffic beyond it; application and inner-tunnel encryption remain independent.

Do not configure a random public relay or disable certificate verification. The app checks a system-trusted certificate against the configured TLS server name. The dial host can be an IP while the TLS server name is the certificate's DNS name.

## Prepare a server

Use Python 3.11+ or the container below. Obtain a certificate with the real relay domain in its SAN, for example with an ACME client. A development self-signed certificate is deliberately not accepted by the app.

Generate a long random token into a restricted environment file. Do not paste a real token into shell command arguments, logs, the image, or a public strategy export:

```sh
sudo install -d -m 700 /etc/4win-mix-relay
sudo sh -c 'umask 077; printf "MIX_RELAY_TOKEN=%s\n" "$(openssl rand -hex 32)" > /etc/4win-mix-relay/relay.env'
```

The protocol requires 32–256 non-space printable ASCII bytes. Supply the same token in the app. Any administrator who can inspect a running container can read its environment; use your platform's secret-management controls where available.

For the non-root container, make restricted **copies** of the certificate and key readable by UID 10001. Do not mount only an ACME `live` directory whose symlinks lead into an unmounted `archive` directory:

```sh
sudo install -d -m 750 -o 10001 -g 10001 /etc/4win-mix-relay/certs
sudo install -m 644 -o 10001 -g 10001 /etc/letsencrypt/live/YOUR_DOMAIN/fullchain.pem /etc/4win-mix-relay/certs/fullchain.pem
sudo install -m 600 -o 10001 -g 10001 /etc/letsencrypt/live/YOUR_DOMAIN/privkey.pem /etc/4win-mix-relay/certs/privkey.pem
```

## Run the container

From the repository root:

```sh
docker build -t 4win-mix-relay -f tools/mix-relay/Dockerfile tools
docker run -d --restart unless-stopped --name 4win-mix-relay \
  --read-only --cap-drop ALL --security-opt no-new-privileges \
  -p 4433:4433 \
  --env-file /etc/4win-mix-relay/relay.env \
  -v /etc/4win-mix-relay/certs:/certs:ro \
  4win-mix-relay
```

Allow inbound **TCP 4433**, not inbound UDP 4433. Allow the server's outbound UDP to the destinations you intend to use and outbound DNS if using hostname destinations. Restrict ingress to known tunnel exit networks when practical; remember that connections arrive from the last tunnel's exit IP, not necessarily the phone's IP.

The server runs as UID 10001, requires TLS 1.2+, limits concurrent sessions and destination mappings, and cleans up disconnected sessions. Private, loopback, link-local, multicast, reserved and unspecified destinations are rejected by default. `--allow-private` exists only for deliberate local/admin testing; do not enable it on a public deployment.

## Configure the app and maintain the server

In the Mix strategy editor, expand **Optional UDP-over-TLS relay**, enable it, then enter the relay host, port, TLS server name and token. This is strategy-local metadata, not another visible protocol block, and does not change standalone protocol settings or the 50-block limit. The app authenticates the relay through the selected prefix before advertising UDP capability. A failed handshake does not fall back to a physical connection.

After certificate renewal, refresh the restricted copies and restart the container so it loads the new files. Rotate a token by starting a replacement endpoint, updating client strategies, then retiring the old endpoint. Monitor resource usage and connection/error rates without recording tokens or payloads. Shared strategy JSON contains the relay token; remove it before distributing the file.

## Local verification

```sh
python3 -m unittest discover -s tools -p 'test_mix_udp_relay.py' -v
```

These tests use a temporary test certificate and loopback fixtures. They do not deploy a public endpoint or prove every protocol pair works against real providers.
