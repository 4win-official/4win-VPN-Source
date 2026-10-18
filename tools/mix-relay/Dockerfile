FROM python:3.12-slim

RUN useradd --system --uid 10001 --create-home relay
WORKDIR /app
COPY mix_udp_relay.py /app/mix_udp_relay.py
USER relay
EXPOSE 4433/tcp
ENTRYPOINT ["python", "/app/mix_udp_relay.py", "--host", "0.0.0.0", "--port", "4433", "--cert", "/certs/fullchain.pem", "--key", "/certs/privkey.pem"]
