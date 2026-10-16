import os
import select
import socket
import time
import threading
import urllib.request
import urllib.error
import json as _json
from seleniumbase import SB

# ── Constants ────────────────────────────────────────────────────────────────

PASTE_THRESHOLD = 200   # chars; above this use JS injection instead of keyboard

SEND_SELECTORS = [
    "#composer-submit-button",
    "[data-testid='send-button']",
    "button[aria-label='Send prompt']",
    "button[aria-label='Send message']",
]

MODAL_TEXTS = [
    "stay logged out", "no thanks", "skip", "continue as guest",
    "continue without account", "maybe later", "not now", "dismiss",
]

GUEST_SELECTORS = [
    "button[data-testid='stay-logged-out-button']",
    "//button[contains(text(),'Stay logged out')]",
    "//button[contains(text(),'Continue without account')]",
    "//button[contains(text(),'Continue as guest')]",
]

# ── Textarea selectors — ordered from most to least specific ─────────────────
# ChatGPT has changed this element's id/attributes multiple times.
# We try all known variants; _find_textarea() returns the first live match.

TEXTAREA_SELECTORS = [
    # ── "Ask anything" placeholder — most reliable signal across UI versions ──
    "[placeholder='Ask anything']",
    "textarea[placeholder='Ask anything']",
    "div[contenteditable='true'][placeholder='Ask anything']",
    "p[placeholder='Ask anything']",          # ChatGPT sometimes uses a <p> inside a div
    # XPath: any element whose placeholder attribute contains "Ask anything"
    "//*[@placeholder='Ask anything']",
    "//*[contains(@placeholder,'Ask anything')]",
    # ── Known stable id/attributes ────────────────────────────────────────────
    "#prompt-textarea",
    "textarea#prompt-textarea",
    "[data-id='prompt-textarea']",
    "div[contenteditable='true'][data-virtualkeyboard-exclusion]",
    # ── Broader fallbacks — scoped to avoid false matches ─────────────────────
    "form div[contenteditable='true']",
    "main div[contenteditable='true']",
    "[role='main'] div[contenteditable='true']",
    "textarea[placeholder]",
]

# ── Helpers ──────────────────────────────────────────────────────────────────

def sleep(ms: int):
    time.sleep(ms / 1000)


def _js(sb, script: str, *args):
    """
    Execute JS in an IIFE with a clean variable scope.

    CDP's Runtime.evaluate runs code as a top-level *program*, not inside a
    function, so the `arguments` object is never populated even when
    execute_script is called with extra parameters.

    Fix: JSON-serialize each Python arg and inject it as a __a0, __a1, …
    variable *before* the script body, then rewrite any `arguments[N]`
    references in the script to use those variables instead.
    """
    import json

    preamble = ""
    patched  = script
    for i, arg in enumerate(args):
        var_name  = f"__a{i}"
        preamble += f"var {var_name} = {json.dumps(arg)};\n"
        patched   = patched.replace(f"arguments[{i}]", var_name)

    full = f"(function(){{\n{preamble}{patched}\n}})();"
    return sb.execute_script(full)


# ── Textarea finder ───────────────────────────────────────────────────────────

def _find_textarea(sb, timeout: float = 15.0):
    """
    Try every selector in TEXTAREA_SELECTORS and return the first element
    that is:
      • present in the DOM
      • visible (non-zero dimensions, not hidden)
      • not disabled / read-only

    Also waits up to *timeout* seconds total before giving up.
    Returns the WebDriver element or raises RuntimeError.
    """
    import logging
    log = logging.getLogger(__name__)

    deadline = time.time() + timeout

    while time.time() < deadline:
        for sel in TEXTAREA_SELECTORS:
            try:
                by = "xpath" if sel.startswith("//") else "css selector"
                el = sb.find_element(by, sel, timeout=1)
                if not el:
                    continue

                # Confirm the element is actually interactable via JS
                ok = _js(sb, """
                    var el = arguments[0];
                    if (!el) return false;
                    var r = el.getBoundingClientRect();
                    if (r.width === 0 || r.height === 0) return false;
                    if (el.disabled || el.readOnly) return false;
                    var style = window.getComputedStyle(el);
                    if (style.display === 'none' || style.visibility === 'hidden') return false;
                    return true;
                """, el)  # NOTE: passing a WebElement here; see _js_el below

                if ok:
                    log.debug("Textarea found with selector: %s", sel)
                    return el, sel
            except Exception:
                pass

        sleep(500)

    raise RuntimeError(
        "Could not find the ChatGPT prompt textarea after "
        f"{timeout:.0f}s. Tried selectors: {TEXTAREA_SELECTORS}"
    )


