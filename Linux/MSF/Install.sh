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

DISTRO_ID=$(. /etc/os-release && echo "$ID")
CODENAME=$(lsb_release -sc 2>/dev/null || (. /etc/os-release && echo "${VERSION_CODENAME:-}"))
ARCH=$(dpkg --print-architecture)

log "Detected: ${DISTRO_ID} ${CODENAME} (${ARCH})"

# ── 0. Purge any leftover artifacts from a previous (failed) run ──────────────
# CRITICAL: this must happen BEFORE the first `apt-get update`.
# A stale metasploit-framework.list with a bad codename (e.g. 'bookworm')
# causes apt to fail immediately, even before our codename probe runs.
section "Removing previous artifacts"
STALE_FILES=(
    /etc/apt/sources.list.d/metasploit-framework.list
    /etc/apt/preferences.d/metasploit-framework
    /usr/share/keyrings/metasploit-framework.gpg
)
for f in "${STALE_FILES[@]}"; do
    if [[ -e "$f" ]]; then
        rm -f "$f"
        log "Removed stale: $f"
    fi
done

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

log "Importing GPG key …"
curl -fsSL "${KEY_URL}" | gpg --dearmor -o "${KEYRING}" \
    || error "Failed to fetch Rapid7 GPG key. Check your internet connection."
chmod 644 "${KEYRING}"

# ── 3. Probe for a supported apt codename ────────────────────────────────────
# Rapid7 only publishes a fixed set of codenames — not every Debian/Ubuntu
# release is listed. We probe the repo with HTTP and use the first 200 we get.
# Order: native codename first, then known-good fallbacks newest→oldest.
SOURCES_FILE=/etc/apt/sources.list.d/metasploit-framework.list
PROBE_ORDER=( "${CODENAME}" jammy focal bullseye buster bionic xenial )

log "Probing Rapid7 repo (OS codename is '${CODENAME}') …"
REPO_CODENAME=""
for cn in "${PROBE_ORDER[@]}"; do
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
           "https://apt.metasploit.com/dists/${cn}/InRelease" 2>/dev/null || echo "000")
    if [[ "$HTTP" == "200" ]]; then
        REPO_CODENAME="${cn}"
        log "  ${cn} → ${HTTP}  ✓"
        break
    else
        warn "  ${cn} → ${HTTP}"
    fi
done

MSF_VIA_OMNIBUS=false

if [[ -z "$REPO_CODENAME" ]]; then
    # ── Fallback: official Rapid7 omnibus installer ───────────────────────────
    warn "No apt codename answered 200. Falling back to official omnibus installer."
    OMNIBUS_URL="https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb"
    curl -fsSL "${OMNIBUS_URL}" -o /tmp/msfinstall \
        || error "Could not reach apt.metasploit.com or GitHub. Verify network access."
    chmod +x /tmp/msfinstall
    /tmp/msfinstall
    MSF_VIA_OMNIBUS=true
else
    # ── apt path ──────────────────────────────────────────────────────────────
    log "Writing apt source with codename: ${REPO_CODENAME}"
    echo "deb [arch=${ARCH} signed-by=${KEYRING}] https://apt.metasploit.com/ ${REPO_CODENAME} main" \
        > "${SOURCES_FILE}"

    cat > /etc/apt/preferences.d/metasploit-framework <<'PINEOF'
Package: metasploit-framework
Pin: origin apt.metasploit.com
Pin-Priority: 990
PINEOF

    log "Repository configured at ${SOURCES_FILE}"

    # ── 4. Install via apt ────────────────────────────────────────────────────
    section "Installing Metasploit Framework"

    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y metasploit-framework \
        || error "apt-get install metasploit-framework failed — check output above."
fi

MSF_VERSION=$(msfconsole --version 2>/dev/null | head -1 || echo "unknown")
log "Installed: ${MSF_VERSION}"

# ── 5. PostgreSQL setup ───────────────────────────────────────────────────────
section "PostgreSQL"

start_pg() {
    if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null 2>&1; then
        systemctl enable postgresql --quiet 2>/dev/null || true
        systemctl start  postgresql 2>/dev/null || true
    fi
    if command -v service &>/dev/null; then
        service postgresql start 2>/dev/null || true
    fi
    # Direct pg_ctlcluster fallback for Docker / minimal containers
    if ! pg_isready -q 2>/dev/null; then
        PG_VER=$(pg_lsclusters -h 2>/dev/null | awk '{print $1; exit}' || true)
        [[ -n "$PG_VER" ]] && pg_ctlcluster "${PG_VER}" main start 2>/dev/null || true
    fi
}
start_pg
sleep 2

if pg_isready -q 2>/dev/null; then
    log "PostgreSQL is running."
else
    warn "PostgreSQL may not be running — msfdb init will attempt to start it."
fi

# ── 6. Initialise msfdb ───────────────────────────────────────────────────────
section "Metasploit database (msfdb)"

if msfdb status 2>/dev/null | grep -qi "connected"; then
    log "Database already initialised — skipping."
else
    log "Running msfdb init …"
    msfdb init 2>&1 | sed "s/^/    /"
fi

# ── 7. Verify ────────────────────────────────────────────────────────────────
section "Verification"

MSF_BIN=$(command -v msfconsole 2>/dev/null || true)
for p in /usr/bin/msfconsole /opt/metasploit-framework/bin/msfconsole; do
    [[ -x "$p" ]] && { MSF_BIN="$p"; break; }
done
[[ -z "$MSF_BIN" ]] && error "msfconsole not found on PATH after installation."

log "msfconsole binary : ${MSF_BIN}"
log "Version           : ${MSF_VERSION}"

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║   Metasploit Framework installed and ready               ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Launch interactive console :  ${BOLD}msfconsole${NC}"
echo -e "  Search for an exploit      :  ${BOLD}msfconsole -q -x 'search type:exploit platform:linux; exit'${NC}"
echo -e "  Database status            :  ${BOLD}msfdb status${NC}"
echo -e "  Update framework           :  ${BOLD}apt-get upgrade metasploit-framework${NC}"
echo ""
echo -e "  ${YELLOW}Use only on systems you own or have explicit permission to test.${NC}"
echo ""
