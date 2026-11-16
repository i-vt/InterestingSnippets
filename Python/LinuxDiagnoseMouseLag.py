#!/usr/bin/env python3
"""
mouse-lag-diag.py -- find out WHY the mouse pointer freezes and clicks vanish.

Works on Debian/any Linux, X11 or Wayland, NVIDIA or not. Standard library
only; run with sudo for the fullest report (journal/dmesg access).

While you move the mouse and click, it captures:
  * every evdev event from the mouse with precise timestamps
  * "motion stalls": gaps between movement events longer than a threshold
    (your freeze), with the system state surrounding each one
  * click press/release pairing -- a "release without press" means events
    were lost below the window system
  * 10 Hz background samples: GPU util (nvidia-smi), load average, CPU
    busy/iowait, average CPU MHz, IRQ totals for USB controllers + GPU,
    memory pressure

Plus a one-off static report: USB autosuspend state (classic cause of lost
mouse input), CPU governor, GPU persistence mode, IRQ sharing between the
GPU and USB controllers, Xorg/journal errors, AMD fTPM stutter.

Usage:
  sudo python3 mouse-lag-diag.py            # 60 s capture (default)
  sudo python3 mouse-lag-diag.py -d 120     # 2 minutes
  sudo python3 mouse-lag-diag.py --list     # list pointer devices, then pick
  sudo python3 mouse-lag-diag.py --event 24 -d 90 -t 40

Tips:
  -t is the stall threshold in ms (default 60). Healthy gaps at 125-1000 Hz
  polling are ~1-8 ms, so anything well above that is a freeze. Keep moving
  the mouse continuously (big circles) and click left/right buttons while it
  runs; reproduce the lag during the window.
"""
from __future__ import annotations

import argparse
import collections
import json
import os
import platform
import re
import select
import shutil
import struct
import subprocess
import sys
import threading
import time

EVENT_FORMAT = "llHHi"                      # 24 bytes on 64-bit
EVENT_SIZE = struct.calcsize(EVENT_FORMAT)
EV_KEY, EV_REL = 0x01, 0x02
BTN_NAMES = {272: "LEFT", 273: "RIGHT", 274: "MIDDLE", 275: "SIDE",
             276: "EXTRA", 277: "FORWARD", 278: "BACK", 330: "TOUCH"}
IRQ_PAT = re.compile(r"(xhci_hcd|ohci_hcd|ehci_hcd|nvidia|NVidia)", re.I)