def _js_el(sb, element, script: str, *args):
    """
    Like _js() but passes a DOM element as the first implicit argument so
    JS can receive it as __el.  Used by _find_textarea's interactability check.
    """
    import json
    preamble = f"var __el = arguments[0];\n"
    patched  = script.replace("arguments[0]", "__el")
    for i, arg in enumerate(args):
        var_name  = f"__a{i}"
        preamble += f"var {var_name} = {json.dumps(arg)};\n"
        patched   = patched.replace(f"arguments[{i+1}]", var_name)

    full = f"(function(){{\n{preamble}{patched}\n}})();"
    return sb.execute_script(full, element)


def _wait_for_textarea(sb, timeout: float = 20.0):
    """
    High-level wrapper: wait until ANY known textarea selector is visible.
    Falls back to a JS scan of all contenteditable/textarea elements.
    Returns (element, selector_used).
    """
    import logging
    log = logging.getLogger(__name__)

    # Fast path — try each selector with wait_for_element_visible
    deadline = time.time() + timeout
    while time.time() < deadline:
        for sel in TEXTAREA_SELECTORS:
            try:
                sb.wait_for_element_visible(sel, timeout=2)
                el = sb.find_element("css selector" if not sel.startswith("//") else "xpath", sel, timeout=1)
                log.info("Textarea ready via: %s", sel)
                return el, sel
            except Exception:
                pass
        sleep(500)

    # JS scan fallback — find ANY editable element inside the composer
    log.warning("Primary selectors timed out — running JS scan for textarea")
    el_found = _js(sb, """
        // 1. Fastest path: find by the known placeholder text "Ask anything"
        var el = document.querySelector('[placeholder="Ask anything"]');

        // 2. Fallback: any visible contenteditable / textarea
        if (!el) {
            var candidates = Array.from(document.querySelectorAll(
                'div[contenteditable="true"], textarea, p[contenteditable="true"]'
            ));
            el = candidates.find(function(e) {
                var r = e.getBoundingClientRect();
                if (r.width === 0 || r.height === 0) return false;
                var style = window.getComputedStyle(e);
                if (style.display === 'none' || style.visibility === 'hidden') return false;
                // Check placeholder attribute contains "Ask anything" (case-insensitive)
                var ph = (e.getAttribute('placeholder') || '').toLowerCase();
                if (ph.indexOf('ask') !== -1) return true;
                // Prefer elements inside a form or near the bottom of the viewport
                var inForm = !!e.closest('form');
                var nearBottom = r.top > window.innerHeight * 0.4;
                return inForm || nearBottom;
            });
        }
        if (el) {
            // Give it a stable id so Python can retrieve it
            el.setAttribute('data-sb-found', 'true');
            return true;
        }
        return false;
    """)

    if el_found:
        try:
            el = sb.find_element("css selector", "[data-sb-found='true']", timeout=3)
            log.info("Textarea found via JS scan fallback")
            return el, "[data-sb-found='true']"
        except Exception:
            pass

    raise RuntimeError(
        "ChatGPT prompt textarea not found after exhausting all selectors and JS scan. "
        "The page may not have loaded correctly or ChatGPT's UI has changed again."
    )


# ── Proxy IP check ───────────────────────────────────────────────────────────

def _redact_ip(ip: str) -> str:
    """Return only the first octet/group: '104.x.x.x' or '2a02:x:x:x'."""
    if not ip:
        return "?.x.x.x"
    if "." in ip:
        return ip.split(".")[0] + ".x.x.x"
    return ip.split(":")[0] + ":x:x:x"


def _fetch_ip_direct(timeout: int) -> str:
    """GET api.ipify.org with NO proxy — returns the raw origin IP."""
    no_proxy = urllib.request.ProxyHandler({})
    opener   = urllib.request.build_opener(no_proxy)
    req      = urllib.request.Request(
        "https://api.ipify.org?format=json",
        headers={"User-Agent": "chatgpt-bot/1.0"},
    )
    with opener.open(req, timeout=timeout) as resp:
        return _json.loads(resp.read().decode()).get("ip", "")


