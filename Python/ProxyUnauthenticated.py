#!/usr/bin/env python3
"""
Multi-protocol proxy server supporting both HTTP and SOCKS5.

Supported protocols:
- HTTP CONNECT tunneling (for HTTPS)
- HTTP request proxying (absolute-form and origin-form)
- SOCKS5 connections with no authentication

Features:
- Robust error handling and timeout management
- IPv6 support
- Chunked transfer encoding
- Header injection protection
- Production-ready resource management
- Fixed SOCKS5 relay for browser compatibility
"""
import asyncio
import re
import sys
import logging
from urllib.parse import urlsplit
from typing import Optional, Dict, Tuple

# Configuration
HOST = "0.0.0.0"            # bind address (keep localhost to avoid creating an open proxy)
PORT = 8080                 # listening port
READ_TIMEOUT = 15.0         # seconds
CONNECT_TIMEOUT = 10.0      # seconds for connecting to origin servers
DRAIN_TIMEOUT = 5.0         # seconds for drain operations
MAX_BODY_READ_TIMEOUT = 300.0  # max 5 minutes for reading large bodies
MAX_REQ_LINE = 8192
MAX_HEADER_BYTES = 64 * 1024
MAX_BODY_SIZE = 100 * 1024 * 1024  # 100MB max body size
RELAY_CHUNK_SIZE = 65536

# SOCKS5 Constants
SOCKS5_VERSION = 0x05
SOCKS5_NO_AUTH = 0x00
SOCKS5_NO_ACCEPTABLE_METHODS = 0xFF
SOCKS5_CONNECT = 0x01
SOCKS5_IPv4 = 0x01
SOCKS5_DOMAIN = 0x03
SOCKS5_IPv6 = 0x04
SOCKS5_SUCCESS = 0x00
SOCKS5_GENERAL_FAILURE = 0x01
SOCKS5_CONNECTION_NOT_ALLOWED = 0x02
SOCKS5_NETWORK_UNREACHABLE = 0x03
SOCKS5_HOST_UNREACHABLE = 0x04
SOCKS5_CONNECTION_REFUSED = 0x05
SOCKS5_TTL_EXPIRED = 0x06
SOCKS5_COMMAND_NOT_SUPPORTED = 0x07
SOCKS5_ADDRESS_TYPE_NOT_SUPPORTED = 0x08

CRLF = b"\r\n"

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Connection tracking for debugging
active_connections = 0
connection_counter = 0


class CaseInsensitiveDict(dict):
    def __setitem__(self, key, value):
        super().__setitem__(key.lower(), value)
    def __getitem__(self, key):
        return super().__getitem__(key.lower())
    def get(self, key, default=None):
        return super().get(key.lower(), default)
    def pop(self, key, default=None):
        return super().pop(key.lower(), default)
    def __contains__(self, key):
        return super().__contains__(key.lower())
    def items_ci(self):
        for k, v in self.items():
            yield k, v


def sanitize_header_value(value: str) -> str:
    """Sanitize header value to prevent CRLF injection."""
    return value.replace('\r', '').replace('\n', '')


async def safe_close_writer(writer: asyncio.StreamWriter, name: str = "writer"):
    """Safely close a writer with proper error handling."""
    if writer and not writer.is_closing():
        try:
            writer.close()
            await asyncio.wait_for(writer.wait_closed(), timeout=2.0)
        except Exception as e:
            logger.debug(f"Error closing {name}: {e}")


async def safe_drain(writer: asyncio.StreamWriter, timeout: float = DRAIN_TIMEOUT) -> bool:
    """Safely drain a writer with timeout."""
    try:
        await asyncio.wait_for(writer.drain(), timeout=timeout)
        return True
    except (asyncio.TimeoutError, ConnectionError, OSError) as e:
        logger.debug(f"Drain failed: {e}")
        return False


