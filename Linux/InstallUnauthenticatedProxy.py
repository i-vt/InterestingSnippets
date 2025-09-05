#!/usr/bin/env bash
set -euo pipefail

# === Config / Args ===
PORT="${1:-3128}"
HOST="0.0.0.0"
SERVICE_NAME="python-proxy.service"
UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}"
APP_DIR="/opt/proxy"
APP_FILE="${APP_DIR}/proxy.py"
USER_NAME="proxyuser"
GROUP_NAME="${USER_NAME}"
PYTHON_BIN="$(command -v python3 || true)"

if [[ -z "${PYTHON_BIN}" ]]; then
  echo "python3 not found. Please install Python 3 first." >&2
  exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root (use sudo)." >&2
  exit 1
fi

# === Create system user ===
if ! id -u "${USER_NAME}" &>/dev/null; then
  useradd --system --no-create-home --shell /usr/sbin/nologin "${USER_NAME}"
fi

# === Install app ===
mkdir -p "${APP_DIR}"

# Only write proxy.py if it doesn't already exist
if [[ ! -f "${APP_FILE}" ]]; then
  cat > "${APP_FILE}" <<'PYCODE'
#!/usr/bin/env python3
"""
Minimal unauthenticated HTTP/HTTPS proxy (asyncio).
Bind to 0.0.0.0 and any port you like.

Usage: python3 proxy.py --host 0.0.0.0 --port 8080
"""
import asyncio
import argparse
import logging
from urllib.parse import urlsplit

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
LOG = logging.getLogger("proxy")