def _fetch_ip_via_proxy(proxy_url: str, timeout: int) -> str:
    """GET api.ipify.org routed through *proxy_url* — returns the egress IP."""
    proxy_handler = urllib.request.ProxyHandler({
        "http":  proxy_url,
        "https": proxy_url,
    })
    opener = urllib.request.build_opener(proxy_handler)
    req    = urllib.request.Request(
        "https://api.ipify.org?format=json",
        headers={"User-Agent": "chatgpt-bot/1.0"},
    )
    with opener.open(req, timeout=timeout) as resp:
        return _json.loads(resp.read().decode()).get("ip", "")


def _fetch_ip_via_browser(sb, timeout: int) -> str:
    script = """
        var done = arguments[0];
        fetch('https://api.ipify.org?format=json')
            .then(function(r){ return r.json(); })
            .then(function(d){ done(d.ip || ''); })
            .catch(function(e){ done(''); });
    """
    try:
        sb.driver.set_script_timeout(timeout)
        return sb.execute_async_script(script) or ""
    except Exception:
        return ""


def _lookup_isp(ip: str, timeout: int) -> str:
    try:
        req = urllib.request.Request(
            f"http://ip-api.com/json/{ip}?fields=status,isp,org",
            headers={"User-Agent": "chatgpt-bot/1.0"},
        )
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            info = _json.loads(resp.read().decode())
        if info.get("status") == "success":
            return info.get("isp") or info.get("org") or "unknown ISP"
    except Exception:
        pass
    return "unknown ISP"


def check_proxy_leak(
    proxy_url: str | None,
    proxy_host: str | None,
    sb=None,
    timeout: int = 12,
) -> bool:
    import logging
    log = logging.getLogger(__name__)

    host_hint = (proxy_host[0] + "…") if proxy_host else "(direct)"

    origin_ip = ""
    try:
        origin_ip = _fetch_ip_direct(timeout)
    except Exception as exc:
        log.warning("IP-check: could not fetch origin IP — %s", exc)

    origin_hint = _redact_ip(origin_ip)

    python_ip = ""
    if proxy_url:
        try:
            python_ip = _fetch_ip_via_proxy(proxy_url, timeout)
        except Exception as exc:
            log.warning("IP-check [python-layer]: request through proxy failed — %s", exc)
    else:
        python_ip = origin_ip

    python_hint = _redact_ip(python_ip)

    browser_ip = ""
    if sb is not None:
        browser_ip = _fetch_ip_via_browser(sb, timeout)
        if not browser_ip:
            log.warning("IP-check [browser-layer]: fetch() returned empty — browser may lack network")
    browser_hint = _redact_ip(browser_ip) if browser_ip else "n/a (browser not ready)"

    lookup_ip = python_ip or origin_ip
    isp = _lookup_isp(lookup_ip, timeout) if lookup_ip else "unknown ISP"

    ok = True

    if proxy_url and python_ip and origin_ip and python_ip == origin_ip:
        log.error(
            "⚠ LEAK — Python layer: proxy egress (%s) == origin (%s). "
            "Traffic is NOT going through the proxy!",
            python_hint, origin_hint,
        )
        ok = False

    if proxy_url and browser_ip and origin_ip and browser_ip == origin_ip:
        log.error(
            "⚠ LEAK — Browser layer: browser egress (%s) == origin (%s). "
            "Chrome is bypassing the proxy!",
            browser_hint, origin_hint,
        )
        ok = False

    if browser_ip and python_ip and browser_ip != python_ip:
        log.warning(
            "⚠ MISMATCH — Python egress (%s) ≠ browser egress (%s). "
            "Browser may be using a different route.",
            python_hint, browser_hint,
        )
        ok = False

    status = "✓ OK" if ok else "✗ LEAK DETECTED"
    log.info(
        "IP-check %s  host=%s  origin=%s  proxy-layer=%s  browser-layer=%s  ISP=%s",
        status, host_hint, origin_hint, python_hint, browser_hint, isp,
    )

    return ok


# ── Guest session ────────────────────────────────────────────────────────────

