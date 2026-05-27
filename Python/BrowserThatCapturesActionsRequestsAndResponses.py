#!/usr/bin/env python3
"""
╔══════════════════════════════════════════════════════╗
║              BurpBuddy - Session Capture             ║
║  Captures ALL requests, responses & user activity    ║
║  Press CTRL+C to export everything locally           ║
╚══════════════════════════════════════════════════════╝

Usage:
  python3 burpbuddy.py https://example.com
  python3 burpbuddy.py                      (prompts for URL)
"""

import asyncio
import json
import sys
import os
import signal
import datetime
import base64
import html as html_module
from pathlib import Path
from playwright.async_api import async_playwright, Request, Response

# ─────────────────────────────────────────
#  Global session store
# ─────────────────────────────────────────
session = {
    "url": "",
    "started_at": "",
    "exported_at": "",
    "user_agent": "",
    "page_title": "",
    "dom_snapshot": "",
    "requests": [],
    "responses": [],
    "interactions": [],
    "cookies": [],
    "local_storage": {},
    "session_storage": {},
    "console_logs": [],
    "errors": [],
    "page_navigations": [],
}

stop_event = asyncio.Event()
req_counter = 0
resp_counter = 0
interaction_counter = 0

# ─────────────────────────────────────────
#  JavaScript injected into every page
#  Captures: mouse, keyboard, scroll,
#  drag, click, forms, selection, focus
# ─────────────────────────────────────────
TRACKER_JS = r"""
(function() {
    if (window.__BB_INITIALIZED) return;
    window.__BB_INITIALIZED = true;
    window.__BB_INTERACTIONS = [];

    function ts() { return Date.now(); }

    function elInfo(el) {
        if (!el || el.nodeType !== 1) return {};
        try {
            const rect = el.getBoundingClientRect();
            return {
                tag:      el.tagName || '',
                id:       el.id || '',
                name:     el.getAttribute('name') || '',
                type:     el.getAttribute('type') || '',
                classes:  (el.className || '').toString().trim(),
                href:     el.href || '',
                selector: cssPath(el),
                text:     (el.innerText || '').substring(0, 120),
                html:     (el.outerHTML || '').substring(0, 400),
                rect:     { x: Math.round(rect.x), y: Math.round(rect.y),
                            w: Math.round(rect.width), h: Math.round(rect.height) }
            };
        } catch(e) { return { tag: el.tagName || '?' }; }
    }

    function cssPath(el) {
        if (!el) return '';
        const parts = [];
        let cur = el;
        while (cur && cur.nodeType === 1 && parts.length < 5) {
            let seg = cur.nodeName.toLowerCase();
            if (cur.id) { seg += '#' + cur.id; parts.unshift(seg); break; }
            const cls = [...(cur.classList || [])].slice(0,2).join('.');
            if (cls) seg += '.' + cls;
            parts.unshift(seg);
            cur = cur.parentElement;
        }
        return parts.join(' > ');
    }

    function push(data) {
        window.__BB_INTERACTIONS.push({ t: ts(), url: location.href, ...data });
    }

    // ── Mouse move (100ms throttle) ──
    let _lastMove = 0;
    document.addEventListener('mousemove', e => {
        const now = ts();
        if (now - _lastMove < 100) return;
        _lastMove = now;
        push({ ev: 'mousemove', x: e.clientX, y: e.clientY,
               px: e.pageX, py: e.pageY, target: cssPath(e.target) });
    }, true);

    // ── Mouse down / up ──
    document.addEventListener('mousedown', e => {
        push({ ev: 'mousedown', x: e.clientX, y: e.clientY,
               btn: e.button, el: elInfo(e.target) });
    }, true);

    document.addEventListener('mouseup', e => {
        push({ ev: 'mouseup', x: e.clientX, y: e.clientY,
               btn: e.button, el: elInfo(e.target) });
    }, true);

    // ── Click / dblclick / contextmenu ──
    ['click','dblclick','contextmenu'].forEach(evName => {
        document.addEventListener(evName, e => {
            push({ ev: evName, x: e.clientX, y: e.clientY,
                   btn: e.button, el: elInfo(e.target) });
        }, true);
    });

    // ── Keyboard ──
    document.addEventListener('keydown', e => {
        push({ ev: 'keydown', key: e.key, code: e.code,
               ctrl: e.ctrlKey, alt: e.altKey, shift: e.shiftKey, meta: e.metaKey,
               target: cssPath(e.target) });
    }, true);

    document.addEventListener('keyup', e => {
        push({ ev: 'keyup', key: e.key, code: e.code, target: cssPath(e.target) });
    }, true);

    // ── Scroll (200ms throttle) ──
    let _lastScroll = 0;
    window.addEventListener('scroll', e => {
        const now = ts();
        if (now - _lastScroll < 200) return;
        _lastScroll = now;
        push({ ev: 'scroll', sx: window.scrollX, sy: window.scrollY,
               dh: document.documentElement.scrollHeight,
               vh: window.innerHeight });
    }, true);

    // ── Drag ──
    ['dragstart','drag','dragend','dragenter','dragleave','dragover','drop'].forEach(evName => {
        document.addEventListener(evName, e => {
            push({ ev: evName, x: e.clientX, y: e.clientY, el: elInfo(e.target) });
        }, true);
    });

    // ── Input / change / select ──
    document.addEventListener('input', e => {
        const val = e.target.type === 'password' ? '[REDACTED]'
                  : (e.target.value || '').substring(0, 500);
        push({ ev: 'input', el: elInfo(e.target), value: val });
    }, true);

    document.addEventListener('change', e => {
        const val = e.target.type === 'password' ? '[REDACTED]'
                  : (e.target.value || e.target.checked || '').toString().substring(0, 200);
        push({ ev: 'change', el: elInfo(e.target), value: val });
    }, true);

    // ── Form submit ──
    document.addEventListener('submit', e => {
        push({ ev: 'submit', el: elInfo(e.target),
               action: e.target.action, method: e.target.method });
    }, true);

    // ── Text selection ──
    document.addEventListener('selectionchange', () => {
        const sel = window.getSelection();
        if (sel && sel.toString().trim().length > 1) {
            push({ ev: 'select', text: sel.toString().substring(0, 500) });
        }
    });

    // ── Focus / blur ──
    document.addEventListener('focus', e => {
        push({ ev: 'focus', el: elInfo(e.target) });
    }, true);
    document.addEventListener('blur', e => {
        push({ ev: 'blur', el: elInfo(e.target) });
    }, true);

    // ── Clipboard ──
    ['copy','cut','paste'].forEach(evName => {
        document.addEventListener(evName, e => {
            push({ ev: evName, target: cssPath(e.target) });
        }, true);
    });

    // ── Touch ──
    ['touchstart','touchend','touchmove'].forEach(evName => {
        document.addEventListener(evName, e => {
            const touches = [...(e.touches || [])].slice(0,3).map(t =>
                ({ x: t.clientX, y: t.clientY }));
            push({ ev: evName, touches, target: cssPath(e.target) });
        }, true);
    });

    // ── Pointer events ──
    ['pointerdown','pointerup','pointermove'].forEach(evName => {
        document.addEventListener(evName, e => {
            if (e.pointerType !== 'mouse') {   // skip duplicates for mouse
                push({ ev: evName, ptype: e.pointerType,
                       x: e.clientX, y: e.clientY, pressure: e.pressure });
            }
        }, true);
    });

    // ── Wheel ──
    document.addEventListener('wheel', e => {
        push({ ev: 'wheel', dx: e.deltaX, dy: e.deltaY, x: e.clientX, y: e.clientY });
    }, { passive: true, capture: true });

    // ── Page visibility ──
    document.addEventListener('visibilitychange', () => {
        push({ ev: 'visibility', state: document.visibilityState });
    });

    // ── Window resize ──
    window.addEventListener('resize', () => {
        push({ ev: 'resize', w: window.innerWidth, h: window.innerHeight });
    });

    console.info('%c🕵️ BurpBuddy tracking active', 'color:#6ee7b7;font-weight:bold');
})();
"""


