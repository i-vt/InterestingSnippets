#!/usr/bin/env bash
#
# portmap — show exactly which application listens on which port
# Debian 13 (trixie). Requires only iproute2 (preinstalled); uses /proc and ps.
#
#   ./portmap            # summary first, then full per-port details
#   ./portmap --json     # JSON array only (no summary)
#
# Run as root (sudo ./portmap) to see ALL processes — unprivileged users
# only get details for processes they own.

set -euo pipefail

MODE=text
case "${1:-}" in
  "") ;;
  --json) MODE=json ;;
  -h|--help) grep '^#' "$0" | cut -c3-; exit 0 ;;
  *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

REC_FILE=$(mktemp); SORTED=$(mktemp)
trap 'rm -f "$REC_FILE" "$SORTED"' EXIT

add_record() { # proto addr port pid name user ppid parent unit started exe cmdline
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >>"$REC_FILE"
}

# ---------------- collect: one record per (socket, owning process) ----------
while IFS= read -r line; do
  # ss -H -tulpn columns: Netid State Recv-Q Send-Q Local Peer Process
  read -r netid state _rq _sq local _peer proc <<<"$line"
  [[ $netid == tcp && $state != LISTEN ]] && continue   # keep tcp LISTEN + all udp

  port=${local##*:}
  addr=${local%:*}; addr=${addr#[}; addr=${addr%]}       # strip [ ] from IPv6
  [[ $port =~ ^[0-9]+$ ]] || port=0

  if [[ $proc == *users:* ]]; then
    rest=$proc
    while [[ $rest =~ \"([^\"]+)\",pid=([0-9]+) ]]; do   # a socket can have several owners
      name=${BASH_REMATCH[1]}; pid=${BASH_REMATCH[2]}
      rest=${rest/"${BASH_REMATCH[0]}"/}

      user=- exe=- cmdline=- ppid=0 parent=- unit=- started=-
      if [[ -d /proc/$pid ]]; then
        user=$(stat -c %U "/proc/$pid" 2>/dev/null || echo '?')
        exe=$(readlink "/proc/$pid/exe" 2>/dev/null || echo '-')
        cmdline=$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)
        cmdline=${cmdline% }
        [[ -z $cmdline ]] && cmdline="[$(<"/proc/$pid/comm")]"
        ppid=$(awk '/^PPid:/{print $2; exit}' "/proc/$pid/status" 2>/dev/null || echo 0)
        [[ -n ${ppid:-} && -r /proc/$ppid/comm ]] && parent=$(<"/proc/$ppid/comm")
        unit=$(grep -m1 -oE '[^/]+\.(service|socket|scope)' "/proc/$pid/cgroup" 2>/dev/null || true)
        unit=${unit:--}
        started=$(ps -o lstart= -p "$pid" 2>/dev/null | sed 's/^ *//')
        started=${started:--}
      fi
      add_record "$netid" "$addr" "$port" "$pid" "$name" "$user" \
                 "$ppid" "$parent" "$unit" "$started" "$exe" "$cmdline"
    done
  else
    add_record "$netid" "$addr" "$port" 0 "(unknown/need-root)" - 0 - - - - -
  fi
done < <(ss -H -tulpn 2>/dev/null)

LC_ALL=C sort -t$'\t' -k1,1 -k3,3n "$REC_FILE" >"$SORTED"

json_escape() {
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}; s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

# ---------------- JSON mode: array only, no summary -------------------------
if [[ $MODE == json ]]; then
  echo "["
  first=1
  while IFS=$'\t' read -r proto addr port pid name user ppid parent unit started exe cmdline; do
    (( first )) || printf ',\n'
    first=0
    printf '  {"proto": "%s", "address": "%s", "port": %s, "pid": %s, "process": "%s", "user": "%s", "ppid": %s, "parent": "%s", "unit": "%s", "started": "%s", "exe": "%s", "cmdline": "%s"}' \
      "$(json_escape "$proto")" "$(json_escape "$addr")" "$port" "$pid" \
      "$(json_escape "$name")" "$(json_escape "$user")" "${ppid:-0}" \
      "$(json_escape "$parent")" "$(json_escape "$unit")" "$(json_escape "$started")" \
      "$(json_escape "$exe")" "$(json_escape "$cmdline")"
  done <"$SORTED"
  (( first )) || echo
  echo "]"
  exit 0
fi

# ---------------- text mode: SUMMARY then FULL DETAILS ----------------------
total=$(wc -l <"$SORTED")
tcp_n=$(awk -F'\t' '$1=="tcp"' "$SORTED" | wc -l)
udp_n=$(awk -F'\t' '$1=="udp"' "$SORTED" | wc -l)
ports_n=$(cut -f3 "$SORTED" | sort -n | uniq | wc -l)
pub_n=$(awk -F'\t' '$2=="0.0.0.0" || $2=="::" || $2=="*"' "$SORTED" | wc -l)

echo "========================= SUMMARY ========================="
printf 'Listening sockets : %s  (tcp: %s, udp: %s)\n' "$total" "$tcp_n" "$udp_n"
printf 'Distinct ports    : %s\n' "$ports_n"
printf 'Public-facing     : %s (bound to 0.0.0.0 / ::)\n' "$pub_n"
(( EUID )) && echo "NOTE: not running as root — process info may be incomplete"

echo
echo "-- by user (sockets) --"
cut -f6 "$SORTED" | sort | uniq -c | sort -rn | awk '{printf "  %-18s %s\n", $2, $1}'

echo
echo "-- by application (sockets) --"
cut -f5 "$SORTED" | sort | uniq -c | sort -rn | awk '{printf "  %-18s %s\n", $2, $1}'

echo
echo "======================= FULL DETAILS ======================"
while IFS=$'\t' read -r proto addr port pid name user ppid parent unit started exe cmdline; do
  printf -- '-- %s/%s on %s --\n' "$proto" "$port" "$addr"
  printf '   process : %s (pid %s, user %s)\n' "$name" "$pid" "$user"
  printf '   command : %s\n' "$cmdline"
  printf '   exe     : %s\n' "$exe"
  printf '   parent  : %s (pid %s)\n' "$parent" "$ppid"
  printf '   unit    : %s\n' "$unit"
  printf '   started : %s\n' "$started"
done <"$SORTED"