def _dismiss_login_wall(sb) -> bool:
    for sel in GUEST_SELECTORS:
        try:
            if sel.startswith("//"):
                el = sb.find_element("xpath", sel, timeout=2)
            else:
                el = sb.find_element("css selector", sel, timeout=2)
            el.click()
            sleep(800)
            return True
        except Exception:
            pass

    clicked = _js(sb, """
        var keywords = ["stay logged out","continue without","continue as guest","no thanks","skip"];
        var btn = Array.from(document.querySelectorAll("button, a")).find(function(b) {
            var t = (b.innerText || b.textContent || "").trim().toLowerCase();
            return keywords.some(function(k){ return t.indexOf(k) !== -1; });
        });
        if (btn) { btn.click(); return true; }
        return false;
    """)
    if clicked:
        sleep(800)
    return bool(clicked)


def _bypass_ssl_interstitial(sb) -> bool:
    import logging
    log = logging.getLogger(__name__)

    ssl_bypassed = _js(sb, """
        var proceed = document.querySelector('#proceed-link');
        if (proceed) { proceed.click(); return 'proceed'; }
        var adv = document.querySelector('#details-button');
        if (adv) { adv.click(); return 'advanced'; }
        return null;
    """)

    if ssl_bypassed == 'advanced':
        sleep(500)
        _js(sb, """
            var proceed = document.querySelector('#proceed-link');
            if (proceed) proceed.click();
        """)
        sleep(500)
        return True
    elif ssl_bypassed == 'proceed':
        sleep(500)
        return True

    try:
        page_src = sb.get_page_source()
        if any(x in page_src for x in ['ERR_CERT', 'NET::ERR']) or \
                'your connection is not private' in page_src.lower():
            log.warning("SSL error page detected — using keyboard bypass")
            from selenium.webdriver.common.action_chains import ActionChains
            ActionChains(sb.driver).send_keys('thisisunsafe').perform()
            sleep(800)
            return True
    except Exception:
        pass

    return False


def establish_guest_session(sb, max_attempts: int = 5):
    """
    Navigate to chatgpt.com, escape any auth redirect, and dismiss login prompts.
    Uses _wait_for_textarea() which tries all known selectors + a JS scan fallback,
    so it stays resilient when ChatGPT changes the composer DOM.
    """
    import logging
    log = logging.getLogger(__name__)

    for attempt in range(1, max_attempts + 1):
        try:
            url = sb.get_current_url()
        except Exception:
            url = ""

        if any(x in url for x in ["auth.openai.com", "/login", "/api/auth"]):
            log.warning("Auth page detected (%s) — clearing session before retry (attempt %d/%d)",
                        url, attempt, max_attempts)
            try:
                sb.driver.execute_cdp_cmd("Network.clearBrowserCookies", {})
                sb.driver.execute_cdp_cmd("Network.clearBrowserCache", {})
            except Exception as e:
                log.warning("CDP clear failed: %s", e)
            try:
                sb.driver.execute_script(
                    "try { localStorage.clear(); sessionStorage.clear(); } catch(e) {}"
                )
            except Exception:
                pass
            sleep(500)
            sb.open("https://chatgpt.com")
        elif attempt == 1:
            sb.open("https://chatgpt.com")

        sleep(2500)

        _bypass_ssl_interstitial(sb)
        _dismiss_login_wall(sb)
        sleep(500)

        # ── Robust textarea detection ────────────────────────────────────
        try:
            _wait_for_textarea(sb, timeout=15)
            log.info("Guest session established (attempt %d)", attempt)
            return
        except Exception as exc:
            log.warning("Textarea not found on attempt %d: %s", attempt, exc)

        try:
            url = sb.get_current_url()
        except Exception:
            url = ""
        if any(x in url for x in ["auth.openai.com", "/login", "/api/auth"]):
            log.warning("Still on auth page after dismiss attempt %d, retrying…", attempt)
            sleep(2000)
            continue

        sleep(1500)
        try:
            _wait_for_textarea(sb, timeout=8)
            log.info("Guest session established (attempt %d, delayed)", attempt)
            return
        except Exception:
            pass

    raise RuntimeError(
        f"Could not establish guest session after {max_attempts} attempts. "
        "The proxy IP may be blocked by ChatGPT or the textarea was not found."
    )


# ── Phase 1 — Focus & clear ──────────────────────────────────────────────────

