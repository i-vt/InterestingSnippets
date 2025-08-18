#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------
# PostgreSQL data directory migration script
# Debian/Ubuntu clusters (pg_lsclusters, systemd).
# ---------------------------------------------

# Script metadata
readonly SCRIPT_VERSION="2.0"
readonly SCRIPT_NAME="$(basename "$0")"

# Defaults (auto-detected if possible)
PG_VER=""
PG_CLUSTER=""
NEW_DATA_DIR=""
CLEANUP_OLD="false"
DRY_RUN="false"
VERIFY_CONNECTIONS="true"
BACKUP_CONFIG="true"

# Logging
readonly LOG_FILE="/tmp/pg-migration-$(date +%Y%m%d-%H%M%S).log"

log() {
  local level="$1"
  shift
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

info() { log "INFO" "$@"; }
warn() { log "WARN" "$@"; }
error() { log "ERROR" "$@"; }

usage() {
  cat <<EOF
PostgreSQL Data Directory Migration Tool v${SCRIPT_VERSION}

Usage:
  $SCRIPT_NAME --new-dir /path/to/new/pgdata [options]

Required:
  --new-dir PATH      Target data directory on the new disk (must be a dedicated directory)

Optional:
  --version N         PostgreSQL major version (e.g., 14, 15, 16, 17). Auto-detects if omitted
  --cluster NAME      Cluster name (default 'main'). Auto-detects when possible
  --cleanup-old       After successful migration, remove contents of old data dir
  --no-verify         Skip connection verification after migration
  --no-backup         Skip backing up configuration files
  --dry-run           Show what would be done without making changes
  -h, --help          Show this help

Notes:
  - Must run as root/sudo
  - Service unit format: postgresql@<version>-<cluster>
  - New filesystem must support UNIX permissions (ext4/xfs/btrfs recommended)
  - Migration log: $LOG_FILE

Examples:
  $SCRIPT_NAME --new-dir /mnt/ssd/postgresql/data
  $SCRIPT_NAME --new-dir /data/pg --version 15 --cluster main --cleanup-old
EOF
}

# Enhanced argument parsing
parse_args() {
  while (( $# )); do
    case "$1" in
      --new-dir) 
        NEW_DATA_DIR="${2:?--new-dir requires a path}"
        shift 2
        ;;
      --version) 
        PG_VER="${2:?--version requires a version number}"
        if ! [[ "$PG_VER" =~ ^[0-9]+$ ]]; then
          error "Invalid version format: $PG_VER (expected: numeric)"
          exit 1
        fi
        shift 2
        ;;
      --cluster) 
        PG_CLUSTER="${2:?--cluster requires a cluster name}"
        shift 2
        ;;
      --cleanup-old) 
        CLEANUP_OLD="true"
        shift
        ;;
      --no-verify)
        VERIFY_CONNECTIONS="false"
        shift
        ;;
      --no-backup)
        BACKUP_CONFIG="false"
        shift
        ;;
      --dry-run) 
        DRY_RUN="true"
        shift
        ;;
      -h|--help) 
        usage
        exit 0
        ;;
      -*) 
        error "Unknown option: $1"
        usage
        exit 1
        ;;
      *) 
        error "Unexpected argument: $1"
        usage
        exit 1
        ;;
    esac
  done
}

# Enhanced privilege check
require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    error "This script requires root privileges. Run with sudo."
    exit 1
  fi
}

# Check command availability
have() { command -v "$1" >/dev/null 2>&1; }