def read_sys(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return None


def run_cmd(cmd, timeout=15):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.stdout
    except Exception:
        return None


def cpu_model():
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if line.startswith("model name"):
                    return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return "?"


# ---------------------------------------------------------------- devices
def discover_mice():
    mice = []
    try:
        data = open("/proc/bus/input/devices").read()
    except OSError:
        return mice
    for block in data.strip().split("\n\n"):
        info = {}
        for ln in block.splitlines():
            if ln.startswith("N: Name="):
                info["name"] = ln.split("=", 1)[1].strip().strip('"')
            elif ln.startswith("H: Handlers="):
                h = ln.split("=", 1)[1].split()
                ev = [x for x in h if x.startswith("event")]
                info["event"] = ev[0] if ev else None
                info["handlers"] = h
            elif ln.startswith("S: Sysfs="):
                info["sysfs"] = ln.split("=", 1)[1].strip()
        if info.get("event") and any(x.startswith("mouse") for x in info.get("handlers", [])):
            mice.append(info)
    return mice


def dump_all_input_devices():
    """Fallback diagnostic: show every input block so nothing can hide."""
    try:
        data = open("/proc/bus/input/devices").read()
    except OSError as e:
        print(f"cannot read /proc/bus/input/devices: {e}")
        return
    for block in data.strip().split("\n\n"):
        name = handlers = ""
        for ln in block.splitlines():
            if ln.startswith("N: Name="):
                name = ln.split("=", 1)[1].strip()
            elif ln.startswith("H: Handlers="):
                handlers = ln.split("=", 1)[1].strip()
        print(f"  {name:40s} handlers: {handlers}")


def usb_device_dir(mouse):
    """Walk up from the input sysfs node to the owning USB device dir."""
    p = os.path.realpath(os.path.join("/sys", mouse["sysfs"].lstrip("/")))
    while p.startswith("/sys/"):
        if os.path.exists(os.path.join(p, "idVendor")):
            return p
        parent = os.path.dirname(p)
        if parent == p:
            break
        p = parent
    return None


# ---------------------------------------------------------------- static checks
def irq_table():
    rows = []
    try:
        lines = open("/proc/interrupts").read().splitlines()[1:]
    except OSError:
        return rows
    for line in lines:
        f = line.split()
        if not f:
            continue
        irq = f[0].rstrip(":")
        counts, i = [], 1
        while i < len(f) and f[i].isdigit():
            counts.append(int(f[i])); i += 1
        name = " ".join(f[i:]).strip()
        if IRQ_PAT.search(name):
            rows.append({"irq": irq, "total": sum(counts), "name": name,
                         "affinity": read_sys(f"/proc/irq/{irq}/smp_affinity_list") or "?"})
    return rows


def usb_power_scan():
    rows = []
    try:
        devs = sorted(os.listdir("/sys/bus/usb/devices"))
    except OSError:
        return read_sys("/sys/module/usbcore/parameters/autosuspend"), rows
    for dev in devs:
        base = os.path.join("/sys/bus/usb/devices", dev)
        if not os.path.isdir(base) or ":" in dev:      # skip interface nodes
            continue
        control = read_sys(os.path.join(base, "power/control"))
        if control is None:
            continue
        vid, pid = read_sys(os.path.join(base, "idVendor")), read_sys(os.path.join(base, "idProduct"))
        rows.append({"dev": dev,
                     "id": f"{vid}:{pid}" if vid else "?",
                     "product": read_sys(os.path.join(base, "product")) or "?",
                     "control": control,
                     "delay_ms": read_sys(os.path.join(base, "power/autosuspend_delay_ms"))})
    return read_sys("/sys/module/usbcore/parameters/autosuspend"), rows


def gpu_compute_apps():
    if not shutil.which("nvidia-smi"):
        return []
    out = run_cmd(["nvidia-smi", "--query-compute-apps=pid,process_name,used_memory",
                   "--format=csv,noheader"], timeout=8)
    apps = []
    if out:
        for ln in out.splitlines():
            p = [x.strip() for x in ln.split(",")]
            if len(p) >= 3:
                apps.append({"pid": p[0], "name": p[1], "mib": p[2]})
    return apps


def gui_session_info():
    out = run_cmd(["loginctl", "list-sessions", "--no-legend"], timeout=8)
    if not out:
        return None
    for line in out.splitlines():
        cols = line.split()
        if len(cols) < 4:
            continue
        info = run_cmd(["loginctl", "show-session", cols[0], "--no-pager"], timeout=8) or ""
        d = dict(kv.split("=", 1) for kv in info.splitlines() if "=" in kv)
        if d.get("State") == "active" and d.get("Desktop"):
            return {"type": d.get("Type"), "desktop": d.get("Desktop"),
                    "user": d.get("Name"), "seat": d.get("Seat")}
    return None


def journal_hits():
    out = run_cmd(["journalctl", "-b", "-p", "warning", "--no-pager", "-o", "short"], timeout=25)
    if not out:
        return None, None
    pat = re.compile(r"(ftpm|usb .*(reset|disconnect|stall)|Xid|\(EE\)|error|fail|"
                     r"dropped|off the bus)", re.I)
    hits = [l for l in out.splitlines() if pat.search(l)
            and not l.lstrip().startswith("(--)")]
    return hits[-30:], None


def dmesg_hits():
    out = run_cmd(["dmesg"], timeout=10)
    if not out:
        return None
    pat = re.compile(r"(ftpm|stutter|usb .*(reset|disconnect|stall)|nvidia .*err)", re.I)
    return [l for l in out.splitlines() if pat.search(l)][-20:]


def xorg_log_summary():
    cands = ["/var/log/Xorg.0.log"]
    cands += [f"/home/{u}/.local/share/xorg/Xorg.0.log"
              for u in (os.listdir("/home") if os.path.isdir("/home") else [])]
    for p in cands:
        if not os.path.exists(p) or not os.access(p, os.R_OK):
            continue
        try:
            lines = open(p, errors="replace").read().splitlines()
        except OSError:
            continue
        ee = [l.strip() for l in lines
              if "(EE)" in l and "(WW) warning" not in l]
        return {"path": p, "ee_count": len(ee), "ee_tail": ee[-6:]}
    return None


# ---------------------------------------------------------------- samplers
def avg_cpu_mhz():
    try:
        data = open("/proc/cpuinfo").read()
        mhz = [float(x) for x in re.findall(r"^cpu MHz\s*:\s*([0-9.]+)", data, re.M)]
        return round(sum(mhz) / len(mhz), 0) if mhz else None
    except OSError:
        return None


def irq_counts():
    d = {}
    try:
        lines = open("/proc/interrupts").read().splitlines()[1:]
    except OSError:
        return d
    for line in lines:
        f = line.split()
        if not f:
            continue
        counts, i = [], 1
        while i < len(f) and f[i].isdigit():
            counts.append(int(f[i])); i += 1
        name = " ".join(f[i:])
        if IRQ_PAT.search(name):
            d[f[0].rstrip(":")] = sum(counts)
    return d


def mem_info():
    try:
        kv = {}
        for line in open("/proc/meminfo"):
            k, v = line.split(":", 1)
            kv[k] = int(v.strip().split()[0])  # kB
        return {"mem_avail_gb": round(kv.get("MemAvailable", 0) / 1048576, 2),
                "swap_free_gb": round(kv.get("SwapFree", 0) / 1048576, 2)}
    except (OSError, ValueError):
        return {}


class GpuPoller(threading.Thread):
    def __init__(self, cache, stop):
        super().__init__(daemon=True)
        self.cache, self.stop = cache, stop

    def run(self):
        if not shutil.which("nvidia-smi"):
            return
        while not self.stop.is_set():
            out = run_cmd(["nvidia-smi",
                           "--query-gpu=utilization.gpu,utilization.memory,memory.used,persistence_mode",
                           "--format=csv,noheader,nounits"], timeout=8)
            if out:
                p = [x.strip() for x in out.split(",")]
                if len(p) >= 4:
                    try:
                        self.cache["gpu"] = {"util": float(p[0]), "mem_util": float(p[1]),
                                             "mem_mib": float(p[2]), "pers": p[3]}
                    except ValueError:
                        pass
            self.stop.wait(0.7)


class Sampler(threading.Thread):
    """10 Hz background samples of system state into a ring buffer."""
    def __init__(self, buf, stop, gpu_cache, interval=0.1):
        super().__init__(daemon=True)
        self.buf, self.stop, self.gpu_cache, self.interval = buf, stop, gpu_cache, interval

    def run(self):
        prev = None
        while not self.stop.is_set():
            s = {"t": time.monotonic()}
            try:
                with open("/proc/stat") as f:
                    cur = list(map(int, f.readline().split()[1:9]))
                if prev:
                    d = [c - p for c, p in zip(cur, prev)]
                    tot = sum(d) or 1
                    s["busy"] = round(100.0 * (tot - d[3] - d[4]) / tot, 1)
                    s["iowait"] = round(100.0 * d[4] / tot, 1)
                prev = cur
            except (OSError, ValueError):
                pass
            try:
                s["load1"] = round(os.getloadavg()[0], 2)
            except OSError:
                pass
            mhz = avg_cpu_mhz()
            if mhz:
                s["mhz"] = mhz
            s["irq"] = irq_counts()
            s.update(mem_info())
            g = self.gpu_cache.get("gpu")
            if g:
                s["gpu"] = g["util"]; s["gpumem"] = g["mem_mib"]
            self.buf.append(s)
            self.stop.wait(self.interval)


def window_stats(buf, t0, t1):
    rows = [s for s in buf if t0 <= s["t"] <= t1]
    out = {"samples": len(rows)}
    for key in ("gpu", "busy", "iowait", "load1", "mhz", "gpumem"):
        vals = [s[key] for s in rows if key in s]
        if vals:
            out[key + "_max"] = max(vals)
            out[key + "_avg"] = round(sum(vals) / len(vals), 1)
    for irq, _ in (rows[-1].get("irq", {}) if rows else {}).items():
        first = next((r["irq"].get(irq) for r in rows if irq in r.get("irq", {})), None)
        last = next((r["irq"].get(irq) for r in reversed(rows) if irq in r.get("irq", {})), None)
        if first is not None and last is not None and last > first:
            out.setdefault("irq_delta", {})[irq] = last - first
    return out


KEYBOARD_WORDS = re.compile(r"keyboard|ornata|blackwidow|huntsman|cynosa|deathstalker|"
                            r"tartarus|keypad|numpad", re.I)
MOUSE_WORDS = re.compile(r"mouse|logitech|g502|g402|g302|g pro|mx master|mx anywhere|mx vertical|"
                         r"deathadder|viper|basilisk|naga|mamba|orochi|atheris|glorious|"
                         r"model o|razer", re.I)


def rank_mice(mice):
    """Score candidates so phantom 'mouse' interfaces on keyboards lose to real mice."""
    def score(m):
        n = m["name"]
        s = 0
        if MOUSE_WORDS.search(n):
            s += 2
        if KEYBOARD_WORDS.search(n):
            s -= 3
        if "receiver" in n.lower():
            s += 1
        return s
    return sorted(mice, key=lambda m: -score(m))


# ---------------------------------------------------------------- monitor
def monitor(mouse, args, buf, stop):
    node = f"/dev/input/{mouse['event']}"
    fd = os.open(node, os.O_RDONLY | os.O_NONBLOCK)
    deadline = time.monotonic() + args.duration
    thr = args.threshold / 1000.0
    grace = args.grace / 1000.0

    state = {
        "total_events": 0, "total_rel": 0,
        "last_rel": None, "recent_rel": collections.deque(maxlen=64),
        "episode": None, "stalls": [], "pauses": 0,
        "press": {}, "clicks": [], "anomalies": collections.Counter(),
        "read_errors": 0, "max_gap_ms": 0.0, "warned_empty": False,
    }

    def close_episode(ev_t):
        ep = state["episode"]
        if ep is None:
            return
        gap = ev_t - ep["start"]
        state["episode"] = None
        if gap <= grace:
            late = False
        elif gap <= 5.0:
            late = True
        else:
            state["pauses"] += 1
            return
        ctx = window_stats(buf, ep["start"] - 1.0, ev_t + 0.5)
        state["stalls"].append({"gap_ms": round(gap * 1000, 1), "late": late,
                                "ctx": ctx, "t": ep["start"]})
        state["max_gap_ms"] = max(state["max_gap_ms"], gap * 1000)

    try:
        while time.monotonic() < deadline and not stop.is_set():
            r, _, _ = select.select([fd], [], [], 0.05)
            now = time.monotonic()
            if not state["warned_empty"] and now > deadline - args.duration + 5 \
                    and state["total_events"] == 0:
                state["warned_empty"] = True
                print(f"\n[WARN] no events from {mouse['name']} after 5s -- this is probably NOT "
                      f"your real mouse. Ctrl-C, run with --list, and pick via --event N.\n")
            got_rel = False
            if r:
                try:
                    data = os.read(fd, EVENT_SIZE * 64)
                except BlockingIOError:
                    data = b""
                except OSError:
                    state["read_errors"] += 1
                    state["anomalies"]["device read error (USB reset/disconnect?)"] += 1
                    time.sleep(0.2)
                    continue
                for off in range(0, len(data) - EVENT_SIZE + 1, EVENT_SIZE):
                    _sec, _usec, typ, code, val = struct.unpack_from(EVENT_FORMAT, data, off)
                    state["total_events"] += 1
                    if typ == EV_REL:
                        got_rel = True
                        state["total_rel"] += 1
                        state["last_rel"] = now
                        state["recent_rel"].append(now)
                    elif typ == EV_KEY and code in BTN_NAMES:
                        if val == 1:                      # press
                            if code in state["press"]:
                                state["anomalies"][f"double-press {BTN_NAMES[code]}"] += 1
                            state["press"][code] = now
                        elif val == 0:                    # release
                            t0 = state["press"].pop(code, None)
                            if t0 is None:
                                state["anomalies"][f"release-without-press {BTN_NAMES[code]}"] += 1
                            else:
                                state["clicks"].append({"btn": BTN_NAMES[code],
                                                        "ms": round((now - t0) * 1000, 1)})
            if state["episode"] is not None and got_rel:
                close_episode(now)
            # open a stall episode only during real bursts of movement
            if (state["last_rel"] is not None and state["episode"] is None
                    and (now - state["last_rel"]) > thr):
                active = sum(1 for t in state["recent_rel"] if now - t < 0.2) >= 3
                if active:
                    state["episode"] = {"start": state["last_rel"]}
            if state["episode"] is not None and (now - state["episode"]["start"]) > 5.0:
                state["pauses"] += 1
                state["episode"] = None
    finally:
        os.close(fd)
        for code, t0 in state["press"].items():
            state["anomalies"][f"press-without-release {BTN_NAMES[code]}"] += 1
    state.pop("press", None)
    state.pop("episode", None)
    state.pop("recent_rel", None)
    return state


# ---------------------------------------------------------------- report
def collect_static(mouse):
    usb_dir = usb_device_dir(mouse) if mouse else None
    mouse_usb = None
    if usb_dir:
        mouse_usb = {"path": usb_dir,
                     "control": read_sys(os.path.join(usb_dir, "power/control")),
                     "delay_ms": read_sys(os.path.join(usb_dir, "power/autosuspend_delay_ms")),
                     "id": f"{read_sys(os.path.join(usb_dir, 'idVendor'))}:"
                           f"{read_sys(os.path.join(usb_dir, 'idProduct'))}"}
    g_auto, usb_rows = usb_power_scan()
    irq_rows = irq_table()
    journal, _ = journal_hits()
    dmesg = dmesg_hits()
    return {
        "kernel": platform.release(), "cpu": cpu_model(),
        "ncores": os.cpu_count(), "session": gui_session_info(),
        "governor": read_sys("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"),
        "mouse_usb": mouse_usb, "usb_global_autosuspend": g_auto,
        "usb_devices": usb_rows, "irq": irq_rows,
        "gpu_apps": gpu_compute_apps(),
        "journal": journal, "dmesg": dmesg,
        "xorg": xorg_log_summary(),
        "as_root": hasattr(os, "geteuid") and os.geteuid() == 0,
    }


def print_static(st, mouse):
    print("\n================ STATIC REPORT ================")
    print(f"kernel      : {st['kernel']}   cpu: {st['cpu']} ({st['ncores']} threads)")
    ses = st["session"]
    print(f"session     : {ses['desktop']}/{ses['type']} (user {ses['user']})" if ses
          else "session     : unknown (run with sudo to resolve)")
    print(f"cpu governor: {st['governor'] or 'n/a'}")
    mu = st["mouse_usb"]
    if mu:
        flag = "  <-- AUTOSUSPEND ON (prime suspect for lost input)" if mu["control"] == "auto" else ""
        print(f"mouse usb   : {mu['id']} power/control={mu['control']} delay={mu['delay_ms']}ms{flag}")
    print(f"usbcore.autosuspend default: {st['usb_global_autosuspend']} s (-1 = disabled)")
    auto = [d for d in st["usb_devices"] if d["control"] == "auto"]
    if auto:
        print(f"USB devices with autosuspend=auto: {len(auto)} "
              f"(e.g. {', '.join(d['dev'] for d in auto[:5])})")
    if st["gpu_apps"]:
        apps = "; ".join(f"pid {a['pid']} {a['name']} ({a['mib']} MiB)" for a in st["gpu_apps"])
        print(f"GPU compute apps: {apps}  <-- competes with desktop compositing")
    gpu_irqs = [r["irq"] for r in st["irq"] if "nvidia" in r["name"].lower()]
    usb_irqs = [r["irq"] for r in st["irq"] if re.search(r"xhci|ohci|ehci", r["name"])]
    shared = set(gpu_irqs) & set(usb_irqs)
    if shared:
        print(f"IRQ SHARING : GPU and USB controller share IRQ {sorted(shared)} <-- bad for latency")
    else:
        print(f"irqs        : usb={usb_irqs or '?'} gpu={gpu_irqs or '?'} (no sharing)"
              if usb_irqs or gpu_irqs else "irqs        : none matched")
    if st["xorg"]:
        print(f"Xorg log    : {st['xorg']['path']} -- {st['xorg']['ee_count']} (EE) errors")
    if st["dmesg"] and any("ftpm" in l.lower() for l in st["dmesg"]):
        print("fTPM        : stutter signatures found in dmesg <-- known AMD freeze cause")
    if not st["as_root"]:
        print("[note] not root: journal/dmesg/Xorg-log checks were skipped or limited; rerun with sudo.")


def verdict(st, res, args):
    v = []
    mu = st["mouse_usb"]
    if mu and mu["control"] == "auto":
        v.append(("HIGH", f"USB autosuspend is ON for your mouse ({mu['id']}). This drops/"
                          f"delays events. Fix: sudo sh -c 'echo on > {mu['path']}/power/control', "
                          f"or boot with usbcore.autosuspend=-1."))
    lost = sum(n for k, n in res["anomalies"].items()
               if "release-without-press" in k or "read error" in k)
    if lost or res["read_errors"]:
        v.append(("HIGH", f"Input events were lost below the window system "
                          f"({res['read_errors']} read errors). Check dmesg for USB resets; "
                          f"try another USB port (avoid hubs) and disable autosuspend."))
    stalls = [s for s in res["stalls"]]
    if stalls:
        gpu_max = max((s["ctx"].get("gpu_max", 0) for s in stalls), default=0)
        gpu_avg = [s["ctx"].get("gpu_avg", 0) for s in stalls if "gpu_avg" in s["ctx"]]
        gpu_avg = sum(gpu_avg) / len(gpu_avg) if gpu_avg else 0
        load_max = max((s["ctx"].get("load1_max", 0) for s in stalls), default=0)
        iow_max = max((s["ctx"].get("iowait_max", 0) for s in stalls), default=0)
        mhz = [s["ctx"]["mhz_max"] for s in stalls if "mhz_max" in s["ctx"]]
        mhz_min = min(mhz) if mhz else None
        if gpu_max >= 70:
            apps = "; ".join(f"pid {a['pid']} {a['name']}" for a in st["gpu_apps"]) or "a GPU process"
            v.append(("HIGH", f"GPU util hit {gpu_max:.0f}% (avg {gpu_avg:.0f}%) during freezes. "
                              f"{apps} is competing with the compositor. Pause it or cap its load; "
                              f"for Xorg also enable ForceFullCompositionPipeline in nvidia-settings."))
        if load_max >= 0.8 * (st["ncores"] or 1):
            v.append(("MEDIUM", f"System was CPU-saturated (load1 {load_max:.1f}) during freezes."))
        if iow_max >= 25:
            v.append(("MEDIUM", f"High iowait ({iow_max:.0f}%) during freezes -- storage stalls "
                               f"can freeze the desktop. SSD 50% full is fine; check nvme health."))
        if mhz_min and st["governor"] == "powersave":
            v.append(("MEDIUM", f"CPU governor is 'powersave' and frequency dipped to "
                               f"{mhz_min:.0f} MHz during freezes. Switch to schedutil/performance."))
    else:
        v.append(("INFO", "No stalls captured. Lower -t (e.g. -t 30), lengthen -d, and reproduce "
                          "the lag while moving the mouse continuously."))
    gpu_irqs = [r["irq"] for r in st["irq"] if "nvidia" in r["name"].lower()]
    usb_irqs = [r["irq"] for r in st["irq"] if re.search(r"xhci|ohci|ehci", r["name"])]
    if set(gpu_irqs) & set(usb_irqs):
        v.append(("MEDIUM", "GPU and USB controller share an IRQ; rebalance with /proc/irq/*/smp_affinity."))
    if st["dmesg"] and any("ftpm" in l.lower() for l in st["dmesg"]):
        v.append(("MEDIUM", "AMD fTPM stutter detected in dmesg. Fix: BIOS update, or "
                            "kernel parameter tpm_crb=off (if you don't use TPM)."))
    if st["journal"]:
        n = sum(1 for l in st["journal"] if re.search(r"nvidia|xorg", l, re.I))
        if n:
            v.append(("MEDIUM", f"{n} NVIDIA/Xorg warnings in journal this boot; check the static report."))
    if st["xorg"] and st["xorg"]["ee_count"] > 0:
        v.append(("LOW", f"Xorg log has {st['xorg']['ee_count']} (EE) errors -- see report tail."))
    if not v:
        v.append(("INFO", "Nothing conclusive captured. If evdev events look clean but clicks still "
                          "vanish inside apps, the loss is at compositor level (NVIDIA + GNOME Xorg): "
                          "test a Wayland session or enable ForceFullCompositionPipeline."))
    return v


def print_results(res, args):
    print("\n================ LIVE CAPTURE ================")
    print(f"events: {res['total_events']} total, {res['total_rel']} motion, "
          f"{len(res['clicks'])} clicks, max gap {res['max_gap_ms']:.0f} ms, "
          f"pauses(user stopped): {res['pauses']}")
    if res["clicks"]:
        avg = sum(c["ms"] for c in res["clicks"]) / len(res["clicks"])
        print(f"click press duration avg {avg:.0f} ms "
              f"(min {min(c['ms'] for c in res['clicks']):.0f}, "
              f"max {max(c['ms'] for c in res['clicks']):.0f})")
    for k, n in res["anomalies"].items():
        print(f"ANOMALY x{n}: {k}")
    print(f"stalls (> {args.threshold} ms during active movement): {len(res['stalls'])}")
    for s in sorted(res["stalls"], key=lambda x: -x["gap_ms"])[:10]:
        c = s["ctx"]
        print(f"  {s['gap_ms']:7.0f} ms  gpu={c.get('gpu_max', 0):5.1f}% "
              f"cpu={c.get('busy_max', 0):5.1f}% load1={c.get('load1_max', 0):5.2f} "
              f"mhz_max={c.get('mhz_max', 0):6.0f} iowait={c.get('iowait_max', 0):4.1f}%"
              f"{' (late)' if s['late'] else ''}")


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description="Diagnose mouse lag / lost clicks.")
    ap.add_argument("-d", "--duration", type=int, default=60, help="capture seconds (default 60)")
    ap.add_argument("-t", "--threshold", type=int, default=60, help="stall threshold ms (default 60)")
    ap.add_argument("-g", "--grace", type=int, default=1000, help="ms of silence before a gap counts "
                                                                  "as a pause, not a stall")
    ap.add_argument("--event", type=int, default=None, help="force /dev/input/eventN")
    ap.add_argument("--list", action="store_true", help="list pointer devices and exit")
    args = ap.parse_args()

    mice = discover_mice()
    if args.list:
        for i, m in enumerate(mice):
            print(f"[{i}] {m['event']:10s} {m['name']}")
        return
    if not mice:
        print("no mouse-like evdev devices found; here is what /proc/bus/input/devices contains:")
        dump_all_input_devices()
        sys.exit(1)
    if args.event is not None:
        mouse = next((m for m in mice if m["event"] == f"event{args.event}"), None)
        if not mouse:
            sys.exit(f"/dev/input/event{args.event} is not a mouse; use --list")
    else:
        ranked = rank_mice([m for m in mice if "touchpad" not in m["name"].lower()] or mice)
        mouse = ranked[0]
    if len(mice) > 1:
        print("pointer candidates:")
        for m in rank_mice(mice):
            mark = " <-- using" if m["event"] == mouse["event"] else ""
            print(f"  {m['event']:10s} {m['name']}{mark}")
        print("override with --event N if the wrong one is selected")

    if not (hasattr(os, "geteuid") and os.geteuid() == 0) and not os.access(
            f"/dev/input/{mouse['event']}", os.R_OK):
        sys.exit(f"cannot read /dev/input/{mouse['event']} -- run with sudo or add your user "
                 f"to the 'input' group")

    print(f"mouse-lag-diag: {mouse['name']} on /dev/input/{mouse['event']}, "
          f"{args.duration}s @ threshold {args.threshold}ms")
    st = collect_static(mouse)
    print_static(st, mouse)

    buf = collections.deque(maxlen=4000)
    stop = threading.Event()
    gpu_cache = {}
    gp = GpuPoller(gpu_cache, stop); gp.start()
    sm = Sampler(buf, stop, gpu_cache); sm.start()
    print(f"\ncapturing for {args.duration}s -- MOVE the mouse continuously and CLICK. "
          f"Reproduce the lag now...")
    res = {}
    try:
        res = monitor(mouse, args, buf, stop)
    except KeyboardInterrupt:
        stop.set()
    finally:
        stop.set()
    print_results(res, args)

    v = verdict(st, res, args)
    order = {"HIGH": 0, "MEDIUM": 1, "LOW": 2, "INFO": 3}
    print("\n================ MOST LIKELY CAUSES ================")
    for sev, text in sorted(v, key=lambda x: order[x[0]]):
        print(f"[{sev:6s}] {text}")

    out = {"config": vars(args), "mouse": mouse, "static": st, "result": res,
           "verdict": v, "samples": list(buf)}
    name = f"mouse-lag-diag-{time.strftime('%Y%m%d-%H%M%S')}.json"
    path = os.path.join(os.getcwd(), name)
    try:
        with open(path, "w") as f:
            json.dump(out, f, indent=1, default=str)
        print(f"\nfull data written to {path}")
    except OSError as e:
        print(f"\ncould not write JSON ({e})")


if __name__ == "__main__":
    main()

