#!/bin/bash

# NVIDIA Driver Diagnostic Script
# Run as root or with sudo: sudo ./diagnose_nvidia.sh

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; }
info() { echo -e "  ${CYAN}[INFO]${NC} $1"; }
header() { echo -e "\n${YELLOW}=== $1 ===${NC}"; }

ISSUES=0

# 1. HARDWARE DETECTION
header "1. GPU Hardware Detection"
if lspci -nn | grep -iE 'VGA|3D' | grep -i nvidia; then
    GPU_ID=$(lspci -nn | grep -i nvidia | grep -oiE '\[10de:[0-9a-f]{4}\]' | head -1)
    info "PCI ID: $GPU_ID"
else
    fail "No NVIDIA GPU detected by lspci."
    ((ISSUES++))
fi

# 2. INSTALLED PACKAGES
header "2. Driver Package Status"
if dpkg -l nvidia-driver 2>/dev/null | grep -q '^ii'; then
    DRV_VER=$(dpkg-query -W -f='${Version}' nvidia-driver 2>/dev/null)
    pass "nvidia-driver installed (version: $DRV_VER)"
else
    fail "nvidia-driver package is NOT installed."
    ((ISSUES++))
fi

for pkg in linux-headers-amd64 firmware-misc-nonfree; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
        pass "$pkg installed"
    else
        fail "$pkg NOT installed."
        ((ISSUES++))
    fi
done

# 3. KERNEL HEADERS vs RUNNING KERNEL
header "3. Kernel Headers Match"
RUNNING=$(uname -r)
info "Running kernel: $RUNNING"
if [ -d "/usr/src/linux-headers-$RUNNING" ]; then
    pass "Headers exist for running kernel."
else
    fail "No headers for $RUNNING — DKMS cannot build the module."
    echo "       Fix: apt install linux-headers-$RUNNING  (or boot the newest installed kernel)"
    ((ISSUES++))
fi

# 4. DKMS MODULE BUILD STATUS
header "4. DKMS Build Status"
if command -v dkms &>/dev/null; then
    dkms status | grep -i nvidia || warn "No NVIDIA module registered in DKMS."
    if dkms status | grep -i nvidia | grep -q installed; then
        pass "NVIDIA kernel module built via DKMS."
    else
        fail "NVIDIA module not built/installed for current kernel."
        echo "       Fix: dkms autoinstall  (then check /var/lib/dkms/nvidia-current/*/build/make.log)"
        ((ISSUES++))
    fi
else
    fail "dkms not installed."
    ((ISSUES++))
fi

# 5. KERNEL MODULE LOADED?
header "5. Kernel Module Status"
if lsmod | grep -q nvidia; then
    pass "nvidia module is loaded:"
    lsmod | grep nvidia
else
    fail "nvidia module is NOT loaded."
    info "Attempting manual load..."
    if modprobe nvidia 2>&1; then
        pass "Module loaded successfully on retry."
    else
        fail "modprobe nvidia failed:"
        modprobe nvidia 2>&1 | sed 's/^/       /'
        ((ISSUES++))
    fi
fi

# 6. SECURE BOOT CHECK (very common cause)
header "6. Secure Boot / Module Signing"
if command -v mokutil &>/dev/null; then
    SB=$(mokutil --sb-state 2>/dev/null)
    info "$SB"
    if echo "$SB" | grep -qi "enabled"; then
        fail "Secure Boot is ENABLED — unsigned NVIDIA modules will be blocked."
        echo "       Fix: enroll a MOK for DKMS, or disable Secure Boot in BIOS/UEFI."
        ((ISSUES++))
    else
        pass "Secure Boot disabled — not blocking the module."
    fi
else
    warn "mokutil not available; check Secure Boot state in BIOS."
fi
dmesg 2>/dev/null | grep -iE "secureboot|module verification failed" | tail -3 | sed 's/^/       /'

# 7. NOUVEAU CONFLICT
header "7. Nouveau Driver Conflict"
if lsmod | grep -q nouveau; then
    fail "nouveau is loaded and conflicts with nvidia."
    echo "       Fix: ensure /etc/modprobe.d/nvidia-blacklists-nouveau.conf exists, then"
    echo "            update-initramfs -u && reboot"
    ((ISSUES++))
else
    pass "nouveau not loaded."
fi
if grep -rqs "blacklist nouveau" /etc/modprobe.d/; then
    pass "nouveau is blacklisted in modprobe.d."
else
    warn "No nouveau blacklist found in /etc/modprobe.d/."
fi

# 8. XORG / WAYLAND CONFIG
header "8. Display Configuration"
if [ -f /etc/X11/xorg.conf ]; then
    warn "/etc/X11/xorg.conf exists — may force wrong driver."
    grep -i "driver" /etc/X11/xorg.conf | sed 's/^/       /'
fi
info "Session type: ${XDG_SESSION_TYPE:-unknown (not in a graphical session)}"

# 9. ERROR LOGS
header "9. Recent Driver Errors (dmesg / journal)"
dmesg 2>/dev/null | grep -iE "nvidia|nvrm" | tail -10 | sed 's/^/  /'
journalctl -k -b --no-pager 2>/dev/null | grep -iE "nvidia|nvrm" | tail -10 | sed 's/^/  /'

# 10. APT / REPO SANITY
header "10. Repository Configuration"
if apt-cache policy nvidia-driver 2>/dev/null | grep -q "Candidate: [0-9]"; then
    pass "nvidia-driver available from configured repos:"
    apt-cache policy nvidia-driver | sed 's/^/       /'
else
    fail "nvidia-driver not available — check contrib/non-free components in sources."
    ((ISSUES++))
fi

# SUMMARY
header "SUMMARY"
if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}No blocking issues found. If you haven't rebooted since install, reboot now.${NC}"
else
    echo -e "${RED}$ISSUES issue(s) found — see the FAIL items and their suggested fixes above.${NC}"
fi
