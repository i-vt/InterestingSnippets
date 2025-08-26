# Color escapes (wrapped in \[ \] so bash counts prompt width correctly)
RESET="\[\033[0m\]"
BRIGHT_YELLOW="\[\033[93m\]"  # neon yellow

GREEN="\[\033[32m\]"   # user color
YELLOW="\[\033[33m\]"  # host color
BLUE="\[\033[34m\]"
RED="\[\033[31m\]"

# __pc_newline
__pc_newline() {
  __prompt_newline_ready=1
}

# __ps1_build
# Two-line prompt:
# (blank) -> "    " x2 + [[ <abs $PWD> ]]
# then [time] user@host :
__ps1_build() {
  local uh_color="$GREEN"
  [[ $EUID -eq 0 ]] && uh_color="$YELLOW"

  local TAB="    "
  local time_part="${BLUE}[\t]${RESET}"
  local who_part="${uh_color}\u${RESET}@${YELLOW}\h${RESET}"

  # Directory always bright yellow
  local path_line="> ${TAB}${BRIGHT_YELLOW}[[ ${PWD} ]]${RESET}"

  PS1="\n${path_line}\n> ${time_part} ${who_part} : "
}

# PROMPT_COMMAND wiring
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
alias ports='ss -tulnp'

# Default editor
export EDITOR=vi
export VISUAL=vi