def _focus_and_clear(sb):
    """Focus the textarea using the multi-selector finder, then clear it."""
    import logging
    log = logging.getLogger(__name__)

    el, sel = _wait_for_textarea(sb, timeout=15)
    try:
        sb.click(sel if not sel.startswith("//") else None)
    except Exception:
        try:
            el.click()
        except Exception:
            pass

    sleep(300)

    _js(sb, """
        // Clear both contenteditable divs and plain textareas
        var el = (
            document.getElementById('prompt-textarea') ||
            document.querySelector('[data-sb-found="true"]') ||
            document.querySelector('div[contenteditable="true"]') ||
            document.querySelector('textarea')
        );
        if (!el) return;
        if (el.tagName === 'TEXTAREA') {
            el.value = '';
        } else {
            el.innerHTML = '';
        }
        el.focus();
    """)
    sleep(150)


# ── Phase 2 — Insert text ────────────────────────────────────────────────────

def _insert_text(sb, message: str):
    if len(message) > PASTE_THRESHOLD:
        _js(sb, """
            var msg = arguments[0];
            var el = (
                document.getElementById('prompt-textarea') ||
                document.querySelector('[data-sb-found="true"]') ||
                document.querySelector('div[contenteditable="true"]') ||
                document.querySelector('textarea')
            );
            if (!el) return;
            el.focus();
            document.execCommand('selectAll', false, null);
            document.execCommand('insertText', false, msg);
        """, message)
        sleep(600)

        _js(sb, """
            var el = (
                document.getElementById('prompt-textarea') ||
                document.querySelector('[data-sb-found="true"]') ||
                document.querySelector('div[contenteditable="true"]') ||
                document.querySelector('textarea')
            );
            if (!el) return;
            ['beforeinput', 'input'].forEach(function(t) {
                el.dispatchEvent(new InputEvent(t, { bubbles: true, inputType: 'insertText' }));
            });
            el.dispatchEvent(new Event('change', { bubbles: true }));
        """)
        sleep(500)
    else:
        el, _ = _wait_for_textarea(sb, timeout=10)
        el.send_keys(message)
        sleep(400)


# ── Phase 3 — Click send ─────────────────────────────────────────────────────

def _click_send(sb):
    sent = False

    for sel in SEND_SELECTORS:
        try:
            sb.wait_for_element_visible(sel, timeout=3)
            sb.click(sel)
            sent = True
            break
        except Exception:
            pass

    if not sent:
        clicked = _js(sb, """
            var btn = Array.from(document.querySelectorAll('button')).find(function(b) {
                var l = (b.getAttribute('aria-label') || '').toLowerCase();
                var t = (b.getAttribute('data-testid') || '').toLowerCase();
                return (l.indexOf('send') !== -1 || t.indexOf('send') !== -1) && !b.disabled;
            });
            if (btn) { btn.click(); return true; }
            return false;
        """)

        if not clicked:
            from selenium.webdriver.common.keys import Keys
            from selenium.webdriver.common.action_chains import ActionChains
            el, _ = _wait_for_textarea(sb, timeout=5)
            ActionChains(sb.driver).key_down(Keys.CONTROL).send_keys(Keys.RETURN).key_up(Keys.CONTROL).perform()


# ── Phase 4 — Poll for response ──────────────────────────────────────────────

def _poll_for_response(sb, message: str, is_retry: bool = False):
    for _ in range(60):
        sleep(1000)

        url = sb.get_current_url()
        if any(x in url for x in ["auth.openai.com", "/api/auth/error", "/login"]):
            raise RuntimeError("Auth redirect: " + url)

        _js(sb, """
            var texts = arguments[0];
            var el = Array.from(document.querySelectorAll('button, a')).find(function(b) {
                var t = (b.innerText || b.textContent || '').trim().toLowerCase();
                return texts.indexOf(t) !== -1;
            });
            if (el) el.click();
        """, MODAL_TEXTS)

        got = _js(sb, """
            var bubbles = document.querySelectorAll('[data-message-author-role="assistant"]');
            var last = bubbles[bubbles.length - 1];
            return !!(last && (last.innerText || '').trim().length > 0);
        """)

        if got:
            return True

    return False


# ── Phase 5 — Wait for streaming ─────────────────────────────────────────────