async def relay_data_stream(reader: asyncio.StreamReader,
                            writer: asyncio.StreamWriter,
                            name: str) -> None:
    """
    Relay data between reader and writer for long-lived tunnels (CONNECT/SOCKS).
    Returns when EOF, timeout, or error occurs. Caller decides when to close.
    """
    bytes_transferred = 0
    try:
        while not writer.is_closing() and not reader.at_eof():
            try:
                # 30s idle timeout; raise if no bytes arrive for that long.
                chunk = await asyncio.wait_for(reader.read(RELAY_CHUNK_SIZE), timeout=30.0)
                if not chunk:
                    logger.debug(f"{name}: EOF reached (transferred {bytes_transferred} bytes)")
                    break
                bytes_transferred += len(chunk)
                writer.write(chunk)
                if not await safe_drain(writer):
                    logger.debug(f"{name}: Drain failed, stopping relay")
                    break
            except asyncio.TimeoutError:
                logger.debug(f"{name}: 30s idle timeout (transferred {bytes_transferred} bytes)")
                break
            except (ConnectionError, OSError, ConnectionResetError) as e:
                logger.debug(f"{name}: Connection error after {bytes_transferred} bytes: {e}")
                break
    except asyncio.CancelledError:
        logger.debug(f"{name}: Relay task cancelled (transferred {bytes_transferred} bytes)")
        raise
    except Exception as e:
        logger.debug(f"{name}: Unexpected error after {bytes_transferred} bytes: {e}")
    logger.debug(f"{name}: Relay finished - {bytes_transferred} bytes transferred")


async def handle_dns_relay(client_reader: asyncio.StreamReader, client_writer: asyncio.StreamWriter,
                           server_reader: asyncio.StreamReader, server_writer: asyncio.StreamWriter,
                           host: str, port: int) -> None:
    """Handle DNS queries with aggressive timeouts and cleanup."""
    try:
        # Read client query
        query_data = await asyncio.wait_for(client_reader.read(512), timeout=2.0)
        if not query_data:
            return
        server_writer.write(query_data)
        await safe_drain(server_writer)
        # Read server response
        response_data = await asyncio.wait_for(server_reader.read(512), timeout=2.0)
        if not response_data:
            return
        client_writer.write(response_data)
        await safe_drain(client_writer)
    except asyncio.TimeoutError:
        logger.debug(f"DNS: Timeout during query/response to {host}:{port}")
    except Exception as e:
        logger.debug(f"DNS: Error during query to {host}:{port}: {e}")
    finally:
        await safe_close_writer(server_writer, "dns_server")
        await safe_close_writer(client_writer, "dns_client")
        logger.info(f"SOCKS5 DNS query to {host}:{port} closed")


async def relay_with_timeout(reader: asyncio.StreamReader, writer: asyncio.StreamWriter,
                             name: str = "relay") -> None:
    """Relay data between reader and writer with timeout (for HTTP responses)."""
    try:
        while not writer.is_closing():
            try:
                chunk = await asyncio.wait_for(reader.read(RELAY_CHUNK_SIZE), timeout=READ_TIMEOUT)
                if not chunk:
                    logger.debug(f"{name}: EOF reached")
                    break
                writer.write(chunk)
                if not await safe_drain(writer):
                    logger.debug(f"{name}: Drain failed, stopping relay")
                    break
            except asyncio.TimeoutError:
                logger.debug(f"{name}: Read timeout")
                break
            except (ConnectionError, OSError) as e:
                logger.debug(f"{name}: Connection error: {e}")
                break
    except Exception as e:
        logger.debug(f"{name}: Unexpected error: {e}")
    finally:
        await safe_close_writer(writer, f"{name}_writer")


