#!/usr/bin/env bash
# =============================================================================
# docker-clean.sh — Docker cache & resource cleanup utility
# Usage: ./docker-clean.sh [OPTIONS]
# =============================================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Defaults ──────────────────────────────────────────────────────────────────
OPT_ALL=false
OPT_IMAGES=false
OPT_CONTAINERS=false
OPT_VOLUMES=false
OPT_NETWORKS=false
OPT_BUILD_CACHE=false
OPT_FORCE=false
OPT_DRY_RUN=false
OPT_STATS=false

# ── Helpers ───────────────────────────────────────────────────────────────────
log_info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_section() { echo -e "\n${BOLD}${CYAN}── $* ──────────────────────────────────────────${RESET}"; }

usage() {
  cat <<EOF

${BOLD}Usage:${RESET} $(basename "$0") [OPTIONS]

${BOLD}Options:${RESET}
  -a, --all           Remove everything (images, containers, volumes,
                      networks, build cache) — full nuclear cleanup
  -i, --images        Remove all unused images
  -c, --containers    Remove all stopped containers
  -v, --volumes       Remove all unused volumes  ⚠ data loss risk
  -n, --networks      Remove all unused networks
  -b, --build-cache   Remove all build cache
  -s, --stats         Show disk usage stats and exit (no cleanup)
  -f, --force         Skip confirmation prompts
  -d, --dry-run       Show what would be removed without removing it
  -h, --help          Show this help message

${BOLD}Examples:${RESET}
  $(basename "$0") --stats                  # See what's taking space
  $(basename "$0") --all --dry-run          # Preview full cleanup
  $(basename "$0") --all --force            # Full cleanup, no prompts
  $(basename "$0") --images --containers    # Clean images + containers only
  $(basename "$0") --build-cache            # Clean only build cache

EOF
}

confirm() {
  local msg="$1"
  if [[ "$OPT_FORCE" == true ]]; then
    return 0
  fi
  echo -e "${YELLOW}[?]${RESET} $msg ${BOLD}(y/N)${RESET} "
  read -r -n1 answer
  echo
  [[ "$answer" =~ ^[Yy]$ ]]
}

check_docker() {
  if ! command -v docker &>/dev/null; then
    log_error "Docker is not installed or not in PATH."
    exit 1
  fi
  if ! docker info &>/dev/null; then
    log_error "Docker daemon is not running. Start it with: sudo systemctl start docker"
    exit 1
  fi
}

show_stats() {
  log_section "Docker Disk Usage"
  docker system df
}

# ── Cleanup functions ─────────────────────────────────────────────────────────

clean_containers() {
  log_section "Stopped Containers"
  local count
  count=$(docker ps -aq --filter status=exited --filter status=created | wc -l)
  if [[ "$count" -eq 0 ]]; then
    log_info "No stopped containers found."
    return
  fi
  log_info "Found ${count} stopped container(s)."
  if [[ "$OPT_DRY_RUN" == true ]]; then
    log_warn "[DRY-RUN] Would remove ${count} stopped container(s):"
    docker ps -a --filter status=exited --filter status=created \
      --format "  • {{.Names}} ({{.ID}}) — {{.Status}}"
    return
  fi
  if confirm "Remove ${count} stopped container(s)?"; then
    docker container prune -f
    log_ok "Stopped containers removed."
  else
    log_info "Skipped containers."
  fi
}

clean_images() {
  log_section "Unused Images"
  local count
  count=$(docker images -q --filter dangling=false | wc -l)
  if [[ "$count" -eq 0 ]]; then
    log_info "No unused images found."
    return
  fi
  log_info "Found images to evaluate."
  if [[ "$OPT_DRY_RUN" == true ]]; then
    log_warn "[DRY-RUN] Would remove unused images:"
    docker images --filter dangling=false --format "  • {{.Repository}}:{{.Tag}} ({{.ID}}) — {{.Size}}"
    return
  fi
  if confirm "Remove all unused images (not used by any container)?"; then
    docker image prune -af
    log_ok "Unused images removed."
  else
    log_info "Skipped images."
  fi
}