def _wait_for_streaming(sb, max_polls: int = 120) -> str:
    prev, stable, polls = "", 0, 0

    while stable < 3 and polls < max_polls:
        sleep(1500)
        polls += 1

        text = _js(sb, """
            var bubbles = document.querySelectorAll('[data-message-author-role="assistant"]');
            var last = bubbles[bubbles.length - 1];
            return (last && last.innerText) ? last.innerText.trim() : '';
        """)

        if text and text == prev:
            stable += 1
        else:
            stable = 0
            prev = text

    return prev


# ── Public send_message ───────────────────────────────────────────────────────

def send_message(sb, message: str, is_retry: bool = False) -> str:
    _focus_and_clear(sb)
    _insert_text(sb, message)
    _click_send(sb)
    got = _poll_for_response(sb, message, is_retry)
    if not got:
        raise RuntimeError("No assistant response after 60 s")
    reply = _wait_for_streaming(sb)
    if not reply.strip():
        raise RuntimeError("Empty response received — browser will restart")
    return reply


# ── Proxy helpers ─────────────────────────────────────────────────────────────

def _load_proxy(proxy_file: str = "proxy.txt"):
    path = os.path.join(os.path.dirname(__file__), proxy_file)
    if not os.path.exists(path):
        return None
    line = open(path).read().strip()
    if not line:
        return None
    try:
        hostport, userpass = line.split("@", 1)
        host, port = hostport.rsplit(":", 1)
        user, password = userpass.split(":", 1)
        proxy_str = f"{user}:{password}@{host}:{port}"
        return proxy_str, host, port, user, password
    except ValueError:
        raise RuntimeError(
            f"proxy.txt format must be host:port@user:pass, got: {line!r}"
        )