# ─────────────────────────────────────────
#  ANSI colour helpers
# ─────────────────────────────────────────
R  = "\033[91m"
G  = "\033[92m"
Y  = "\033[93m"
B  = "\033[94m"
M  = "\033[95m"
C  = "\033[96m"
W  = "\033[97m"
DIM = "\033[2m"
RST = "\033[0m"
BOLD = "\033[1m"

def banner():
    print(f"""
{C}╔══════════════════════════════════════════════════════╗
║           {W}{BOLD}BurpBuddy — Session Capture Tool{RST}{C}           ║
║  {DIM}Requests · Responses · Mouse · Keyboard · DOM{RST}{C}       ║
╚══════════════════════════════════════════════════════╝{RST}
""")

def fmt_method(m):
    colors = {"GET": G, "POST": Y, "PUT": M, "DELETE": R,
              "PATCH": C, "OPTIONS": DIM, "HEAD": DIM}
    return f"{colors.get(m, W)}{m:<7}{RST}"

def fmt_status(s):
    if s < 300: return f"{G}{s}{RST}"
    if s < 400: return f"{C}{s}{RST}"
    if s < 500: return f"{Y}{s}{RST}"
    return f"{R}{s}{RST}"

def truncate(url, n=90):
    return url[:n] + "…" if len(url) > n else url


