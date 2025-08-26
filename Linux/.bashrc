# Color escapes (wrapped in \[ \] so bash counts prompt width correctly)
RESET="\[\033[0m\]"
GREEN="\[\033[32m\]"
YELLOW="\[\033[33m\]"
BLUE="\[\033[34m\]"

# __short_cwd
# Prints a compact path like: ~/…/p/q/Leaf  (only last 3 segments shown; middle two shortened to first letters)
__short_cwd() {
  local p="$PWD" base="" rel=""
  
  if [[ $p == "$HOME"* ]]; then
    base="~"
    rel="${p#$HOME/}"
    [[ "$p" == "$HOME" ]] && { echo "~"; return; }
  else
    base="/"
    rel="${p#/}"
    [[ -z "$rel" ]] && { echo "/"; return; }
  fi
  
  IFS='/' read -r -a parts <<< "$rel"
  local n=${#parts[@]}
  
  if (( n <= 3 )); then
    printf "%s/%s" "$base" "$rel"
  else
    local a="${parts[n-3]:0:1}"
    local b="${parts[n-2]:0:1}"
    local c="${parts[n-1]}"
    
    if [[ $base == "~" ]]; then
      printf "~/%s/%s/%s" "…" "$a" "$b/$c"
    else
      printf "/%s/%s/%s" "…" "$a" "$b/$c"
    fi
  fi
}

# __pc_newline
# Marks that a new prompt is about to be drawn (used for spacing control if you hook it elsewhere)
__pc_newline() {
  __prompt_newline_ready=1
}

# __ps1_build
# Assembles a single-line PS1 with time, user@host (root = yellow user), and shortened cwd
__ps1_build() {
  local uh_color="$GREEN"
  [[ $EUID -eq 0 ]] && uh_color="$YELLOW"
  
  local time_part="${BLUE}[\t]${RESET}"
  local who_part="${uh_color}\u${RESET}@${YELLOW}\h${RESET}"
  local cwd_part="${GREEN}$(__short_cwd)${RESET} : "
  
  PS1="${time_part} ${who_part} ${cwd_part} "
}

# PROMPT_COMMAND wiring:
# Run __pc_newline once, then any existing PROMPT_COMMAND entries, then __ps1_build.
if declare -p PROMPT_COMMAND &>/dev/null && [[ $(declare -p PROMPT_COMMAND 2>/dev/null) == "declare -a"* ]]; then
  PROMPT_COMMAND=(__pc_newline "${PROMPT_COMMAND[@]}" __ps1_build)
else
  PROMPT_COMMAND="__pc_newline${PROMPT_COMMAND:+; $PROMPT_COMMAND}; __ps1_build"
fi

# Aliases 
alias s2020='python3 -m http.server 2020'
alias s2021='python3 -m http.server 2021'
alias s2022='python3 -m http.server 2022'
alias wgup='wg-quick up /etc/wireguard/wg0.conf'
alias wgdown='wg-quick down /etc/wireguard/wg0.conf'
alias vim='vi'

# Set default editor to vi 
export EDITOR=vi
export VISUAL=vi