async def respond_http(writer: asyncio.StreamWriter, code: int, reason: str,
                       headers: Optional[Dict[str, str]] = None, body: bytes = b"",
                       auto_close: bool = True) -> bool:
    """Send HTTP response with proper error handling."""
    if writer.is_closing():
        return False
    try:
        status = f"HTTP/1.1 {code} {reason}".encode() + CRLF
        writer.write(status)
        if headers is None:
            headers = {}
        if body and "content-length" not in {k.lower() for k in headers.keys()}:
            headers["Content-Length"] = str(len(body))
        if auto_close and "connection" not in {k.lower() for k in headers.keys()}:
            headers["Connection"] = "close"
        for k, v in headers.items():
            clean_value = sanitize_header_value(str(v))
            writer.write(f"{k}: {clean_value}".encode() + CRLF)
        writer.write(CRLF)
        if body:
            writer.write(body)
        return await safe_drain(writer)
    except Exception as e:
        logger.debug(f"Error sending response: {e}")
        return False


def parse_host_port(host_port: str) -> Tuple[str, int]:
    """Parse host:port string with proper IPv6 support."""
    ipv6_with_port_pattern = r'^\[([0-9a-fA-F:]+)\]:(\d+)$'
    ipv6_with_port_match = re.match(ipv6_with_port_pattern, host_port)
    if ipv6_with_port_match:
        return ipv6_with_port_match.group(1), int(ipv6_with_port_match.group(2))
    ipv6_no_port_pattern = r'^\[([0-9a-fA-F:]+)\]$'
    ipv6_no_port_match = re.match(ipv6_no_port_pattern, host_port)
    if ipv6_no_port_match:
        return ipv6_no_port_match.group(1), 80
    if ':' in host_port and host_port.count(':') > 1 and '[' not in host_port:
        return host_port, 80
    if ':' in host_port and not host_port.count(':') > 1:
        host, port_str = host_port.rsplit(':', 1)
        port = int(port_str)
        if not (1 <= port <= 65535):
            raise ValueError("Port out of range")
        return host, port
    return host_port, 80


class PrependedStreamReader:
    """StreamReader wrapper that prepends data to the beginning of a stream."""
    def __init__(self, prepend_data: bytes, original_reader: asyncio.StreamReader):
        self.prepend_data = prepend_data
        self.original_reader = original_reader
        self.prepend_consumed = False

    async def read(self, n: int = -1) -> bytes:
        if not self.prepend_consumed:
            if n == -1 or n >= len(self.prepend_data):
                self.prepend_consumed = True
                remaining = n - len(self.prepend_data) if n != -1 else -1
                additional = await self.original_reader.read(remaining) if remaining != 0 else b""
                return self.prepend_data + additional
            else:
                result = self.prepend_data[:n]
                self.prepend_data = self.prepend_data[n:]
                if not self.prepend_data:
                    self.prepend_consumed = True
                return result
        else:
            return await self.original_reader.read(n)

    async def readexactly(self, n: int) -> bytes:
        if not self.prepend_consumed:
            if n <= len(self.prepend_data):
                result = self.prepend_data[:n]
                self.prepend_data = self.prepend_data[n:]
                if not self.prepend_data:
                    self.prepend_consumed = True
                return result
            else:
                self.prepend_consumed = True
                remaining = n - len(self.prepend_data)
                additional = await self.original_reader.readexactly(remaining)
                return self.prepend_data + additional
        else:
            return await self.original_reader.readexactly(n)

    async def readline(self) -> bytes:
        if not self.prepend_consumed:
            self.prepend_consumed = True
            line_part = await self.original_reader.readline()
            return self.prepend_data + line_part
        else:
            return await self.original_reader.readline()


async def read_headers(reader: asyncio.StreamReader) -> Dict[str, str]:
    """Read HTTP headers with proper bounds checking."""
    headers = CaseInsensitiveDict()
    raw_headers = b""
    while True:
        line = await asyncio.wait_for(reader.readline(), timeout=READ_TIMEOUT)
        raw_headers += line
        if len(raw_headers) > MAX_HEADER_BYTES:
            raise ValueError("Headers too large")
        if line in (b"\r\n", b"\n", b""):
            break
    for hline in raw_headers.splitlines():
        hline = hline.strip()
        if not hline or b":" not in hline:
            continue
        try:
            name, val = hline.split(b":", 1)
            headers[name.decode("iso-8859-1").strip()] = val.decode("iso-8859-1").strip()
        except (UnicodeDecodeError, ValueError):
            continue
    return headers