# ─────────────────────────────────────────
#  Core capture coroutine
# ─────────────────────────────────────────
async def run_capture(url: str):
    global req_counter, resp_counter, interaction_counter
    session["url"] = url
    session["started_at"] = datetime.datetime.now().isoformat()

    async with async_playwright() as pw:
        browser = await pw.chromium.launch(
            headless=False,
            args=[
                "--no-sandbox",
                "--disable-setuid-sandbox",
                "--disable-blink-features=AutomationControlled",
                "--disable-web-security",
                "--disable-features=IsolateOrigins,site-per-process",
                "--allow-running-insecure-content",
                "--disable-site-isolation-trials",
                "--disable-infobars",
                "--start-maximized",
                "--disable-extensions",
                "--no-first-run",
                "--no-default-browser-check",
            ],
        )

        # viewport=None  →  Playwright does NOT lock the layout to a fixed size.
        # Combined with --start-maximized the window and page resize together freely,
        # so responsive/fluid sites render exactly as they would in a normal browser.
        context = await browser.new_context(
            viewport=None,
            screen={"width": 1920, "height": 1080},  # hint for media queries / window.screen
            ignore_https_errors=True,
            java_script_enabled=True,
            bypass_csp=True,
            user_agent=(
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/124.0.0.0 Safari/537.36"
            ),
            extra_http_headers={
                "Accept-Language": "en-US,en;q=0.9",
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
                "sec-ch-ua": '"Chromium";v="124", "Google Chrome";v="124", "Not-A.Brand";v="99"',
                "sec-ch-ua-mobile": "?0",
                "sec-ch-ua-platform": '"Windows"',
            },
        )

        # Inject tracker before any page script runs
        await context.add_init_script(TRACKER_JS)

        page = await context.new_page()

        # ── Capture requests ──────────────────────
        async def on_request(req: Request):
            global req_counter
            req_counter += 1
            entry = {
                "id":            req_counter,
                "ts":            datetime.datetime.now().isoformat(),
                "url":           req.url,
                "method":        req.method,
                "headers":       dict(req.headers),
                "post_data":     req.post_data,
                "resource_type": req.resource_type,
                "frame_url":     req.frame.url if req.frame else "",
                "is_navigation": req.is_navigation_request(),
            }
            session["requests"].append(entry)
            rtype = f"{DIM}[{req.resource_type[:10]}]{RST}"
            print(f"  {fmt_method(req.method)} {rtype} {truncate(req.url)}")

        # ── Capture responses ─────────────────────
        # Body reading is a background task — never blocks the network stack.
        # Calling await resp.body() inline would stall all concurrent requests
        # (images, scripts, CSS) and cause incomplete page loads.
        async def _read_body(resp: Response, entry: dict):
            ct = entry["content_type"]
            try:
                raw = await resp.body()
                entry["body_size"] = len(raw)
                text_types = ["text","json","xml","javascript","html","svg","css","wasm"]
                if any(t in ct for t in text_types):
                    try:
                        decoded = raw.decode("utf-8", errors="replace")
                        entry["body_text"] = decoded[:200_000] + ("\n…[TRUNCATED]" if len(decoded) > 200_000 else "")
                    except Exception:
                        entry["body_b64"] = base64.b64encode(raw).decode()
                else:
                    if len(raw) < 512_000:
                        entry["body_b64"] = base64.b64encode(raw).decode()
                    else:
                        entry["body_b64"] = "[BINARY {} bytes — too large to inline]".format(len(raw))
            except Exception as e:
                entry["body_text"] = "[Could not read body: {}]".format(e)
            sz = entry.get("body_size", 0)
            status = entry["status"]
            print("       {} {:>8,}B  {}".format(fmt_status(status), sz, truncate(entry["url"], 80)))

        async def on_response(resp: Response):
            global resp_counter
            resp_counter += 1
            ct = resp.headers.get("content-type", "")
            entry = {
                "id":           resp_counter,
                "ts":           datetime.datetime.now().isoformat(),
                "url":          resp.url,
                "status":       resp.status,
                "status_text":  resp.status_text,
                "headers":      dict(resp.headers),
                "content_type": ct,
                "body_size":    0,
                "body_text":    None,
                "body_b64":     None,
            }
            session["responses"].append(entry)
            # Fire-and-forget — page loading is never held up waiting for the body
            asyncio.create_task(_read_body(resp, entry))

        # ── Console & errors ──────────────────────
        def on_console(msg):
            session["console_logs"].append({
                "ts":   datetime.datetime.now().isoformat(),
                "type": msg.type,
                "text": msg.text,
            })

        def on_page_error(err):
            session["errors"].append({
                "ts":      datetime.datetime.now().isoformat(),
                "message": str(err),
            })
            print(f"  {R}[JS ERR]{RST} {str(err)[:120]}")

        def on_navigation(frame):
            if frame == page.main_frame:
                entry = {"ts": datetime.datetime.now().isoformat(), "url": frame.url}
                session["page_navigations"].append(entry)
                print(f"\n  {M}[NAV]{RST} {frame.url}\n")

        page.on("request",    on_request)
        page.on("response",   on_response)
        page.on("console",    on_console)
        page.on("pageerror",  on_page_error)
        page.on("framenavigated", on_navigation)

        print(f"  {G}Opening:{RST}  {W}{url}{RST}")
        print(f"  {Y}CTRL+C{RST} at any time to export & exit\n")
        print(f"  {'METHOD':<12}  {'STATUS':>6}   {'SIZE':>9}   URL")
        print(f"  {'─'*80}")

        try:
            # "load" waits for window.onload (all resources), much more reliable than domcontentloaded
            await page.goto(url, wait_until="load", timeout=60_000)
        except Exception as e:
            print("\n  [WARN] Initial load: {}".format(e))

        # Give dynamic/SPA content a moment to settle after onload
        try:
            await page.wait_for_load_state("networkidle", timeout=10_000)
        except Exception:
            pass  # networkidle timeout is fine — page is still usable

        print("\n  {} Page loaded. Interact with the browser now.".format(G + "✓" + RST))
        print("  {}All events are being captured…{}\n".format(DIM, RST))

        # Wait until CTRL+C fires stop_event
        await stop_event.wait()

        # ── Collect final state ───────────────────
        print(f"\n  {C}Collecting final page state…{RST}")
        try:
            session["interactions"]   = await page.evaluate("window.__BB_INTERACTIONS || []")
            session["dom_snapshot"]   = await page.content()
            session["page_title"]     = await page.title()
            session["cookies"]        = await context.cookies()
            session["local_storage"]  = await page.evaluate("""
                () => {
                    const d = {};
                    for (let i = 0; i < localStorage.length; i++) {
                        const k = localStorage.key(i);
                        d[k] = localStorage.getItem(k);
                    }
                    return d;
                }
            """)
            session["session_storage"] = await page.evaluate("""
                () => {
                    const d = {};
                    for (let i = 0; i < sessionStorage.length; i++) {
                        const k = sessionStorage.key(i);
                        d[k] = sessionStorage.getItem(k);
                    }
                    return d;
                }
            """)
            ua = await page.evaluate("navigator.userAgent")
            session["user_agent"] = ua
        except Exception as e:
            print(f"  {Y}[WARN]{RST} State collection: {e}")

        await context.close()
        await browser.close()


