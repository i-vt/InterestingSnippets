#!/usr/bin/env bash
# =============================================================================
# Metasploit Framework Installer — Debian / Ubuntu
# Installs from the official Rapid7 apt repository, sets up PostgreSQL,
# and initialises msfdb so msfconsole is ready to use.
#
# Usage:  sudo bash install_msf.sh
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
section() { echo -e "\n${CYAN}${BOLD}──── $* ────${NC}"; }
error()   { echo -e "${RED}[-] ERROR:${NC} $*" >&2; exit 1; }

# ── Root guard ────────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Run with sudo or as root:  sudo bash $0"

# ── Detect Debian-family ─────────────────────────────────────────────────────
command -v apt-get &>/dev/null || error "apt-get not found — Debian/Ubuntu required."

# Grab distro info
DISTRO_ID=$(. /etc/os-release && echo "$ID")
CODENAME=$(lsb_release -sc 2>/dev/null || . /etc/os-release && echo "${VERSION_CODENAME:-}")
ARCH=$(dpkg --print-architecture)

log "Detected: ${DISTRO_ID} ${CODENAME} (${ARCH})"

# ── 1. System update & base deps ─────────────────────────────────────────────
section "System update & prerequisites"

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    curl wget gnupg2 lsb-release \
    apt-transport-https ca-certificates \
    software-properties-common \
    postgresql postgresql-contrib \
    libpq-dev \
    2>/dev/null

log "Prerequisites installed."

# ── 2. Rapid7 GPG key ────────────────────────────────────────────────────────
section "Rapid7 repository"

KEYRING=/usr/share/keyrings/metasploit-framework.gpg
KEY_URL=https://apt.metasploit.com/metasploit-framework.gpg.key

log "Importing GPG key from ${KEY_URL} …"
curl -fsSL "${KEY_URL}" | gpg --dearmor -o "${KEYRING}" \
    || error "Failed to fetch Rapid7 GPG key. Check your internet connection."
chmod 644 "${KEYRING}"

# ── 3. Apt source ────────────────────────────────────────────────────────────
SOURCES_FILE=/etc/apt/sources.list.d/metasploit-framework.list

# Rapid7 publishes a single 'apt.metasploit.com' repo (not split by codename).
echo "deb [arch=${ARCH} signed-by=${KEYRING}] https://apt.metasploit.com/ ${CODENAME} main" \
    > "${SOURCES_FILE}"

# Fallback line for distros whose codename Rapid7 doesn't carry (e.g. very new
# Ubuntu LTS).  We add a second line using a known-good alias.
if [[ "${CODENAME}" != "focal" && "${CODENAME}" != "jammy" && \
      "${CODENAME}" != "noble" && "${CODENAME}" != "bullseye" && \
      "${CODENAME}" != "bookworm" && "${CODENAME}" != "buster" ]]; then
    warn "Codename '${CODENAME}' may not be listed by Rapid7; adding 'focal' as fallback."
    echo "deb [arch=${ARCH} signed-by=${KEYRING}] https://apt.metasploit.com/ focal main" \
        >> "${SOURCES_FILE}"
fi

# Pin to prefer Rapid7's packages over any distro copies.
cat > /etc/apt/preferences.d/metasploit-framework <<'PINEOF'
Package: metasploit-framework
Pin: origin apt.metasploit.com
Pin-Priority: 990
PINEOF

log "Repository configured at ${SOURCES_FILE}"

# ── 4. Install Metasploit Framework ──────────────────────────────────────────
section "Installing Metasploit Framework"

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y metasploit-framework \
    || error "Installation failed. If the repository returned a 404, your \
distro codename may not be supported yet — edit ${SOURCES_FILE} to use 'jammy' \
or 'bookworm' manually and re-run."

MSF_VERSION=$(msfconsole --version 2>/dev/null | head -1 || echo "unknown")
log "Installed: ${MSF_VERSION}"

# ── 5. PostgreSQL setup ───────────────────────────────────────────────────────
section "PostgreSQL"

# Ensure PostgreSQL is running — handle both SysV and systemd.
start_pg() {
    if command -v systemctl &>/dev/null && systemctl is-enabled postgresql &>/dev/null 2>&1; then
        systemctl enable postgresql --quiet 2>/dev/null || true
        systemctl start  postgresql || true
    elif command -v service &>/dev/null; then
        service postgresql start || true
    fi
}
start_pg

# Wait a moment for PG to accept connections.
sleep 2

pg_running=false
if pg_isready -q 2>/dev/null; then
    pg_running=true
fi

if $pg_running; then
    log "PostgreSQL is running."
else
    warn "PostgreSQL may not be running — msfdb init will attempt to start it."
fi

# ── 6. Initialise msfdb ───────────────────────────────────────────────────────
section "Metasploit database (msfdb)"

if msfdb status 2>/dev/null | grep -qi "connected"; then
    log "Database already initialised."
else
    log "Running msfdb init …"
    msfdb init 2>&1 | sed "s/^/    /"
fi

# ── 7. Verify ────────────────────────────────────────────────────────────────
section "Verification"

MSF_PATHS=( /usr/bin/msfconsole /opt/metasploit-framework/bin/msfconsole )
MSF_BIN=""
for p in "${MSF_PATHS[@]}"; do
    [[ -x "$p" ]] && { MSF_BIN="$p"; break; }
done
[[ -z "$MSF_BIN" ]] && MSF_BIN=$(command -v msfconsole 2>/dev/null || true)
[[ -z "$MSF_BIN" ]] && error "msfconsole not found on PATH after installation."

log "msfconsole binary : ${MSF_BIN}"
log "Version           : ${MSF_VERSION}"

MODULES=$("${MSF_BIN}" -q -x 'exit' 2>/dev/null | grep -oP '\d+ modules' | head -1 || true)
[[ -n "$MODULES" ]] && log "Loaded modules     : ${MODULES}"

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║   Metasploit Framework installed and ready               ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Start an interactive session :  ${BOLD}msfconsole${NC}"
echo -e "  Quick module search          :  ${BOLD}msfconsole -q -x 'search type:exploit platform:linux; exit'${NC}"
echo -e "  Database status              :  ${BOLD}msfdb status${NC}"
echo -e "  Update framework             :  ${BOLD}apt-get upgrade metasploit-framework${NC}"
echo ""
echo -e "  ${YELLOW}Use only on systems you own or have explicit permission to test.${NC}"
echo ""