async def read_chunked_body(reader: asyncio.StreamReader) -> bytes:
    """Read chunked request body."""
    body = b""
    total_size = 0
    while True:
        size_line = await asyncio.wait_for(reader.readline(), timeout=READ_TIMEOUT)
        if not size_line:
            raise ValueError("Incomplete chunked body")
        try:
            chunk_size = int(size_line.strip().split(b';')[0], 16)
        except ValueError:
            raise ValueError("Invalid chunk size")
        if chunk_size == 0:
            while True:
                line = await asyncio.wait_for(reader.readline(), timeout=READ_TIMEOUT)
                if line in (b"\r\n", b"\n", b""):
                    break
            break
        chunk_data = await asyncio.wait_for(reader.readexactly(chunk_size), timeout=READ_TIMEOUT)
        total_size += len(chunk_data)
        if total_size > MAX_BODY_SIZE:
            raise ValueError("Body too large")
        body += chunk_data
        trailing = await asyncio.wait_for(reader.readexactly(2), timeout=READ_TIMEOUT)
        if trailing not in (b'\r\n', b'\n\r'):
            if not trailing.startswith(b'\n'):
                raise ValueError("Invalid chunk trailing bytes")
    return body


async def read_request_body(reader: asyncio.StreamReader, headers: Dict[str, str]) -> Optional[bytes]:
    """Read request body handling both Content-Length and chunked encoding."""
    if "transfer-encoding" in headers:
        te = headers["transfer-encoding"].lower()
        if "chunked" in te:
            return await read_chunked_body(reader)
        else:
            raise ValueError(f"Unsupported transfer encoding: {te}")
    if "content-length" in headers:
        content_length = int(headers["content-length"])
        if content_length < 0:
            raise ValueError("Negative content length")
        if content_length > MAX_BODY_SIZE:
            raise ValueError("Body too large")
        if content_length == 0:
            return b""
        timeout = min(READ_TIMEOUT * (1 + content_length // (64 * 1024)), MAX_BODY_READ_TIMEOUT)
        body = await asyncio.wait_for(reader.readexactly(content_length), timeout=timeout)
        return body
    return None


async def handle_socks5_auth(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> bool:
    """Handle SOCKS5 authentication negotiation."""
    try:
        auth_data = await asyncio.wait_for(reader.read(2), timeout=READ_TIMEOUT)
        if len(auth_data) != 2:
            return False
        version, nmethods = auth_data
        if version != SOCKS5_VERSION:
            return False
        methods = await asyncio.wait_for(reader.read(nmethods), timeout=READ_TIMEOUT) if nmethods > 0 else b""
        if SOCKS5_NO_AUTH in methods or nmethods == 0:
            writer.write(bytes([SOCKS5_VERSION, SOCKS5_NO_AUTH]))
            if not await safe_drain(writer):
                return False
            return True
        writer.write(bytes([SOCKS5_VERSION, SOCKS5_NO_ACCEPTABLE_METHODS]))
        await safe_drain(writer)
        return False
    except Exception:
        return False


async def parse_socks5_address(reader: asyncio.StreamReader) -> Tuple[str, int]:
    """Parse SOCKS5 address from connection request."""
    atyp_data = await asyncio.wait_for(reader.read(1), timeout=READ_TIMEOUT)
    if not atyp_data:
        raise ValueError("Missing address type")
    atyp = atyp_data[0]
    if atyp == SOCKS5_IPv4:
        addr_data = await asyncio.wait_for(reader.read(4), timeout=READ_TIMEOUT)
        if len(addr_data) != 4:
            raise ValueError("Invalid IPv4 address")
        host = ".".join(str(b) for b in addr_data)
    elif atyp == SOCKS5_DOMAIN:
        len_data = await asyncio.wait_for(reader.read(1), timeout=READ_TIMEOUT)
        if not len_data:
            raise ValueError("Missing domain length")
        domain_len = len_data[0]
        if domain_len == 0:
            raise ValueError("Empty domain name")
        domain_data = await asyncio.wait_for(reader.read(domain_len), timeout=READ_TIMEOUT)
        if len(domain_data) != domain_len:
            raise ValueError("Invalid domain name")
        host = domain_data.decode('ascii')
    elif atyp == SOCKS5_IPv6:
        addr_data = await asyncio.wait_for(reader.read(16), timeout=READ_TIMEOUT)
        if len(addr_data) != 16:
            raise ValueError("Invalid IPv6 address")
        parts = []
        for i in range(0, 16, 2):
            part = (addr_data[i] << 8) | addr_data[i + 1]
            parts.append(f"{part:x}")
        host = ":".join(parts)
    else:
        raise ValueError(f"Unsupported address type: {atyp}")
    port_data = await asyncio.wait_for(reader.read(2), timeout=READ_TIMEOUT)
    if len(port_data) != 2:
        raise ValueError("Invalid port")
    port = (port_data[0] << 8) | port_data[1]
    return host, port


async def send_socks5_response(writer: asyncio.StreamWriter, reply_code: int,
                               bind_addr: str = "0.0.0.0", bind_port: int = 0) -> bool:
    """Send SOCKS5 connection response."""
    try:
        response = bytearray([SOCKS5_VERSION, reply_code, 0x00, SOCKS5_IPv4])
        for part in bind_addr.split('.'):
            response.append(int(part))
        response.extend([(bind_port >> 8) & 0xFF, bind_port & 0xFF])
        writer.write(response)
        return await safe_drain(writer)
    except Exception as e:
        logger.debug(f"Error sending SOCKS5 response: {e}")
        return False


async def handle_socks5(client_reader: asyncio.StreamReader, client_writer: asyncio.StreamWriter) -> None:
    """Handle SOCKS5 proxy connection."""
    logger.info("SOCKS5 connection detected")

    if not await handle_socks5_auth(client_reader, client_writer):
        await safe_close_writer(client_writer, "socks5_client")
        return

    try:
        req_header = await asyncio.wait_for(client_reader.read(3), timeout=READ_TIMEOUT)
        if len(req_header) != 3:
            await send_socks5_response(client_writer, SOCKS5_GENERAL_FAILURE)
        version, cmd, _ = req_header
        if version != SOCKS5_VERSION:
            await send_socks5_response(client_writer, SOCKS5_GENERAL_FAILURE)
            return
        if cmd != SOCKS5_CONNECT:
            await send_socks5_response(client_writer, SOCKS5_COMMAND_NOT_SUPPORTED)
            return

        host, port = await parse_socks5_address(client_reader)
        logger.info(f"SOCKS5 CONNECT to {host}:{port}")

        try:
            server_reader, server_writer = await asyncio.wait_for(
                asyncio.open_connection(host, port), timeout=CONNECT_TIMEOUT
            )
        except Exception as e:
            if "refused" in str(e).lower():
                reply_code = SOCKS5_CONNECTION_REFUSED
            elif "unreachable" in str(e).lower():
                reply_code = SOCKS5_HOST_UNREACHABLE
            else:
                reply_code = SOCKS5_GENERAL_FAILURE
            await send_socks5_response(client_writer, reply_code)
            await safe_close_writer(client_writer, "socks5_client")
            return

        if not await send_socks5_response(client_writer, SOCKS5_SUCCESS):
            await safe_close_writer(server_writer, "socks5_server")
            await safe_close_writer(client_writer, "socks5_client")
            return

        # Optional: very fast DNS handling
        if port == 53:
            await handle_dns_relay(client_reader, client_writer, server_reader, server_writer, host, port)
            return

        logger.info(f"SOCKS5 tunnel established to {host}:{port}")

        # Relay both directions until BOTH complete
        client_to_server = asyncio.create_task(
            relay_data_stream(client_reader, server_writer, f"socks5_c2s_{host}:{port}")
        )
        server_to_client = asyncio.create_task(
            relay_data_stream(server_reader, client_writer, f"socks5_s2c_{host}:{port}")
        )

        try:
            await asyncio.gather(client_to_server, server_to_client)
        finally:
            await safe_close_writer(server_writer, "socks5_server")
            await safe_close_writer(client_writer, "socks5_client")
            logger.info(f"SOCKS5 tunnel to {host}:{port} closed")

    except asyncio.TimeoutError:
        await send_socks5_response(client_writer, SOCKS5_GENERAL_FAILURE)
        await safe_close_writer(client_writer, "socks5_client")
    except Exception as e:
        logger.error(f"SOCKS5 error: {e}")
        await send_socks5_response(client_writer, SOCKS5_GENERAL_FAILURE)
        await safe_close_writer(client_writer, "socks5_client")


async def handle_connect(client_reader: asyncio.StreamReader, client_writer: asyncio.StreamWriter,
                         target: str) -> None:
    """Handle CONNECT method for HTTPS tunneling."""
    try:
        host, port = parse_host_port(target)
    except ValueError as e:
        await respond_http(client_writer, 400, "Bad Request", body=f"Invalid target: {e}".encode())
        return

    try:
        server_reader, server_writer = await asyncio.wait_for(
            asyncio.open_connection(host, port), timeout=CONNECT_TIMEOUT
        )
    except Exception as e:
        await respond_http(client_writer, 502, "Bad Gateway",
                           body=f"Failed to connect to {host}:{port}: {e}".encode())
        return

    success = await respond_http(
        client_writer, 200, "Connection Established",
        headers={"Proxy-Agent": "FixedPyProxy/1.0"},
        auto_close=False
    )
    if not success:
        await safe_close_writer(server_writer, "server")
        return

    logger.info(f"HTTP CONNECT tunnel established to {host}:{port}")

    client_to_server = asyncio.create_task(
        relay_data_stream(client_reader, server_writer, f"http_c2s_{host}:{port}")
    )
    server_to_client = asyncio.create_task(
        relay_data_stream(server_reader, client_writer, f"http_s2c_{host}:{port}")
    )

    try:
        # Keep the tunnel up until BOTH relays complete
        await asyncio.gather(client_to_server, server_to_client)
    except Exception as e:
        logger.error(f"Error in HTTP CONNECT relay for {host}:{port}: {e}")
    finally:
        await safe_close_writer(server_writer, "server")
        await safe_close_writer(client_writer, "client")
        logger.info(f"HTTP CONNECT tunnel to {host}:{port} closed")


async def handle_http_request(client_reader: asyncio.StreamReader, client_writer: asyncio.StreamWriter,
                              method: str, target: str, version: str, headers: Dict[str, str]) -> None:
    """Handle regular HTTP requests (both absolute-form and origin-form)."""
    parts = urlsplit(target)
    if not parts.scheme:
        if "host" not in headers:
            await respond_http(client_writer, 400, "Bad Request",
                               body=b"Host header required for origin-form requests")
            return
        host_header = headers["host"]
        target = f"http://{host_header}{target}"
        parts = urlsplit(target)

    if parts.scheme.lower() != "http":
        await respond_http(client_writer, 400, "Bad Request",
                           body=b"Only http:// URLs supported (use CONNECT for https)")
        return
    if not parts.netloc:
        await respond_http(client_writer, 400, "Bad Request", body=b"Missing host in URL")
        return

    try:
        host, port = parse_host_port(parts.netloc)
    except ValueError as e:
        await respond_http(client_writer, 400, "Bad Request",
                           body=f"Invalid host:port in URL: {e}".encode())
        return

    path = parts.path or "/"
    if parts.query:
        path += "?" + parts.query

    try:
        body = await read_request_body(client_reader, headers)
    except ValueError as e:
        await respond_http(client_writer, 400, "Bad Request", body=f"Body error: {e}".encode())
        return
    except asyncio.TimeoutError:
        await respond_http(client_writer, 408, "Request Timeout", body=b"Body read timeout")
        return

    origin_headers = CaseInsensitiveDict(headers)

    te_header_keep = False
    if "te" in origin_headers:
        te_value = origin_headers["te"].lower().strip()
        if te_value == "trailers":
            te_header_keep = True

    hop_by_hop = {"proxy-connection", "connection", "keep-alive", "Trailer",
                  "transfer-encoding", "upgrade", "proxy-authenticate", "proxy-authorization"}
    for h in hop_by_hop:
        origin_headers.pop(h, None)
    if not te_header_keep:
        origin_headers.pop("te", None)

    origin_headers["Host"] = parts.netloc
    origin_headers["Connection"] = "close"

    if body is not None:
        origin_headers["Content-Length"] = str(len(body))
        origin_headers.pop("transfer-encoding", None)

    try:
        origin_reader, origin_writer = await asyncio.wait_for(
            asyncio.open_connection(host, port), timeout=CONNECT_TIMEOUT
        )
    except Exception as e:
        await respond_http(client_writer, 502, "Bad Gateway",
                           body=f"Failed to connect to {host}:{port}: {e}".encode())
        return

    logger.info(f"HTTP {method} {target} -> {host}:{port}{path} (Content-Length: {len(body) if body else 0})")

    try:
        origin_writer.write(f"{method} {path} {version}\r\n".encode("iso-8859-1"))
        for k, v in origin_headers.items_ci():
            origin_writer.write(f"{k}: {v}\r\n".encode("iso-8859-1"))
        origin_writer.write(CRLF)
        if body:
            origin_writer.write(body)

        if not await safe_drain(origin_writer):
            await respond_http(client_writer, 502, "Bad Gateway", body=b"Failed to send request")
            return

        try:
            while not client_writer.is_closing():
                data = await asyncio.wait_for(origin_reader.read(RELAY_CHUNK_SIZE), timeout=READ_TIMEOUT)
                if not data:
                    break
                client_writer.write(data)
                if not await safe_drain(client_writer):
                    break
        except asyncio.TimeoutError:
            logger.debug("Origin server response timeout")
        except (ConnectionError, OSError) as e:
            logger.debug(f"Connection error during response: {e}")

    except Exception as e:
        logger.error(f"Error handling HTTP request: {e}")
    finally:
        await safe_close_writer(origin_writer, "origin")
        await safe_close_writer(client_writer, "client")


async def handle_client(client_reader: asyncio.StreamReader, client_writer: asyncio.StreamWriter):
    """Handle incoming client connection (HTTP or SOCKS5)."""
    global active_connections, connection_counter

    connection_counter += 1
    active_connections += 1
    conn_id = connection_counter

    peer = client_writer.get_extra_info("peername")
    logger.info(f"New connection #{conn_id} from {peer} (active: {active_connections})")

    try:
        first_byte = await asyncio.wait_for(client_reader.read(1), timeout=READ_TIMEOUT)
        if not first_byte:
            await safe_close_writer(client_writer, "client")
            return

        if first_byte[0] == SOCKS5_VERSION:
            new_reader = PrependedStreamReader(first_byte, client_reader)
            try:
                await handle_socks5(new_reader, client_writer)
            except Exception as e:
                logger.error(f"Connection #{conn_id}: SOCKS5 handler error: {e}")
                await safe_close_writer(client_writer, "socks5_client_error")
            return

        rest_of_line = await asyncio.wait_for(client_reader.readline(), timeout=READ_TIMEOUT)
        req_line = first_byte + rest_of_line

        if len(req_line) > MAX_REQ_LINE:
            await respond_http(client_writer, 414, "Request-URI Too Long", body=b"URI too long")
            await safe_close_writer(client_writer, "client")
            return

        try:
            req_parts = req_line.decode("iso-8859-1").strip().split(None, 2)
            if len(req_parts) < 2:
                raise ValueError("Incomplete request line")
            elif len(req_parts) == 2:
                method, target = req_parts
                version = "HTTP/1.0"
            else:
                method, target, version = req_parts
        except (ValueError, UnicodeDecodeError):
            await respond_http(client_writer, 400, "Bad Request", body=b"Malformed request line")
            await safe_close_writer(client_writer, "client")
            return

        try:
            headers = await read_headers(client_reader)
        except ValueError as e:
            await respond_http(client_writer, 431 if "too large" in str(e).lower() else 400,
                               "Bad Request", body=f"Header error: {e}".encode())
            await safe_close_writer(client_writer, "client")
            return
        except asyncio.TimeoutError:
            await respond_http(client_writer, 408, "Request Timeout", body=b"Header read timeout")
            await safe_close_writer(client_writer, "client")
            return

        if method.upper() == "CONNECT":
            await handle_connect(client_reader, client_writer, target)
        else:
            await handle_http_request(client_reader, client_writer, method, target, version, headers)

    except asyncio.TimeoutError:
        await respond_http(client_writer, 408, "Request Timeout", body=b"Request timeout")
        await safe_close_writer(client_writer, "client")
    except asyncio.CancelledError:
        await safe_close_writer(client_writer, "client")
        raise
    except Exception as e:
        logger.error(f"Connection #{conn_id}: Unexpected error handling client {peer}: {e}")
        try:
            await respond_http(client_writer, 500, "Internal Server Error",
                               body=f"Server error: {e}".encode())
        except Exception:
            pass
        await safe_close_writer(client_writer, "client")
    finally:
        active_connections -= 1


async def periodic_status_logger():
    """Log server status periodically for debugging."""
    while True:
        await asyncio.sleep(30)
        if active_connections > 0:
            logger.info(f"Status: {active_connections} active connections, {connection_counter} total handled")


async def main():
    """Main server function."""
    host = HOST
    port = PORT

    if len(sys.argv) >= 2:
        try:
            port = int(sys.argv[1])
            if not (1 <= port <= 65535):
                raise ValueError("Port must be between 1 and 65535")
        except ValueError as e:
            print(f"Usage: python proxy.py [port] - {e}", file=sys.stderr)
            sys.exit(1)

    try:
        server = await asyncio.start_server(handle_client, host=host, port=port)
        addr = ", ".join(str(sock.getsockname()) for sock in server.sockets)
        logger.info(f"HTTP/SOCKS5 proxy server started on {addr}")
        logger.info("Supports: HTTP CONNECT, HTTP requests, SOCKS5")
        logger.info("Press Ctrl+C to stop")

        status_task = asyncio.create_task(periodic_status_logger())

        async with server:
            try:
                await server.serve_forever()
            finally:
                status_task.cancel()
                try:
                    await status_task
                except asyncio.CancelledError:
                    pass

    except OSError as e:
        logger.error(f"Failed to start server: {e}")
        sys.exit(1)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Server stopped by user")
        print("\nUsage examples:")
        print("HTTP proxy:  curl -x http://127.0.0.1:8080 http://httpbin.org/ip")
        print("HTTPS via CONNECT: curl -x http://127.0.0.1:8080 https://httpbin.org/ip")
        print("SOCKS5 proxy: curl --socks5 127.0.0.1:8080 http://httpbin.org/ip")
    except Exception as e:
        logger.error(f"Server error: {e}")
        sys.exit(1)