# ─────────────────────────────────────────
#  Export helpers
# ─────────────────────────────────────────
def export_json(ts_str: str) -> str:
    path = f"bb_session_{ts_str}.json"
    with open(path, "w", encoding="utf-8") as f:
        json.dump(session, f, indent=2, default=str, ensure_ascii=False)
    return path


def export_html_report(ts_str: str) -> str:
    path = f"bb_report_{ts_str}.html"

    reqs  = session["requests"]
    resps = session["responses"]
    inters = session["interactions"]

    resp_map = {}
    for r in resps:
        resp_map[r["url"]] = r

    def esc(s):
        return html_module.escape(str(s) if s is not None else "")

    def sz(n):
        if n < 1024: return f"{n} B"
        if n < 1_048_576: return f"{n/1024:.1f} KB"
        return f"{n/1_048_576:.1f} MB"

    def status_class(s):
        if s < 300: return "ok"
        if s < 400: return "redirect"
        if s < 500: return "warn"
        return "err"

    # Build request rows
    req_rows = []
    for req in reqs:
        resp = resp_map.get(req["url"], {})
        status = resp.get("status", "—")
        body_sz = sz(resp.get("body_size", 0)) if resp else "—"
        sc = status_class(status) if isinstance(status, int) else ""
        body_text = esc(resp.get("body_text") or "")[:5000] if resp else ""
        req_headers = esc(json.dumps(req.get("headers", {}), indent=2))
        resp_headers = esc(json.dumps(resp.get("headers", {}), indent=2)) if resp else ""
        post = esc(req.get("post_data") or "")

        req_rows.append(f"""
<tr onclick="toggleDetail('r{req['id']}')" class="req-row">
  <td class="mono dim">{req['id']}</td>
  <td><span class="method {req['method'].lower()}">{esc(req['method'])}</span></td>
  <td class="{sc}">{status}</td>
  <td class="dim">{esc(req.get('resource_type',''))}</td>
  <td class="url-cell" title="{esc(req['url'])}">{esc(truncate(req['url'], 80))}</td>
  <td class="dim">{body_sz}</td>
  <td class="dim mono">{esc(req['ts'][11:19])}</td>
</tr>
<tr id="r{req['id']}" class="detail-row hidden">
  <td colspan="7">
    <div class="detail-box">
      <div class="tabs">
        <button class="tab active" onclick="switchTab(event,'rq{req['id']}h')">Request Headers</button>
        <button class="tab" onclick="switchTab(event,'rq{req['id']}p')">Post Body</button>
        <button class="tab" onclick="switchTab(event,'rq{req['id']}rh')">Response Headers</button>
        <button class="tab" onclick="switchTab(event,'rq{req['id']}rb')">Response Body</button>
      </div>
      <div id="rq{req['id']}h" class="tab-panel active"><pre>{req_headers}</pre></div>
      <div id="rq{req['id']}p" class="tab-panel hidden"><pre>{post or '(none)'}</pre></div>
      <div id="rq{req['id']}rh" class="tab-panel hidden"><pre>{resp_headers or '(no response)'}</pre></div>
      <div id="rq{req['id']}rb" class="tab-panel hidden"><pre class="body-pre">{body_text or '(empty or binary)'}</pre></div>
    </div>
  </td>
</tr>""")

    # Build interaction rows
    inter_rows = []
    ev_counts = {}
    for i in inters:
        ev = i.get("ev", "?")
        ev_counts[ev] = ev_counts.get(ev, 0) + 1

    for i in inters:
        ev = i.get("ev", "?")
        extra = ""
        if ev in ("click","dblclick","contextmenu","mousedown","mouseup"):
            el = i.get("el", {})
            extra = f"<span class='dim'>{esc(el.get('selector',''))}</span>"
            if el.get("text"): extra += f" &nbsp; <span class='dim italic'>&ldquo;{esc(el.get('text','')[:60])}&rdquo;</span>"
        elif ev == "mousemove":
            extra = f"<span class='dim'>({i.get('x')}, {i.get('y')})</span>"
        elif ev in ("keydown","keyup"):
            key = i.get("key","")
            mods = " ".join(filter(None,[
                "Ctrl"  if i.get("ctrl")  else "",
                "Alt"   if i.get("alt")   else "",
                "Shift" if i.get("shift") else "",
                "Meta"  if i.get("meta")  else "",
            ]))
            extra = f"<span class='key'>{esc(mods+' ' if mods else '')}{esc(key)}</span> <span class='dim'>{esc(i.get('target',''))}</span>"
        elif ev == "input":
            el = i.get("el", {})
            extra = f"<span class='dim'>{esc(el.get('selector',''))}</span> = <span class='val'>{esc(str(i.get('value',''))[:80])}</span>"
        elif ev == "scroll":
            extra = f"<span class='dim'>Y={i.get('sy',0)}</span>"
        elif ev == "select":
            extra = f"<span class='val'>{esc(str(i.get('text',''))[:80])}</span>"

        ts_ms = i.get("t", 0)
        t_str = datetime.datetime.fromtimestamp(ts_ms/1000).strftime("%H:%M:%S.%f")[:-3] if ts_ms else "—"

        inter_rows.append(f"""
<tr class="inter-row ev-{esc(ev)}">
  <td class="mono dim">{t_str}</td>
  <td><span class="ev-badge ev-{esc(ev)}">{esc(ev)}</span></td>
  <td class="detail-cell">{extra}</td>
</tr>""")

    # Interaction filter buttons
    filter_btns = "".join(
        f'<button class="ev-filter-btn active" data-ev="{esc(ev)}" onclick="filterEvt(this)">'
        f'{esc(ev)} <span class="cnt">{cnt}</span></button>'
        for ev, cnt in sorted(ev_counts.items(), key=lambda x: -x[1])
    )

    # Stats
    total_size = sum(r.get("body_size", 0) for r in resps)
    errors     = sum(1 for r in resps if r.get("status", 0) >= 400)
    started    = session.get("started_at", "")
    exported   = session.get("exported_at", "")
    dur_s      = ""
    try:
        d = datetime.datetime.fromisoformat(exported) - datetime.datetime.fromisoformat(started)
        dur_s = f"{int(d.total_seconds())}s"
    except Exception:
        pass

    html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>BurpBuddy — {esc(session.get('page_title','Session'))}</title>
