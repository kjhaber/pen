# bash completion for claude-devcon
# Installed by Homebrew to $(brew --prefix)/etc/bash_completion.d/
# or manually sourced from your .bash_profile / .bashrc

_claude_devcon() {
  local cur prev
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  # Complete subcommands at position 1
  if [[ $COMP_CWORD -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "exec stop list sync-settings" -- "$cur") )
    return
  fi

  # Complete container names for stop and exec at position 2
  case "$prev" in
    stop|exec)
      local containers
      containers=$(claude-devcon list --names-only 2>/dev/null)
      COMPREPLY=( $(compgen -W "$containers" -- "$cur") )
      ;;
  esac
}

complete -F _claude_devcon claude-devcon
