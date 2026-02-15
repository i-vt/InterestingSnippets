# ── Color helpers ──────────────────────────────────────────────────────────────
RESET="\[\033[0m\]"
BOLD="\[\033[1m\]"
DIM="\[\033[2m\]"

_supports_truecolor=0
if [[ "${COLORTERM:-}" =~ (truecolor|24bit) ]]; then _supports_truecolor=1; fi

mkfg() {
  if (( _supports_truecolor )); then
    printf '\[\033[38;2;%s%sm\]' "$1" ""
  else
    printf '\[\033[38;5;%sm\]' "$2"
  fi
}

FG_TIME=$(mkfg "255;180;100" 215)     # warm soft orange (readable on dark bg)
FG_USER=$(mkfg "57;255;20" 46)        # neon green (bright, high contrast)
FG_HOST=$(mkfg "255;150;90" 209)      # softer orange for host
FG_PATH=$(mkfg "140;255;120" 119)     # slightly softer neon green for paths
FG_ARROW=$(mkfg "220;220;220" 252)    # light gray arrows (visible but not loud)
FG_ERR=$(mkfg "255;95;95" 203)        # warm red for errors
FG_OK=$(mkfg "57;255;20" 46)          # neon green OK
FG_HINT=$(mkfg "200;200;180" 250)     # lighter beige-gray for hints
FG_ROOT=$(mkfg "255;120;100" 196)     # strong warm orange/red for root user
BRIGHT_YELLOW=$(mkfg "255;230;120" 228) # accent highlight (not overused)


# ── Prompt newline hook ───────────────────────────────────────────────────────
__pc_newline() { __prompt_newline_ready=1; }

# ── Prompt builder (two lines) ────────────────────────────────────────────────
__ps1_build() {
  local uh_user_color="$FG_USER"
  [[ $EUID -eq 0 ]] && uh_user_color="$FG_ROOT"

  local TAB="    "
  local path_line="${FG_ARROW}>${RESET} ${TAB}${FG_PATH}[[ ${PWD} ]]${RESET}"
  local time_part="${FG_TIME}[\\t]${RESET}"
  local who_part="${uh_user_color}\\u${RESET}${FG_HINT}@${RESET}${FG_HOST}\\h${RESET}"

  PS1="\n${path_line}\n${FG_ARROW}>${RESET} ${time_part} ${who_part} : "
}

# ── History: configuration ────────────────────────────────────────────────────
export HISTFILE="${HISTFILE:-$HOME/.bash_history}"
export HISTSIZE=100000          # in-memory lines
export HISTFILESIZE=200000      # on-disk lines
export HISTCONTROL=ignoredups:erasedups:ignorespace
export HISTTIMEFORMAT='%F %T  ' # "YYYY-MM-DD HH:MM:SS  <cmd>"

# Ignore noisy commands (turned off b/c irritates me)
# export HISTIGNORE='ls:ls *:ll:la:cd:pwd:clear:history:exit:bg:fg:jobs'

# Append to the history file and store multi-line entries
shopt -s histappend
shopt -s cmdhist
shopt -s lithist

# ── History: share across concurrent shells ───────────────────────────────────
__hist_share() {
  builtin history -a           # append this session's new line
  builtin history -c           # clear current in-memory history
  builtin history -r           # reread merged history from disk
}

# ── PROMPT_COMMAND wiring (array-safe) ────────────────────────────────────────
if declare -p PROMPT_COMMAND &>/dev/null && [[ $(declare -p PROMPT_COMMAND 2>/dev/null) == "declare -a"* ]]; then
  PROMPT_COMMAND=(__pc_newline __hist_share "${PROMPT_COMMAND[@]}" __ps1_build)
else
  PROMPT_COMMAND="__pc_newline; __hist_share${PROMPT_COMMAND:+; $PROMPT_COMMAND}; __ps1_build"
fi

# ── Handy status colors for scripts (optional) ────────────────────────────────
export PS_OK="${FG_OK}[ok]${RESET}"
export PS_ERR="${FG_ERR}[err]${RESET}"

# ── Aliases (yours) ───────────────────────────────────────────────────────────
alias s2020='python3 -m http.server 2020'
alias s2021='python3 -m http.server 2021'
alias s2022='python3 -m http.server 2022'
alias wgup='wg-quick up /etc/wireguard/wg0.conf'
alias wgdown='wg-quick down /etc/wireguard/wg0.conf'
alias ports='ss -tulnp'

# ── Default editor ────────────────────────────────────────────────────────────
export EDITOR=vi
export VISUAL=vi


# ── Extras from your old config ───────────────────────────────────────────────
# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# check the window size after each command
shopt -s checkwinsize

# set variable identifying the chroot (used in the prompt if desired)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# Load aliases if ~/.bash_aliases exists
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# Enable programmable completion features
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