<style>
:root {{
  --bg:     #0d1117;
  --bg2:    #161b22;
  --bg3:    #21262d;
  --border: #30363d;
  --txt:    #e6edf3;
  --dim:    #8b949e;
  --green:  #3fb950;
  --yellow: #d29922;
  --red:    #f85149;
  --blue:   #58a6ff;
  --purple: #d2a8ff;
  --cyan:   #76e3ea;
  --orange: #ffa657;
  --pink:   #ff7b72;
}}
*, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}
body {{ background: var(--bg); color: var(--txt); font-family: -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif; font-size: 13px; }}
a {{ color: var(--blue); }}
.hidden {{ display: none !important; }}

/* ── Layout ── */
header {{ background: var(--bg2); border-bottom: 1px solid var(--border); padding: 14px 20px; display:flex; align-items:center; gap:16px; position:sticky; top:0; z-index:100; }}
header h1 {{ font-size: 15px; font-weight: 700; color: var(--cyan); }}
header .url {{ color: var(--dim); font-size: 12px; font-family: monospace; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; max-width:500px; }}
.stats {{ margin-left: auto; display:flex; gap: 20px; }}
.stat {{ text-align:center; }}
.stat .val {{ font-size: 18px; font-weight: 700; color: var(--blue); }}
.stat .lbl {{ font-size: 10px; color: var(--dim); text-transform: uppercase; letter-spacing:.05em; }}

nav {{ background: var(--bg2); border-bottom: 1px solid var(--border); display:flex; gap:0; position:sticky; top:57px; z-index:99; }}
nav button {{ background:none; border:none; color: var(--dim); padding: 10px 20px; cursor:pointer; font-size: 13px; border-bottom: 2px solid transparent; transition: all .15s; }}
nav button:hover {{ color: var(--txt); }}
nav button.active {{ color: var(--blue); border-bottom-color: var(--blue); }}

.panel {{ display:none; }}
.panel.active {{ display:block; }}