# Enhanced dependency checking
ensure_commands() {
  local required=(pg_lsclusters systemctl rsync sed awk grep sudo)
  local optional=(setfacl getfacl)
  local missing=()
  
  for cmd in "${required[@]}"; do
    if ! have "$cmd"; then
      missing+=("$cmd")
    fi
  done
  
  if [[ ${#missing[@]} -gt 0 ]]; then
    error "Missing required commands: ${missing[*]}"
    error "On Debian/Ubuntu: apt-get install postgresql-common rsync"
    exit 1
  fi
  
  # Check optional commands
  for cmd in "${optional[@]}"; do
    if ! have "$cmd"; then
      warn "Optional command '$cmd' not found (ACL support will be limited)"
    fi
  done
}

# Enhanced cluster detection with better error handling
detect_cluster() {
  if [[ -n "$PG_VER" && -n "$PG_CLUSTER" ]]; then
    info "Using specified cluster: ${PG_VER}/${PG_CLUSTER}"
    return
  fi

  info "Auto-detecting PostgreSQL clusters..."
  
  local clusters_output
  if ! clusters_output="$(pg_lsclusters 2>/dev/null)"; then
    error "Failed to run pg_lsclusters. Is PostgreSQL installed?"
    exit 1
  fi

  # Parse clusters (skip header line)
  local cluster_lines
  cluster_lines="$(echo "$clusters_output" | awk 'NR>1 && NF>=3 {print $1, $2, $3}' | grep -v '^[[:space:]]*$' || true)"
  
  if [[ -z "$cluster_lines" ]]; then
    error "No PostgreSQL clusters found"
    error "Install PostgreSQL or specify --version and --cluster manually"
    exit 1
  fi

  local cluster_count
  cluster_count="$(echo "$cluster_lines" | wc -l)"
  
  if [[ "$cluster_count" -gt 1 ]]; then
    error "Multiple clusters detected. Please specify --version and --cluster:"
    echo "$cluster_lines" | while read -r ver name status; do
      error "  --version $ver --cluster $name (status: $status)"
    done
    exit 1
  fi

  # Extract version and cluster name
  read -r PG_VER PG_CLUSTER status <<< "$cluster_lines"
  info "Auto-detected cluster: ${PG_VER}/${PG_CLUSTER} (status: ${status})"
  
  if [[ "$status" != "online" ]]; then
    warn "Cluster status is '$status', not 'online'. Proceeding anyway."
  fi
}

# Get data directory from pg_lsclusters output
get_data_directory() {
  local data_dir
  data_dir="$(pg_lsclusters | awk -v v="$PG_VER" -v c="$PG_CLUSTER" '
    NR>1 && $1==v && $2==c { 
      for (i=4; i<=NF-1; i++) { 
        if ($i ~ /^\//) { 
          print $i; 
          exit 
        } 
      } 
    }')"
  
  if [[ -z "$data_dir" ]]; then
    error "Could not determine data directory for cluster ${PG_VER}/${PG_CLUSTER}"
    exit 1
  fi
  
  echo "$data_dir"
}

# Get log file path
get_log_path() {
  pg_lsclusters | awk -v v="$PG_VER" -v c="$PG_CLUSTER" '
    NR>1 && $1==v && $2==c { print $NF }'
}

get_config_directory() {
  echo "/etc/postgresql/${PG_VER}/${PG_CLUSTER}"
}

get_service_unit() {
  echo "postgresql@${PG_VER}-${PG_CLUSTER}.service"
}

# Enhanced directory validation and setup
setup_target_directory() {
  local target="$1"
  
  # Validate path
  if [[ ! "$target" =~ ^/[^[:space:]]*$ ]]; then
    error "Invalid target directory path: '$target'"
    exit 1
  fi

  # Check if it's a mount point (recommended for large datasets)
  if mountpoint -q "$target" 2>/dev/null; then
    info "Target directory is a mount point: $target"
  elif [[ -d "$target" ]]; then
    warn "Target directory exists but is not a mount point"
    warn "Consider mounting dedicated storage at this location"
  fi

  # Create directory if it doesn't exist
  if [[ ! -d "$target" ]]; then
    info "Creating target directory: $target"
    run_cmd mkdir -p "$target"
  else
    # Check if directory is empty
    if [[ -n "$(find "$target" -maxdepth 1 -type f -o -type d ! -path "$target" 2>/dev/null | head -1)" ]]; then
      warn "Target directory '$target' is not empty"
      if [[ "$DRY_RUN" != "true" ]]; then
        read -r -p "Continue anyway? This may overwrite existing data [y/N]: " response
        [[ "${response,,}" == "y" ]] || exit 1
      fi
    fi
  fi

  # Set ownership and permissions
  run_cmd chown postgres:postgres "$target"
  run_cmd chmod 700 "$target"
  
  # Check disk space
  check_disk_space "$target"
}

# Check available disk space
check_disk_space() {
  local target="$1"
  local old_data_dir="$2"
  
  if [[ -z "$old_data_dir" ]]; then
    warn "Cannot check disk space: old data directory unknown"
    return
  fi

  local old_size new_avail
  old_size="$(du -sb "$old_data_dir" 2>/dev/null | awk '{print $1}' || echo "0")"
  new_avail="$(df -B1 "$target" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")"
  
  if [[ "$old_size" -gt 0 && "$new_avail" -gt 0 ]]; then
    local old_gb new_gb
    old_gb="$((old_size / 1024 / 1024 / 1024))"
    new_gb="$((new_avail / 1024 / 1024 / 1024))"
    
    info "Data size: ${old_gb}GB, Available space: ${new_gb}GB"
    
    if [[ "$old_size" -gt "$new_avail" ]]; then
      error "Insufficient disk space on target filesystem"
      error "Required: ${old_gb}GB, Available: ${new_gb}GB"
      exit 1
    fi
    
    # Warn if less than 20% free space after migration
    local remaining=$((new_avail - old_size))
    if [[ "$remaining" -lt $((new_avail / 5)) ]]; then
      warn "Low disk space warning: less than 20% will remain after migration"
    fi
  fi
}

# Enhanced directory traversal permissions
setup_parent_permissions() {
  local target="$1"
  local path=""
  
  info "Setting up parent directory permissions for: $target"
  
  # Split path and process each component
  IFS='/' read -ra path_parts <<< "$target"
  for part in "${path_parts[@]}"; do
    [[ -z "$part" ]] && continue
    path="$path/$part"
    
    # Try ACL first (more precise), fallback to chmod
    if have setfacl && have getfacl; then
      if run_cmd setfacl -m u:postgres:--x "$path" 2>/dev/null; then
        info "Set ACL for postgres on: $path"
      else
        warn "ACL failed, using chmod for: $path"
        run_cmd chmod o+x "$path"
      fi
    else
      run_cmd chmod o+x "$path"
    fi
  done
}

# Backup configuration files
backup_configurations() {
  [[ "$BACKUP_CONFIG" != "true" ]] && return
  
  local config_dir backup_dir
  config_dir="$(get_config_directory)"
  backup_dir="${config_dir}.backup.$(date +%Y%m%d-%H%M%S)"
  
  info "Backing up configuration to: $backup_dir"
  run_cmd cp -r "$config_dir" "$backup_dir"
}

# Update postgresql.conf with new data directory
update_config() {
  local config_dir config_file
  config_dir="$(get_config_directory)"
  config_file="${config_dir}/postgresql.conf"
  
  if [[ ! -f "$config_file" ]]; then
    error "PostgreSQL configuration file not found: $config_file"
    exit 1
  fi

  info "Updating postgresql.conf with new data directory"
  
  # Create backup before modification
  run_cmd cp "$config_file" "${config_file}.bak.$(date +%Y%m%d-%H%M%S)"
  
  # Update or add data_directory setting
  local escaped_path="${NEW_DATA_DIR//\//\\/}"
  if grep -qE '^\s*data_directory\s*=' "$config_file"; then
    run_cmd sed -i "s|^\s*data_directory\s*=.*|data_directory = '${NEW_DATA_DIR}'|" "$config_file"
  else
    echo "data_directory = '${NEW_DATA_DIR}'" | run_cmd tee -a "$config_file" >/dev/null
  fi
}

# Verify PostgreSQL connections work
verify_connectivity() {
  [[ "$VERIFY_CONNECTIONS" != "true" ]] && return
  
  info "Verifying PostgreSQL connectivity..."
  
  local max_attempts=30
  local attempt=1
  
  while [[ $attempt -le $max_attempts ]]; do
    if run_cmd sudo -u postgres psql -c "SELECT version();" >/dev/null 2>&1; then
      info "Connection test successful"
      
      # Show current data directory
      local current_data_dir
      current_data_dir="$(run_cmd sudo -u postgres psql -Atqc "SHOW data_directory;" 2>/dev/null || echo "unknown")"
      info "Current data_directory: $current_data_dir"
      
      if [[ "$current_data_dir" == "$NEW_DATA_DIR" ]]; then
        info "✅ Data directory successfully updated"
      else
        warn "Data directory mismatch - expected: $NEW_DATA_DIR, got: $current_data_dir"
      fi
      return 0
    fi
    
    warn "Connection attempt $attempt/$max_attempts failed, retrying in 2s..."
    sleep 2
    ((attempt++))
  done
  
  error "Failed to establish connection after $max_attempts attempts"
  return 1
}

# Enhanced command execution with better logging
run_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY-RUN] $*"
    return 0
  else
    info "Executing: $*"
    if "$@" 2>&1 | tee -a "$LOG_FILE"; then
      return 0
    else
      local exit_code=$?
      error "Command failed with exit code $exit_code: $*"
      return $exit_code
    fi
  fi
}