clean_volumes() {
  log_section "Unused Volumes"
  local count
  count=$(docker volume ls -q --filter dangling=true | wc -l)
  if [[ "$count" -eq 0 ]]; then
    log_info "No unused volumes found."
    return
  fi
  log_warn "Found ${count} unused volume(s). This may contain persistent data!"
  if [[ "$OPT_DRY_RUN" == true ]]; then
    log_warn "[DRY-RUN] Would remove ${count} unused volume(s):"
    docker volume ls --filter dangling=true --format "  • {{.Name}} ({{.Driver}})"
    return
  fi
  if confirm "⚠  Remove ${count} unused volume(s)? DATA WILL BE LOST"; then
    docker volume prune -f
    log_ok "Unused volumes removed."
  else
    log_info "Skipped volumes."
  fi
}

clean_networks() {
  log_section "Unused Networks"
  if [[ "$OPT_DRY_RUN" == true ]]; then
    log_warn "[DRY-RUN] Would remove unused custom networks (bridge/host/none kept)."
    docker network ls --filter type=custom --format "  • {{.Name}} ({{.Driver}})"
    return
  fi
  if confirm "Remove unused custom networks?"; then
    docker network prune -f
    log_ok "Unused networks removed."
  else
    log_info "Skipped networks."
  fi
}

clean_build_cache() {
  log_section "Build Cache"
  local size
  size=$(docker system df --format "{{.BuildCacheSize}}" 2>/dev/null || echo "unknown")
  log_info "Build cache size: ${size}"
  if [[ "$OPT_DRY_RUN" == true ]]; then
    log_warn "[DRY-RUN] Would remove all build cache (${size})."
    return
  fi
  if confirm "Remove all build cache (${size})?"; then
    docker builder prune -af
    log_ok "Build cache cleared."
  else
    log_info "Skipped build cache."
  fi
}

clean_all() {
  log_section "Full System Prune"
  if [[ "$OPT_DRY_RUN" == true ]]; then
    log_warn "[DRY-RUN] Would run: docker system prune -a --volumes"
    echo
    docker system df
    return
  fi
  log_warn "This will remove ALL unused containers, images, volumes, networks, and build cache."
  if confirm "Proceed with FULL cleanup?"; then
    docker system prune -af --volumes
    log_ok "Full Docker cleanup complete."
  else
    log_info "Full cleanup cancelled."
  fi
}

# ── Argument parsing ──────────────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
  usage
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--all)           OPT_ALL=true ;;
    -i|--images)        OPT_IMAGES=true ;;
    -c|--containers)    OPT_CONTAINERS=true ;;
    -v|--volumes)       OPT_VOLUMES=true ;;
    -n|--networks)      OPT_NETWORKS=true ;;
    -b|--build-cache)   OPT_BUILD_CACHE=true ;;
    -s|--stats)         OPT_STATS=true ;;
    -f|--force)         OPT_FORCE=true ;;
    -d|--dry-run)       OPT_DRY_RUN=true ;;
    -h|--help)          usage; exit 0 ;;
    *)
      log_error "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

# ── Main ──────────────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
echo "  ██████╗  ██████╗  ██████╗██╗  ██╗███████╗██████╗"
echo "  ██╔══██╗██╔═══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗"
echo "  ██║  ██║██║   ██║██║     █████╔╝ █████╗  ██████╔╝"
echo "  ██║  ██║██║   ██║██║     ██╔═██╗ ██╔══╝  ██╔══██╗"
echo "  ██████╔╝╚██████╔╝╚██████╗██║  ██╗███████╗██║  ██║"
echo "  ╚═════╝  ╚═════╝  ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝"
echo "  CLEAN                                        v1.0.0"
echo -e "${RESET}"

check_docker

[[ "$OPT_DRY_RUN" == true ]] && log_warn "DRY-RUN mode — nothing will be deleted.\n"

# Stats-only mode
if [[ "$OPT_STATS" == true ]]; then
  show_stats
  exit 0
fi

# Show stats before cleanup
show_stats

# Run selected cleanup actions
if [[ "$OPT_ALL" == true ]]; then
  clean_all
else
  [[ "$OPT_CONTAINERS" == true ]]  && clean_containers
  [[ "$OPT_IMAGES" == true ]]      && clean_images
  [[ "$OPT_VOLUMES" == true ]]     && clean_volumes
  [[ "$OPT_NETWORKS" == true ]]    && clean_networks
  [[ "$OPT_BUILD_CACHE" == true ]] && clean_build_cache
fi

# Show stats after cleanup (skip if dry-run or stats-only)
if [[ "$OPT_DRY_RUN" == false ]]; then
  log_section "Disk Usage After Cleanup"
  docker system df
fi

echo -e "\n${GREEN}${BOLD}Done!${RESET}"