async def pipe(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    try:
        while True:
            data = await reader.read(65536)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except Exception as e:
        LOG.debug("pipe exception: %s", e)
    finally:
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass

async def handle_client(client_reader: asyncio.StreamReader, client_writer: asyncio.StreamWriter):
    peer = client_writer.get_extra_info("peername")
    LOG.info("Connection from %s", peer)
    try:
        # Read headers
        header_bytes = await client_reader.readuntil(b"\r\n\r\n")
    except asyncio.IncompleteReadError:
        LOG.warning("Incomplete header from %s", peer)
        client_writer.close()
        return
    except Exception as e:
        LOG.warning("Error reading headers from %s: %s", peer, e)
        client_writer.close()
        return

    header_text = header_bytes.decode(errors="ignore")
    first_line, rest = header_text.split("\r\n", 1)
    parts = first_line.split()
    if len(parts) < 3:
        LOG.warning("Malformed request line from %s: %r", peer, first_line)
        client_writer.close()
        return
    method, path, proto = parts[0], parts[1], parts[2]
    headers_part, _, _ = rest.partition("\r\n\r\n")
    headers_lines = headers_part.split("\r\n")
    headers = {}
    for h in headers_lines:
        if ":" in h:
            k, v = h.split(":", 1)
            headers[k.strip().lower()] = v.strip()

    # If there's a request body already available (rare), read it based on Content-Length
    body = b""
    content_len = headers.get("content-length")
    if content_len and content_len.isdigit():
        to_read = int(content_len)
        if to_read > 0:
            body = await client_reader.readexactly(to_read)

    if method.upper() == "CONNECT":
        # path is host:port
        host_port = path.split(":")
        host = host_port[0]
        port = int(host_port[1]) if len(host_port) > 1 else 443
        LOG.info("CONNECT %s:%d from %s", host, port, peer)
        try:
            remote_reader, remote_writer = await asyncio.open_connection(host, port)
        except Exception as e:
            LOG.warning("Failed CONNECT to %s:%d: %s", host, port, e)
            client_writer.write(f"{proto} 502 Bad Gateway\r\n\r\n".encode())
            await client_writer.drain()
            client_writer.close()
            return

        client_writer.write(f"{proto} 200 Connection established\r\n\r\n".encode())
        await client_writer.drain()

        await asyncio.gather(
            pipe(client_reader, remote_writer),
            pipe(remote_reader, client_writer),
        )
        LOG.info("CONNECT closed %s:%d", host, port)
    else:
        LOG.info("%s %s from %s", method, path, peer)
        upstream_host = None
        upstream_port = 80
        if path.startswith("http://") or path.startswith("https://"):
            u = urlsplit(path)
            upstream_host = u.hostname
            upstream_port = u.port or (443 if u.scheme == "https" else 80)
            new_path = u.path or "/"
            if u.query:
                new_path += "?" + u.query
        else:
            host_hdr = headers.get("host")
            if not host_hdr:
                LOG.warning("No Host header from %s", peer)
                client_writer.write(f"{proto} 400 Bad Request\r\n\r\n".encode())
                await client_writer.drain()
                client_writer.close()
                return
            if ":" in host_hdr:
                upstream_host, port_str = host_hdr.split(":", 1)
                upstream_port = int(port_str)
            else:
                upstream_host = host_hdr
                upstream_port = 80
            new_path = path

        try:
            remote_reader, remote_writer = await asyncio.open_connection(upstream_host, upstream_port)
        except Exception as e:
            LOG.warning("Failed connect to upstream %s:%d: %s", upstream_host, upstream_port, e)
            client_writer.write(f"{proto} 502 Bad Gateway\r\n\r\n".encode())
            await client_writer.drain()
            client_writer.close()
            return

        new_first_line = f"{method} {new_path} {proto}\r\n"
        header_lines = []
        for k, v in headers.items():
            header_lines.append(f"{k}: {v}")
        header_raw = "\r\n".join(header_lines)
        full_request = (new_first_line + header_raw + "\r\n\r\n").encode() + body

        try:
            remote_writer.write(full_request)
            await remote_writer.drain()
        except Exception as e:
            LOG.warning("Error sending to upstream %s:%d: %s", upstream_host, upstream_port, e)
            client_writer.close()
            remote_writer.close()
            return

        await asyncio.gather(
            pipe(client_reader, remote_writer),
            pipe(remote_reader, client_writer),
        )
        LOG.info("HTTP request finished for %s %s", upstream_host, new_path)

    try:
        client_writer.close()
        await client_writer.wait_closed()
    except Exception:
        pass

async def main(host: str, port: int):
    server = await asyncio.start_server(handle_client, host, port)
    addrs = ", ".join(str(sock.getsockname()) for sock in server.sockets)
    LOG.info("Serving on %s", addrs)
    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Minimal unauthenticated proxy")
    parser.add_argument("--host", default="0.0.0.0", help="Bind address (default 0.0.0.0)")
    parser.add_argument("--port", type=int, default=8080, help="Port to listen on")
    args = parser.parse_args()
    try:
        asyncio.run(main(args.host, args.port))
    except KeyboardInterrupt:
        LOG.info("Shutting down")
PYCODE
  chmod +x "${APP_FILE}"
fi

chown -R "${USER_NAME}:${GROUP_NAME}" "${APP_DIR}"

# === Create / update systemd unit ===
cat > "${UNIT_PATH}" <<UNIT
[Unit]
Description=Minimal Python Proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${USER_NAME}
Group=${GROUP_NAME}
WorkingDirectory=${APP_DIR}
ExecStart=${PYTHON_BIN} ${APP_FILE} --host ${HOST} --port ${PORT}
Restart=on-failure
RestartSec=2
LimitNOFILE=65536

# Allow binding to low ports if desired
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ProtectControlGroups=true
ProtectKernelLogs=true
ProtectKernelModules=true
ProtectKernelTunables=true
RestrictAddressFamilies=AF_INET AF_INET6
LockPersonality=true
MemoryDenyWriteExecute=true
RestrictRealtime=true
SystemCallArchitectures=native

[Install]
WantedBy=multi-user.target
UNIT

# === Reload + enable service ===
systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}"

# === Optional: open firewall if tool is present ===
if command -v ufw &>/dev/null; then
  if ufw status | grep -q "Status: active"; then
    ufw allow "${PORT}/tcp" || true
  fi
elif command -v firewall-cmd &>/dev/null; then
  firewall-cmd --add-port="${PORT}/tcp" --permanent || true
  firewall-cmd --reload || true
fi

# === Show status summary ===
echo "==== Service status ===="
systemctl --no-pager --full status "${SERVICE_NAME}" || true
echo "==== Journal (last 20 lines) ===="
journalctl -u "${SERVICE_NAME}" -n 20 --no-pager || true

echo
echo "Deployed. Listening on ${HOST}:${PORT}."
echo "To change the port later: sudo sed -i 's/--port [0-9]\\+/--port NEWPORT/' '${UNIT_PATH}' && sudo systemctl daemon-reload && sudo systemctl restart '${SERVICE_NAME}'"
echo
echo "To completely remove the proxy service, run:"
echo "  sudo systemctl disable --now python-proxy.service"
echo "  sudo rm -f /etc/systemd/system/python-proxy.service"
echo "  sudo systemctl daemon-reload"
echo "  # optional cleanup:"
echo "  sudo rm -rf /opt/proxy"
echo "  sudo userdel proxyuser 2>/dev/null || true"
