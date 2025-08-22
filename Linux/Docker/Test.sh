#!/usr/bin/env bash
# test-docker.sh — sanity checks for a fresh Docker install on Debian
set -euo pipefail

RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; NC=$'\e[0m'
pass(){ echo "${GRN}✔${NC} $*"; }
fail(){ echo "${RED}✘${NC} $*"; }
info(){ echo "${YLW}➜${NC} $*"; }

require_cmd() {
  if ! command -v "$1" &>/dev/null; then
    fail "Command '$1' not found."
    exit 1
  fi
}

# 0) Basic presence
info "Checking docker CLI availability…"
require_cmd docker
pass "docker CLI present"

# 1) Daemon health
info "Checking Docker daemon status…"
if systemctl is-active --quiet docker 2>/dev/null; then
  pass "systemd reports docker is active"
else
  # fallback for non-systemd or containers
  if docker info &>/dev/null; then
    pass "docker daemon reachable (non-systemd environment)"
  else
    fail "docker daemon not active or unreachable"
    systemctl status docker || true
    exit 1
  fi
fi

# 2) Versions
info "Collecting versions…"
docker --version || true
docker info --format 'Server: {{.ServerVersion}}  OS: {{.OperatingSystem}}  CgroupDriver: {{.CgroupDriver}}' || true
if docker buildx version &>/dev/null; then
  pass "Buildx plugin detected: $(docker buildx version | head -n1)"
else
  fail "Buildx plugin not found"
fi
if docker compose version &>/dev/null; then
  pass "Compose v2 plugin detected: $(docker compose version | head -n1)"
else
  fail "Compose v2 plugin not found (try installing docker-compose-plugin)"
fi

# 3) Run hello-world
info "Running hello-world image…"
docker run --rm hello-world >/dev/null
pass "hello-world ran successfully"

# 4) Pull and run alpine command
info "Pulling and running alpine to execute a command…"
OUT="$(docker run --rm alpine sh -c 'echo container-ok')"
if [[ "$OUT" == "container-ok" ]]; then
  pass "Alpine container executed command"
else
  fail "Alpine command output mismatch"
  exit 1
fi

# 5) Volume test
info "Testing volumes…"
VOL="testvol-$$"
docker volume create "$VOL" >/dev/null
docker run --rm -v "$VOL":/data alpine sh -c 'echo persisted > /data/file.txt'
CHK="$(docker run --rm -v "$VOL":/data alpine cat /data/file.txt || true)"
docker volume rm "$VOL" >/dev/null
if [[ "$CHK" == "persisted" ]]; then
  pass "Volume read/write works"
else
  fail "Volume test failed"
  exit 1
fi

# 6) Simple networking (DNS + outbound) implicitly verified by pulls above

# 7) Quick Compose up/down sanity check (no ports)
TMPDIR="$(mktemp -d)"
trap 'docker compose -f "$TMPDIR/docker-compose.yml" down -v &>/dev/null || true; rm -rf "$TMPDIR"' EXIT
cat > "$TMPDIR/docker-compose.yml" <<'YML'
services:
  echoer:
    image: alpine
    command: ["sh","-c","echo compose-ok && sleep 2"]
YML

if docker compose -f "$TMPDIR/docker-compose.yml" up --abort-on-container-exit --quiet-pull; then
  pass "docker compose up/down works"
else
  fail "docker compose run failed"
  exit 1
fi
docker compose -f "$TMPDIR/docker-compose.yml" down -v >/dev/null 2>&1 || true

# 8) Group membership hint
if [[ "${SUDO_USER:-$USER}" != "root" ]]; then
  # Check if the invoking user can talk to the daemon without sudo
  if sudo -n -u "${SUDO_USER:-$USER}" bash -c "docker info" &>/dev/null; then
    pass "User ${SUDO_USER:-$USER} can use docker without sudo"
  else
    info "User ${SUDO_USER:-$USER} may need to log out/in for docker group to apply"
  fi
fi

echo
pass "All Docker tests passed ✅"