# Enhanced cleanup with safety checks
cleanup_old_data() {
  [[ "$CLEANUP_OLD" != "true" ]] && return
  
  local old_dir="$1"
  
  # Safety checks
  if [[ -z "$old_dir" || "$old_dir" == "/" || ${#old_dir} -lt 10 ]]; then
    error "Refusing to clean up suspicious path: '$old_dir'"
    return 1
  fi
  
  if [[ ! -d "$old_dir" ]]; then
    warn "Old data directory no longer exists: $old_dir"
    return 0
  fi

  warn "About to remove contents of: $old_dir"
  if [[ "$DRY_RUN" != "true" ]]; then
    read -r -p "Are you absolutely sure? Type 'DELETE' to confirm: " confirm
    if [[ "$confirm" != "DELETE" ]]; then
      info "Cleanup cancelled by user"
      return 0
    fi
  fi
  
  info "Cleaning up old data directory: $old_dir"
  run_cmd find "$old_dir" -mindepth 1 -delete
  info "Cleanup completed"
}

# Main execution function
main() {
  info "Starting PostgreSQL data directory migration (v${SCRIPT_VERSION})"
  info "Log file: $LOG_FILE"
  
  # Preflight checks
  require_root
  ensure_commands
  parse_args "$@"

  if [[ -z "$NEW_DATA_DIR" ]]; then
    error "--new-dir is required"
    usage
    exit 1
  fi

  # Detection and validation
  detect_cluster
  
  local service old_data_dir log_file
  service="$(get_service_unit)"
  old_data_dir="$(get_data_directory)"
  log_file="$(get_log_path || true)"
  
  info "Migration details:"
  info "  Cluster: ${PG_VER}/${PG_CLUSTER}"
  info "  Service: $service"
  info "  Old data dir: $old_data_dir"
  info "  New data dir: $NEW_DATA_DIR"
  [[ -n "$log_file" ]] && info "  PostgreSQL log: $log_file"

  # Validate old data directory exists and has data
  if [[ ! -d "$old_data_dir" ]]; then
    error "Old data directory does not exist: $old_data_dir"
    exit 1
  fi
  
  if [[ -z "$(find "$old_data_dir" -maxdepth 1 -name "PG_VERSION" 2>/dev/null)" ]]; then
    error "Old directory doesn't appear to be a PostgreSQL data directory: $old_data_dir"
    exit 1
  fi

  # Setup and validation
  setup_target_directory "$NEW_DATA_DIR"
  check_disk_space "$NEW_DATA_DIR" "$old_data_dir"
  setup_parent_permissions "$NEW_DATA_DIR"
  
  # Backup configurations
  backup_configurations

  # Migration process
  info "=== Starting Migration Process ==="
  
  # Stop PostgreSQL
  info "Stopping PostgreSQL service: $service"
  run_cmd systemctl stop "$service"
  
  # Verify it's stopped
  sleep 2
  if run_cmd systemctl is-active --quiet "$service"; then
    error "PostgreSQL service is still active after stop command"
    exit 1
  fi
  info "PostgreSQL service stopped successfully"

  # Copy data with progress indication
  info "Copying data from $old_data_dir to $NEW_DATA_DIR"
  info "This may take some time depending on data size..."
  
  # Use rsync with progress and compression for large transfers
  if [[ "$DRY_RUN" != "true" ]]; then
    run_cmd rsync -av --progress --delete --inplace --numeric-ids \
      "$old_data_dir/" "$NEW_DATA_DIR/"
  else
    run_cmd rsync -av --dry-run --delete --inplace --numeric-ids \
      "$old_data_dir/" "$NEW_DATA_DIR/"
  fi

  # Set final ownership and permissions
  run_cmd chown -R postgres:postgres "$NEW_DATA_DIR"
  run_cmd chmod 700 "$NEW_DATA_DIR"
  
  # Ensure parent directories are still accessible
  setup_parent_permissions "$NEW_DATA_DIR"

  # Update configuration
  update_config

  # Ensure runtime directory exists
  if [[ ! -d /run/postgresql ]]; then
    run_cmd install -d -o postgres -g postgres -m 2775 /run/postgresql
  fi

  # Start PostgreSQL
  info "Starting PostgreSQL service: $service"
  run_cmd systemctl start "$service"
  
  # Wait for startup
  sleep 3
  
  # Check service status
  if ! run_cmd systemctl --no-pager --lines=20 status "$service"; then
    error "PostgreSQL failed to start"
    [[ -n "$log_file" ]] && error "Check PostgreSQL logs: $log_file"
    exit 1
  fi

  # Verify connectivity and data directory
  if ! verify_connectivity; then
    error "Migration completed but connectivity verification failed"
    [[ -n "$log_file" ]] && error "Check PostgreSQL logs: $log_file"
    exit 1
  fi

  # Optional cleanup
  cleanup_old_data "$old_data_dir"

  # Success message
  info "=== Migration Completed Successfully ==="
  info "✅ PostgreSQL is running with data directory: $NEW_DATA_DIR"
  info "✅ Service: $service is active"
  [[ -n "$log_file" ]] && info "Monitor PostgreSQL logs: $log_file"
  info "Migration log saved to: $LOG_FILE"
  
  if [[ "$CLEANUP_OLD" != "true" ]]; then
    info ""
    info "Next steps:"
    info "  1. Verify your applications can connect"
    info "  2. Run database consistency checks if needed"
    info "  3. Consider cleaning up old data: $old_data_dir"
    info "  4. Ensure new disk is mounted at boot (check /etc/fstab)"
  fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