class LocalProxyServer:
    """
    Minimal TCP proxy that injects Proxy-Authorization into CONNECT tunnels
    and forwards to the upstream authenticated proxy.
    """

    CRLF     = b"\r\n"
    CRLFCRLF = b"\r\n\r\n"

    def __init__(self, upstream_host, upstream_port, username, password):
        import base64
        self._host    = upstream_host
        self._port    = int(upstream_port)
        self._auth    = base64.b64encode(
            (username + ":" + password).encode()
        ).decode()
        self._sel     = select
        self._running = True

        self._srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._srv.bind(("127.0.0.1", 0))
        self.local_port = self._srv.getsockname()[1]

        self._thread = threading.Thread(target=self._serve, daemon=True)
        self._thread.start()

    def _serve(self):
        self._srv.listen(64)
        self._srv.settimeout(1.0)
        while self._running:
            try:
                client, _ = self._srv.accept()
            except socket.timeout:
                continue
            except Exception:
                break
            threading.Thread(target=self._handle, args=(client,), daemon=True).start()

    def _recv_headers(self, sock):
        buf = b""
        sock.settimeout(10)
        while self.CRLFCRLF not in buf:
            chunk = sock.recv(4096)
            if not chunk:
                break
            buf += chunk
        return buf

    def _handle(self, client):
        upstream = None
        try:
            raw = self._recv_headers(client)
            if not raw:
                return

            head, _, leftover = raw.partition(self.CRLFCRLF)
            first_line = head.split(self.CRLF)[0].decode(errors="replace")
            parts = first_line.split()
            if len(parts) < 2:
                return
            method = parts[0].upper()
            target = parts[1]

            upstream = socket.create_connection((self._host, self._port), timeout=15)

            if method == "CONNECT":
                req = (
                    "CONNECT " + target + " HTTP/1.1\r\n"
                    "Host: " + target + "\r\n"
                    "Proxy-Authorization: Basic " + self._auth + "\r\n"
                    "\r\n"
                ).encode()
                upstream.sendall(req)
                resp = self._recv_headers(upstream)
                if b" 200" in resp.split(self.CRLF)[0]:
                    client.sendall(b"HTTP/1.1 200 Connection established\r\n\r\n")
                    self._relay(client, upstream)
                else:
                    client.sendall(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
            else:
                lines = head.decode(errors="replace").split("\r\n")
                lines.insert(1, "Proxy-Authorization: Basic " + self._auth)
                fwd = "\r\n".join(lines).encode() + self.CRLFCRLF + leftover
                upstream.sendall(fwd)
                self._relay(client, upstream)

        except Exception:
            pass
        finally:
            for s in (client, upstream):
                if s:
                    try: s.close()
                    except Exception: pass

    def _relay(self, a, b):
        a.settimeout(None)
        b.settimeout(None)
        while True:
            try:
                r, _, _ = self._sel.select([a, b], [], [], 60)
            except Exception:
                break
            if not r:
                break
            for src in r:
                dst = b if src is a else a
                try:
                    data = src.recv(65536)
                    if not data:
                        return
                    dst.sendall(data)
                except Exception:
                    return

    def stop(self):
        self._running = False
        try: self._srv.close()
        except Exception: pass


# ── Singleton browser worker ──────────────────────────────────────────────────

class ChatGPTWorker:
    """
    Manages a single persistent SeleniumBase browser instance.
    Thread-safe: one request at a time via a threading.Lock.
    """

    def __init__(self, headless: bool = True, proxy_file: str = "proxy.txt"):
        self._lock        = threading.Lock()
        self._headless    = headless
        self._proxy_file  = proxy_file
        self._sb_ctx      = None
        self._sb          = None
        self._local_proxy = None
        import logging
        log = logging.getLogger(__name__)
        try:
            self._start()
            self._self_test()
        except Exception as exc:
            log.warning("Initial browser startup failed (%s) — will retry on first request.", exc)

    def _self_test(self):
        import logging
        log = logging.getLogger(__name__)
        log.info("Self-test: sending Hello…")
        try:
            reply = send_message(self._sb, "Hello")
            if reply.strip():
                log.info("Self-test passed ✓  (reply: %r…)", reply[:80])
            else:
                log.warning("Self-test: got empty reply — browser may not be healthy")
        except Exception as exc:
            log.warning("Self-test failed: %s", exc)

    def _start(self):
        import logging
        log = logging.getLogger(__name__)

        if self._sb_ctx is not None:
            try: self._sb_ctx.__exit__(None, None, None)
            except Exception: pass
            self._sb_ctx = None
            self._sb = None

        if self._local_proxy is not None:
            try: self._local_proxy.stop()
            except Exception: pass
            self._local_proxy = None

        proxy_info = _load_proxy(self._proxy_file)
        proxy_str  = None

        if proxy_info:
            proxy_str, host, port, user, password = proxy_info
            log.info("Using upstream proxy: %s…:%s", host[0], port)
            self._local_proxy = LocalProxyServer(host, int(port), user, password)
            local_proxy_url = f"http://127.0.0.1:{self._local_proxy.local_port}"
            proxy_str = local_proxy_url
            log.info("Local auth proxy on port %d", self._local_proxy.local_port)
            check_proxy_leak(proxy_url=local_proxy_url, proxy_host=host)
        else:
            proxy_str = None
            check_proxy_leak(proxy_url=None, proxy_host=None)

        self._sb_ctx = SB(
            browser="chrome",
            headless=self._headless,
            undetectable=True,
            incognito=True,
            proxy=proxy_str,
        )
        self._sb = self._sb_ctx.__enter__()
        establish_guest_session(self._sb)

        if proxy_info:
            try:
                check_proxy_leak(
                    proxy_url=local_proxy_url,
                    proxy_host=host,
                    sb=self._sb,
                )
            except Exception as exc:
                log.warning("Browser-layer IP check failed (non-fatal): %s", exc)

    def chat(self, message: str, max_attempts: int = 10) -> str:
        import logging
        log = logging.getLogger(__name__)

        with self._lock:
            last_exc = None
            for attempt in range(1, max_attempts + 1):
                try:
                    if self._sb is None:
                        self._start()
                    return send_message(self._sb, message)
                except Exception as exc:
                    last_exc = exc
                    log.warning(
                        "Attempt %d/%d failed: %s — restarting browser…",
                        attempt, max_attempts, exc,
                    )
                    try:
                        self._sb_ctx.__exit__(None, None, None)
                    except Exception:
                        pass
                    try:
                        self._start()
                    except Exception as start_exc:
                        log.warning("Browser restart failed: %s", start_exc)

            raise RuntimeError(
                f"Failed after {max_attempts} attempts. Last error: {last_exc}"
            )

    def shutdown(self):
        try:
            self._sb_ctx.__exit__(None, None, None)
        except Exception:
            pass
        if self._local_proxy is not None:
            try: self._local_proxy.stop()
            except Exception: pass