/* ── Search bar ── */
.toolbar {{ padding: 10px 16px; background: var(--bg2); border-bottom: 1px solid var(--border); display:flex; gap:10px; align-items:center; flex-wrap:wrap; }}
.toolbar input {{ background: var(--bg3); border: 1px solid var(--border); color: var(--txt); padding: 5px 10px; border-radius: 6px; font-size: 12px; width: 260px; }}
.toolbar input:focus {{ outline: none; border-color: var(--blue); }}
.toolbar label {{ color: var(--dim); font-size: 12px; display:flex; align-items:center; gap:5px; cursor:pointer; }}
.toolbar input[type=checkbox] {{ cursor:pointer; }}
.export-btn {{ margin-left:auto; background: var(--blue); color: #000; border: none; padding: 5px 14px; border-radius: 6px; font-size: 12px; cursor:pointer; font-weight:600; }}
.export-btn:hover {{ opacity:.85; }}

/* ── Table ── */
table {{ width:100%; border-collapse:collapse; }}
th {{ background: var(--bg3); color: var(--dim); text-align:left; padding: 8px 10px; font-size: 11px; text-transform:uppercase; letter-spacing:.06em; border-bottom: 1px solid var(--border); position:sticky; top:113px; z-index:50; }}
td {{ padding: 6px 10px; border-bottom: 1px solid var(--border); vertical-align:top; }}
tr.req-row {{ cursor:pointer; }}
tr.req-row:hover td {{ background: var(--bg2); }}
.mono {{ font-family: 'SF Mono',Consolas,monospace; font-size: 11px; }}
.dim {{ color: var(--dim); }}
.italic {{ font-style:italic; }}
.url-cell {{ max-width: 500px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; font-family:monospace; font-size:11px; }}

/* ── Method badges ── */
.method {{ display:inline-block; padding: 1px 6px; border-radius: 4px; font-weight:700; font-size:11px; font-family:monospace; }}
.get     {{ background:#1a3a2a; color: var(--green); }}
.post    {{ background:#3a2a00; color: var(--yellow); }}
.put     {{ background:#2a1a3a; color: var(--purple); }}
.delete  {{ background:#3a1a1a; color: var(--red); }}
.patch   {{ background:#1a2a3a; color: var(--cyan); }}
.options {{ background: var(--bg3); color: var(--dim); }}
.head    {{ background: var(--bg3); color: var(--dim); }}

/* ── Status ── */
.ok       {{ color: var(--green); font-weight:700; }}
.redirect {{ color: var(--cyan); font-weight:700; }}
.warn     {{ color: var(--yellow); font-weight:700; }}
.err      {{ color: var(--red); font-weight:700; }}

/* ── Detail / tabs ── */
.detail-row td {{ background: var(--bg2); padding: 0; }}
.detail-box {{ padding: 12px 16px; }}
.tabs {{ display:flex; gap:4px; margin-bottom: 8px; }}
.tab {{ background: var(--bg3); border: 1px solid var(--border); color: var(--dim); padding: 4px 12px; border-radius: 4px; cursor:pointer; font-size: 11px; }}
.tab.active {{ background: var(--blue); color: #000; border-color: var(--blue); font-weight:600; }}
.tab-panel pre {{ background: var(--bg); border: 1px solid var(--border); border-radius: 6px; padding: 10px; overflow: auto; font-size: 11px; max-height: 300px; font-family: 'SF Mono',Consolas,monospace; white-space:pre-wrap; word-break:break-all; }}
.body-pre {{ color: var(--txt); }}
.tab-panel.hidden {{ display:none; }}

/* ── Interactions ── */
.ev-filter-wrap {{ padding: 10px 16px; background: var(--bg2); border-bottom: 1px solid var(--border); display:flex; gap:6px; flex-wrap:wrap; align-items:center; }}
.ev-filter-btn {{ background: var(--bg3); border: 1px solid var(--border); color: var(--dim); padding: 3px 10px; border-radius: 20px; cursor:pointer; font-size: 11px; }}
.ev-filter-btn.active {{ border-color: var(--blue); color: var(--blue); }}
.ev-filter-btn .cnt {{ color: var(--dim); }}
.ev-badge {{ display:inline-block; padding: 1px 8px; border-radius: 4px; font-size: 11px; font-family:monospace; font-weight:600; }}
.inter-row td {{ border-bottom: 1px solid var(--border); padding: 4px 10px; }}
.inter-row:hover td {{ background: var(--bg2); }}
.detail-cell {{ max-width: 700px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }}
.key {{ background: var(--bg3); border: 1px solid var(--border); border-radius: 4px; padding: 1px 6px; font-family:monospace; font-size:11px; }}
.val {{ color: var(--orange); font-family: monospace; }}

/* ── Event badge colors ── */
.ev-click,.ev-dblclick,.ev-contextmenu,.ev-mousedown,.ev-mouseup {{ background:#1a2a3a; color: var(--blue); }}
.ev-mousemove {{ background:#1a1a2a; color: #5560aa; }}
.ev-keydown,.ev-keyup {{ background:#2a1a2a; color: var(--purple); }}
.ev-input,.ev-change {{ background:#2a2a1a; color: var(--orange); }}
.ev-scroll,.ev-wheel {{ background:#1a2a2a; color: var(--cyan); }}
.ev-dragstart,.ev-drag,.ev-dragend,.ev-drop,.ev-dragenter,.ev-dragleave,.ev-dragover {{ background:#1a3a2a; color: var(--green); }}
.ev-submit {{ background:#3a2a2a; color: var(--red); }}
.ev-select {{ background:#3a1a3a; color: var(--pink); }}
.ev-focus,.ev-blur {{ background:#2a2a2a; color: var(--dim); }}
.ev-copy,.ev-cut,.ev-paste {{ background:#1a3a2a; color: var(--green); }}
.ev-touchstart,.ev-touchend,.ev-touchmove {{ background:#2a3a1a; color: var(--yellow); }}
.ev-pointerdown,.ev-pointerup,.ev-pointermove {{ background:#1a2a3a; color: var(--blue); }}
.ev-resize,.ev-visibility {{ background:#2a2a3a; color: var(--dim); }}
.ev-nav {{ background:#3a1a1a; color: var(--red); }}

/* ── Raw JSON ── */
#rawpanel {{ padding: 16px; }}
#rawpanel pre {{ background: var(--bg2); border: 1px solid var(--border); border-radius: 8px; padding: 16px; overflow:auto; font-size:11px; font-family:'SF Mono',Consolas,monospace; max-height: 80vh; }}

/* ── DOM ── */
#dompanel {{ padding: 16px; }}
#dompanel pre {{ background: var(--bg2); border: 1px solid var(--border); border-radius: 8px; padding: 16px; overflow:auto; font-size:11px; font-family:'SF Mono',Consolas,monospace; max-height: 80vh; white-space:pre-wrap; word-break:break-all; }}

/* ── Cookies/Storage ── */
#cookiepanel {{ padding: 16px; }}
.kv-table {{ width:100%; border-collapse:collapse; margin-bottom: 24px; }}
.kv-table th {{ background: var(--bg3); color: var(--dim); padding: 6px 10px; text-align:left; font-size:11px; text-transform:uppercase; }}
.kv-table td {{ padding: 6px 10px; border-bottom: 1px solid var(--border); font-family:monospace; font-size:11px; word-break:break-all; }}
.section-title {{ color: var(--blue); font-weight:700; margin-bottom: 10px; font-size:13px; }}
</style>
</head>
<body>

<header>
  <h1>🕵️ BurpBuddy</h1>
  <div class="url" title="{esc(session.get('url',''))}">📡 {esc(session.get('url',''))}</div>
  <div class="stats">
    <div class="stat"><div class="val">{len(reqs)}</div><div class="lbl">Requests</div></div>
    <div class="stat"><div class="val">{errors}</div><div class="lbl">Errors</div></div>
    <div class="stat"><div class="val">{len(inters)}</div><div class="lbl">Events</div></div>
    <div class="stat"><div class="val">{sz(total_size)}</div><div class="lbl">Total Size</div></div>
    <div class="stat"><div class="val">{dur_s}</div><div class="lbl">Duration</div></div>
  </div>
</header>

<nav>
  <button class="active" onclick="showPanel('network',this)">🌐 Network ({len(reqs)})</button>
  <button onclick="showPanel('interactions',this)">🖱️ Interactions ({len(inters)})</button>
  <button onclick="showPanel('cookies',this)">🍪 Cookies &amp; Storage</button>
  <button onclick="showPanel('dom',this)">🏗️ DOM Snapshot</button>
  <button onclick="showPanel('raw',this)">{{ }} Raw JSON</button>
</nav>

<!-- ══ NETWORK ══ -->
<div id="network" class="panel active">
  <div class="toolbar">
    <input type="text" id="netSearch" placeholder="Filter by URL, method, status…" oninput="filterNet()">
    <label><input type="checkbox" id="hideAssets" onchange="filterNet()"> Hide assets (img/font/css)</label>
    <label><input type="checkbox" id="onlyErrors" onchange="filterNet()"> Errors only</label>
    <button class="export-btn" onclick="downloadJSON()">⬇ Export JSON</button>
  </div>
  <table id="netTable">
    <thead>
      <tr>
        <th>#</th><th>Method</th><th>Status</th><th>Type</th><th>URL</th><th>Size</th><th>Time</th>
      </tr>
    </thead>
    <tbody id="netBody">
      {''.join(req_rows)}
    </tbody>
  </table>
</div>

<!-- ══ INTERACTIONS ══ -->
<div id="interactions" class="panel">
  <div class="toolbar">
    <input type="text" id="interSearch" placeholder="Filter interactions…" oninput="filterInter()">
  </div>
  <div class="ev-filter-wrap">
    <span style="color:var(--dim);font-size:11px;margin-right:4px">Filter:</span>
    <button class="ev-filter-btn active" data-ev="__ALL__" onclick="filterEvt(this)">All ({len(inters)})</button>
    {filter_btns}
  </div>
  <table id="interTable">
    <thead>
      <tr><th style="top:155px">Time</th><th style="top:155px">Event</th><th style="top:155px">Detail</th></tr>
    </thead>
    <tbody id="interBody">
      {''.join(inter_rows)}
    </tbody>
  </table>
</div>

<!-- ══ COOKIES & STORAGE ══ -->
<div id="cookies" class="panel">
<div id="cookiepanel">
  <div class="section-title">🍪 Cookies ({len(session.get('cookies',[]))})</div>
  <table class="kv-table">
    <thead><tr><th>Name</th><th>Value</th><th>Domain</th><th>Path</th><th>Secure</th><th>HttpOnly</th></tr></thead>
    <tbody>
      {''.join(f"<tr><td>{esc(c.get('name',''))}</td><td>{esc(str(c.get('value',''))[:200])}</td><td>{esc(c.get('domain',''))}</td><td>{esc(c.get('path',''))}</td><td>{'✓' if c.get('secure') else ''}</td><td>{'✓' if c.get('httpOnly') else ''}</td></tr>" for c in session.get('cookies',[]))}
    </tbody>
  </table>

  <div class="section-title">💾 localStorage ({len(session.get('local_storage',{}))} keys)</div>
  <table class="kv-table">
    <thead><tr><th>Key</th><th>Value</th></tr></thead>
    <tbody>
      {''.join(f"<tr><td>{esc(k)}</td><td>{esc(str(v)[:400])}</td></tr>" for k,v in session.get('local_storage',{}).items())}
    </tbody>
  </table>

  <div class="section-title">🗃️ sessionStorage ({len(session.get('session_storage',{}))} keys)</div>
  <table class="kv-table">
    <thead><tr><th>Key</th><th>Value</th></tr></thead>
    <tbody>
      {''.join(f"<tr><td>{esc(k)}</td><td>{esc(str(v)[:400])}</td></tr>" for k,v in session.get('session_storage',{}).items())}
    </tbody>
  </table>

  <div class="section-title">⚠️ Console Logs ({len(session.get('console_logs',[]))})</div>
  <table class="kv-table">
    <thead><tr><th>Time</th><th>Type</th><th>Message</th></tr></thead>
    <tbody>
      {''.join(f"<tr><td>{esc(c.get('ts','')[11:19])}</td><td>{esc(c.get('type',''))}</td><td>{esc(c.get('text','')[:300])}</td></tr>" for c in session.get('console_logs',[]))}
    </tbody>
  </table>
</div>
</div>

<!-- ══ DOM ══ -->
<div id="dom" class="panel">
  <div id="dompanel">
    <div class="section-title">🏗️ DOM Snapshot — {esc(session.get('page_title',''))}</div>
    <pre>{esc(session.get('dom_snapshot',''))}</pre>
  </div>
</div>

<!-- ══ RAW JSON ══ -->
<div id="raw" class="panel">
  <div id="rawpanel">
    <div class="section-title">{{ }} Raw Session JSON</div>
    <pre id="rawJson"></pre>
  </div>
</div>

<script>
const SESSION = {json.dumps({"url": session.get("url"), "started_at": session.get("started_at"), "exported_at": session.get("exported_at"), "requests": reqs, "responses": [{k: v for k, v in r.items() if k != "body_text" and k != "body_b64"} for r in resps], "interactions": inters, "cookies": session.get("cookies"), "local_storage": session.get("local_storage"), "console_logs": session.get("console_logs")}, default=str)};

function showPanel(id, btn) {{
  document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
  document.querySelectorAll('nav button').forEach(b => b.classList.remove('active'));
  document.getElementById(id).classList.add('active');
  btn.classList.add('active');
  if (id === 'raw') {{
    document.getElementById('rawJson').textContent = JSON.stringify(SESSION, null, 2);
  }}
}}

function toggleDetail(id) {{
  const row = document.getElementById(id);
  row.classList.toggle('hidden');
}}

function switchTab(e, id) {{
  const box = e.target.closest('.detail-box');
  box.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
  box.querySelectorAll('.tab-panel').forEach(p => {{ p.classList.remove('active'); p.classList.add('hidden'); }});
  e.target.classList.add('active');
  const panel = document.getElementById(id);
  panel.classList.remove('hidden');
  panel.classList.add('active');
}}

// ── Network filter ──
function filterNet() {{
  const q = document.getElementById('netSearch').value.toLowerCase();
  const hideAssets = document.getElementById('hideAssets').checked;
  const onlyErrors = document.getElementById('onlyErrors').checked;
  const assetTypes = new Set(['image','font','stylesheet','media','other']);

  document.querySelectorAll('#netBody tr.req-row').forEach((row, i) => {{
    const url     = (row.querySelector('.url-cell')?.title || '').toLowerCase();
    const method  = (row.querySelector('.method')?.textContent || '').toLowerCase();
    const status  = row.querySelector('.ok, .redirect, .warn, .err')?.textContent || '';
    const rtype   = row.cells[3]?.textContent?.trim().toLowerCase() || '';
    const isAsset = hideAssets && assetTypes.has(rtype);
    const isErr   = onlyErrors && !row.querySelector('.warn, .err');
    const matches = !q || url.includes(q) || method.includes(q) || status.includes(q);
    const detailRow = row.nextElementSibling;
    const hide = !matches || isAsset || isErr;
    row.style.display = hide ? 'none' : '';
    if (detailRow?.classList.contains('detail-row')) detailRow.style.display = hide ? 'none' : '';
  }});
}}

// ── Interaction filters ──
let activeEvFilter = '__ALL__';
function filterEvt(btn) {{
  document.querySelectorAll('.ev-filter-btn').forEach(b => b.classList.remove('active'));
  btn.classList.add('active');
  activeEvFilter = btn.dataset.ev;
  applyInterFilter();
}}
function filterInter() {{ applyInterFilter(); }}
function applyInterFilter() {{
  const q = document.getElementById('interSearch').value.toLowerCase();
  document.querySelectorAll('#interBody tr.inter-row').forEach(row => {{
    const ev  = [...row.classList].find(c => c.startsWith('ev-'))?.slice(3) || '';
    const txt = row.textContent.toLowerCase();
    const evOk = activeEvFilter === '__ALL__' || ev === activeEvFilter;
    const qOk  = !q || txt.includes(q);
    row.style.display = (evOk && qOk) ? '' : 'none';
  }});
}}

// ── Download JSON ──
function downloadJSON() {{
  const blob = new Blob([JSON.stringify(SESSION, null, 2)], {{type:'application/json'}});
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'bb_session.json';
  a.click();
}}
</script>
</body>
</html>"""

    with open(path, "w", encoding="utf-8") as f:
        f.write(html_content)
    return path


# ─────────────────────────────────────────
#  Signal handler & main
# ─────────────────────────────────────────
def do_export():
    ts_str = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    session["exported_at"] = datetime.datetime.now().isoformat()

    print(f"\n{C}{'─'*56}{RST}")
    print(f"  {W}{BOLD}Exporting session…{RST}")

    json_path = export_json(ts_str)
    html_path = export_html_report(ts_str)

    reqs   = len(session["requests"])
    resps  = len(session["responses"])
    inters = len(session["interactions"])
    errs   = sum(1 for r in session["responses"] if r.get("status", 0) >= 400)
    total  = sum(r.get("body_size", 0) for r in session["responses"])

    def sz(n):
        if n < 1024: return f"{n} B"
        if n < 1_048_576: return f"{n/1024:.1f} KB"
        return f"{n/1_048_576:.1f} MB"

    print(f"\n  {G}✅ Export complete!{RST}")
    print(f"  {B}📄 JSON:{RST}  {json_path}  ({sz(os.path.getsize(json_path))})")
    print(f"  {B}🌐 HTML:{RST}  {html_path}  ({sz(os.path.getsize(html_path))})")
    print(f"\n  {W}Summary{RST}")
    print(f"    Requests captured  : {G}{reqs}{RST}")
    print(f"    Responses captured : {G}{resps}{RST}")
    print(f"    HTTP errors (4xx+) : {R if errs else G}{errs}{RST}")
    print(f"    Interactions logged: {G}{inters}{RST}")
    print(f"    Total response size: {G}{sz(total)}{RST}")
    print(f"    Console log entries: {G}{len(session.get('console_logs',[]))}{RST}")
    print(f"{C}{'─'*56}{RST}\n")


async def main():
    banner()

    if len(sys.argv) >= 2:
        url = sys.argv[1]
    else:
        url = input(f"  {W}Enter URL to capture{RST} (e.g. https://example.com): ").strip()
        if not url:
            url = "https://example.com"

    if not url.startswith("http"):
        url = "https://" + url

    loop = asyncio.get_event_loop()

    def _sigint():
        print(f"\n  {Y}⚡ CTRL+C — stopping capture…{RST}")
        stop_event.set()

    loop.add_signal_handler(signal.SIGINT, _sigint)

    try:
        await run_capture(url)
    except Exception as e:
        print(f"\n  {R}[ERROR]{RST} {e}")
        stop_event.set()

    do_export()


if __name__ == "__main__":
    asyncio.run(main())
