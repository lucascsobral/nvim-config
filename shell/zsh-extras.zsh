# Extras do zsh: menu de completar enquanto digita (zsh-autocomplete) e comandos gerados por IA
# (ShellGPT, pelo CLI Proxy API). O install.sh instala os dois e põe no topo do ~/.zshrc:
#   source ~/.config/nvim/shell/zsh-extras.zsh
#
# O zsh-autocomplete precisa vir antes de qualquer `compdef` e não pode haver `compinit` no
# ~/.zshrc (ele mesmo chama). No Ubuntu, o ~/.zshenv também precisa de `skip_global_compinit=1`.

# [[ zsh-autocomplete ]] ---------------------------------------------------------
for _f in \
  /opt/homebrew/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh \
  /usr/local/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh \
  "${XDG_DATA_HOME:-$HOME/.local/share}/zsh-autocomplete/zsh-autocomplete.plugin.zsh"; do
  if [[ -r $_f ]]; then
    source "$_f"
    break
  fi
done
unset _f

# [[ ShellGPT ]] -----------------------------------------------------------------
# Usa a mesma chave do minuet. Ela só é passada ao sgpt, para não mudar o OPENAI_API_KEY
# de outros programas. Endereço e modelo ficam em ~/.config/shell_gpt/.sgptrc.
sgpt() { OPENAI_API_KEY="$CLIPROXY_KEY" command sgpt "$@"; }

# Ctrl+L: troca o texto da linha (ex.: "matar o processo na porta 8080") pelo comando.
# O comando não roda sozinho: confira e aperte Enter. Para limpar a tela, use `clear`.
_sgpt_zsh() {
  [[ -z $BUFFER ]] && return
  local prompt=$BUFFER cmd
  BUFFER="$prompt ⌛"
  zle -R # mostra o ⌛ enquanto espera (`zle -I` trava junto com o zsh-autocomplete)
  cmd=$(sgpt --shell --no-interaction <<<"$prompt" 2>/dev/null | sed '/^```/d')
  if [[ -n $cmd ]]; then
    BUFFER=$cmd
  else
    BUFFER=$prompt
    zle -M 'ShellGPT não respondeu (CLIPROXY_KEY definida? rede?)'
  fi
  zle end-of-line
}
zle -N _sgpt_zsh
bindkey '^L' _sgpt_zsh
