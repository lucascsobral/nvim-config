#!/usr/bin/env bash
# Instala as dependências desta config do Neovim.
#
#   macOS : usa o Homebrew (não precisa de sudo)
#   Linux : baixa tudo para ~/.local, sem sudo e sem apt
#
# Uso:
#   ./install.sh --check   mostra o que já existe e o que falta, sem instalar nada
#   ./install.sh           instala o que falta e baixa plugins, LSPs e parsers
#
# Pode rodar de novo quantas vezes quiser: o que já está instalado é pulado.

set -euo pipefail

CHECK_ONLY=0
case "${1:-}" in
  --check) CHECK_ONLY=1 ;;
  "") ;;
  *) echo "uso: $0 [--check]" >&2; exit 2 ;;
esac

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL="$HOME/.local"
BIN="$LOCAL/bin"
OPT="$LOCAL/opt"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
SHIMS="$DATA/shims" # só entra no PATH de dentro do nvim (ver topo do init.lua)
VENV="$DATA/python-venv"

NVIM_MIN=0.12.0
NODE_MIN=20
NODE_LINE=latest-v24.x
PY_VERSION=3.13
PY_PACKAGES=(norminette c-formatter-42)
ZIG_VERSION=0.14.1

ORIG_PATH="$PATH"
export PATH="$BIN:$PATH"

FAILED=()
WARNINGS=() # problemas que não impedem o nvim de funcionar (ex.: chave do minuet ausente)
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- saída -------------------------------------------------------------------
if [ -t 1 ]; then G=$'\033[32m' Y=$'\033[33m' R=$'\033[31m' B=$'\033[1m' N=$'\033[0m'; else G='' Y='' R='' B='' N=''; fi
title() { printf '\n%s%s%s\n' "$B" "$*" "$N"; }
ok() { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
todo() { printf '  %s→%s %s\n' "$Y" "$N" "$*"; }
bad() { printf '  %s✗%s %s\n' "$R" "$N" "$*"; }
warn() { bad "$*"; WARNINGS+=("$*"); }

have() { command -v "$1" >/dev/null 2>&1; }

version_ge() { # $1 >= $2 ?
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" = "$2" ]
}

nvim_ok() {
  have nvim || return 1
  local v
  v="$(nvim --version 2>/dev/null | head -1 | sed -nE 's/^NVIM v([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')"
  [ -n "$v" ] && version_ge "$v" "$NVIM_MIN"
}

node_ok() {
  have node || return 1
  local major
  major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null)" || return 1
  [ "${major:-0}" -ge "$NODE_MIN" ]
}

# step "descrição" função_que_verifica função_que_instala
step() {
  local desc="$1" check="$2" install="$3"
  if "$check"; then ok "$desc"; return 0; fi
  if [ "$CHECK_ONLY" = 1 ]; then todo "$desc: falta (será instalado)"; return 0; fi
  todo "$desc: instalando..."
  if "$install" && "$check"; then
    ok "$desc: instalado"
  else
    bad "$desc: falhou"
    FAILED+=("$desc")
  fi
}

# --- downloads (Linux) -------------------------------------------------------
dl() { curl -fL --retry 3 -sS -o "$2" "$1"; }

# URL do primeiro asset da última release que casar com um dos padrões (regex).
gh_asset() {
  local repo="$1" json urls re u
  shift
  local auth=()
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  json="$(curl -fsSL ${auth[@]+"${auth[@]}"} "https://api.github.com/repos/$repo/releases/latest")" || return 1
  urls="$(printf '%s' "$json" | grep -o '"browser_download_url": *"[^"]*"' | sed -E 's/.*"(https[^"]+)"$/\1/')"
  for re in "$@"; do
    u="$(printf '%s\n' "$urls" | grep -E "$re" | head -1 || true)"
    if [ -n "$u" ]; then echo "$u"; return 0; fi
  done
  return 1
}

# Baixa um .tar.gz de release e copia o executável $3 para ~/.local/bin
install_bin_from_tarball() {
  local url="$1" bin="$2" dir="$TMP/$2"
  mkdir -p "$dir" "$BIN"
  dl "$url" "$dir/pkg.tar.gz" && tar -xzf "$dir/pkg.tar.gz" -C "$dir" || return 1
  local found
  found="$(find "$dir" -type f -name "$bin" | head -1)"
  [ -n "$found" ] && install -m 755 "$found" "$BIN/$bin"
}

managed_python() {
  uv python find --managed-python "$PY_VERSION" 2>/dev/null || uv python find "$PY_VERSION" 2>/dev/null
}

# --- Linux: cada ferramenta --------------------------------------------------
linux_arch() {
  case "$(uname -m)" in
    x86_64 | amd64) ARCH=x86_64 NVIM_ARCH=x86_64 NODE_ARCH=x64 TS_ARCH=x64 LG_ARCH=x86_64 ;;
    aarch64 | arm64) ARCH=aarch64 NVIM_ARCH=arm64 NODE_ARCH=arm64 TS_ARCH=arm64 LG_ARCH=arm64 ;;
    *) bad "arquitetura não suportada: $(uname -m)"; exit 1 ;;
  esac
}

uv_ok() { have uv; }
uv_install() {
  local url
  url="$(gh_asset astral-sh/uv "uv-$ARCH-unknown-linux-musl\.tar\.gz$" "uv-$ARCH-unknown-linux-gnu\.tar\.gz$")" || return 1
  install_bin_from_tarball "$url" uv && install_bin_from_tarball "$url" uvx
}

python_ok() { have uv && [ -n "$(managed_python)" ]; }
python_install() { uv python install "$PY_VERSION"; }

nvim_install() {
  local f="$TMP/nvim.tar.gz"
  dl "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-$NVIM_ARCH.tar.gz" "$f" || return 1
  mkdir -p "$OPT" "$BIN"
  rm -rf "$OPT/nvim" "$OPT/nvim-linux-$NVIM_ARCH"
  tar -xzf "$f" -C "$OPT" && mv "$OPT/nvim-linux-$NVIM_ARCH" "$OPT/nvim" || return 1
  ln -sf "$OPT/nvim/bin/nvim" "$BIN/nvim"
  if ! "$BIN/nvim" --version >/dev/null 2>&1; then
    bad "o binário do Neovim não roda nesta máquina (glibc antiga?): $("$BIN/nvim" --version 2>&1 | head -1)"
    return 1
  fi
}

rg_ok() { have rg; }
rg_install() {
  local url
  url="$(gh_asset BurntSushi/ripgrep "$ARCH-unknown-linux-musl\.tar\.gz$" "$ARCH-unknown-linux-gnu\.tar\.gz$")" || return 1
  install_bin_from_tarball "$url" rg
}

fd_ok() { have fd || have fdfind; }
fd_install() {
  local url
  url="$(gh_asset sharkdp/fd "$ARCH-unknown-linux-musl\.tar\.gz$" "$ARCH-unknown-linux-gnu\.tar\.gz$")" || return 1
  install_bin_from_tarball "$url" fd
}

lazygit_ok() { have lazygit; }
lazygit_install() {
  local url
  url="$(gh_asset jesseduffield/lazygit "_[Ll]inux_$LG_ARCH\.tar\.gz$")" || return 1
  install_bin_from_tarball "$url" lazygit
}

ts_ok() { have tree-sitter && tree-sitter --version >/dev/null 2>&1; }
ts_install() {
  local url
  url="$(gh_asset tree-sitter/tree-sitter "tree-sitter-linux-$TS_ARCH\.gz$")" || return 1
  mkdir -p "$BIN"
  dl "$url" "$TMP/ts.gz" && gunzip -c "$TMP/ts.gz" >"$BIN/tree-sitter" && chmod 755 "$BIN/tree-sitter"
}

node_install() {
  local name
  name="$(curl -fsSL "https://nodejs.org/dist/$NODE_LINE/SHASUMS256.txt" | grep -oE "node-v[0-9.]+-linux-$NODE_ARCH\.tar\.gz" | head -1)" || return 1
  [ -n "$name" ] || return 1
  dl "https://nodejs.org/dist/$NODE_LINE/$name" "$TMP/node.tar.gz" || return 1
  mkdir -p "$OPT" "$BIN"
  rm -rf "$OPT/node" "$OPT/${name%.tar.gz}"
  tar -xzf "$TMP/node.tar.gz" -C "$OPT" && mv "$OPT/${name%.tar.gz}" "$OPT/node" || return 1
  local b
  for b in node npm npx; do ln -sf "$OPT/node/bin/$b" "$BIN/$b"; done
}

cc_ok() { have cc || have gcc || have clang || [ -x "$SHIMS/cc" ]; }
cc_install() {
  # Sem compilador C no sistema: usa o Zig (um compilador C num arquivo só) como `cc` dentro do nvim.
  local name="zig-$ARCH-linux-$ZIG_VERSION" f="$TMP/zig.tar.xz" py
  dl "https://ziglang.org/download/$ZIG_VERSION/$name.tar.xz" "$f" || return 1
  mkdir -p "$OPT" "$SHIMS"
  rm -rf "$OPT/zig" "$OPT/$name"
  if have xz; then
    tar -xJf "$f" -C "$OPT" || return 1
  else
    py="$(managed_python)" || return 1
    "$py" -c 'import sys, tarfile; tarfile.open(sys.argv[1]).extractall(sys.argv[2], filter="data")' "$f" "$OPT" || return 1
  fi
  mv "$OPT/$name" "$OPT/zig" || return 1
  write_zig_shim cc
  write_zig_shim c++
}

# O tree-sitter passa o target no formato do Rust (aarch64-unknown-linux-gnu),
# que o zig não entende; o shim converte para aarch64-linux-gnu.
write_zig_shim() {
  cat >"$SHIMS/$1" <<EOF
#!/bin/sh
fix=0
for a do
  shift
  if [ "\$fix" = 1 ]; then a=\$(printf %s "\$a" | sed 's/-unknown-/-/; s/-pc-/-/'); fix=0; fi
  case "\$a" in
    -target) fix=1 ;;
    --target=*) a="--target=\$(printf %s "\${a#--target=}" | sed 's/-unknown-/-/; s/-pc-/-/')" ;;
  esac
  set -- "\$@" "\$a"
done
exec "$OPT/zig/zig" $1 "\$@"
EOF
  chmod 755 "$SHIMS/$1"
}

unzip_ok() { have unzip || [ -x "$SHIMS/unzip" ]; }
unzip_install() {
  # O Mason usa `unzip -d . arquivo.zip`. Este substituto em Python faz o mesmo e preserva permissões.
  local py
  py="$(managed_python)" || return 1
  mkdir -p "$SHIMS"
  cat >"$SHIMS/unzip" <<EOF
#!$py
import os, sys, zipfile
dest, files, args, i = ".", [], sys.argv[1:], 0
while i < len(args):
    if args[i] == "-d":
        dest = args[i + 1]; i += 2; continue
    if not args[i].startswith("-"):
        files.append(args[i])
    i += 1
for f in files:
    with zipfile.ZipFile(f) as z:
        for info in z.infolist():
            path = z.extract(info, dest)
            mode = (info.external_attr >> 16) & 0o777
            if mode:
                os.chmod(path, mode)
EOF
  chmod 755 "$SHIMS/unzip"
}

# O Mason cria venvs com `python3 -m venv`. No Ubuntu sem o pacote python3-venv isso falha,
# então dentro do nvim o `python3` passa a ser o Python instalado pelo uv.
py3venv_ok() {
  [ -x "$SHIMS/python3" ] && return 0
  have python3 && python3 -c 'import ensurepip, venv' >/dev/null 2>&1
}
py3venv_install() {
  local py
  py="$(managed_python)" || return 1
  mkdir -p "$SHIMS"
  ln -sf "$py" "$SHIMS/python3"
}

# Fonte MesloLGS Nerd Font Mono (Menlo do macOS + ícones). Só faz diferença se você usa um
# terminal gráfico nesta máquina; por SSH, quem desenha a fonte é o terminal do seu computador.
FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/MesloNerdFont"
font_linux_ok() { ls "$FONT_DIR"/MesloLGSNerdFontMono-*.ttf >/dev/null 2>&1; }
font_linux_install() {
  local py
  py="$(managed_python)" || return 1
  dl "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Meslo.zip" "$TMP/Meslo.zip" || return 1
  mkdir -p "$FONT_DIR"
  # Extrai só as 4 variantes MesloLGS Mono (regular, bold, italic, bold italic)
  "$py" - "$TMP/Meslo.zip" "$FONT_DIR" <<'EOF' || return 1
import sys, zipfile, os
with zipfile.ZipFile(sys.argv[1]) as z:
    for name in z.namelist():
        base = os.path.basename(name)
        if base.startswith("MesloLGSNerdFontMono-") and base.endswith(".ttf"):
            with open(os.path.join(sys.argv[2], base), "wb") as out:
                out.write(z.read(name))
EOF
  if have fc-cache; then fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true; fi
}

# --- comum aos dois sistemas -------------------------------------------------
venv_ok() { [ -x "$VENV/bin/python" ] && "$VENV/bin/python" -c 'import norminette, c_formatter_42' >/dev/null 2>&1; }
venv_install() {
  [ -x "$VENV/bin/python" ] || uv venv -q --python "$PY_VERSION" "$VENV" || return 1
  VIRTUAL_ENV="$VENV" uv pip install -q "${PY_PACKAGES[@]}"
}

bootstrap_nvim() {
  title "Plugins, LSPs e parsers (pode levar alguns minutos)"
  if [ "$CHECK_ONLY" = 1 ]; then
    todo "o nvim baixa plugins, LSPs (Mason) e parsers (treesitter) na instalação"
    return 0
  fi
  local log="$TMP/nvim-bootstrap.log" status attempt
  # Manifesto de plugins remotos deixado pelo molten (Jupyter), que saiu da config.
  if grep -q molten "$DATA/rplugin.vim" 2>/dev/null; then rm -f "$DATA/rplugin.vim"; fi
  local errors='^E[0-9]+:|Error executing|stack traceback|\] error:|Failed to (compile|install)'
  # Duas tentativas: falhas soltas (rede, compilação de um parser) costumam passar na segunda,
  # que só refaz o que faltou.
  for attempt in 1 2; do
    status=0
    # vim.pack.add normalmente pede confirmação na primeira instalação; aqui ela é pulada.
    nvim --headless \
      --cmd 'lua local add = vim.pack.add; vim.pack.add = function(specs, opts) opts = opts or {}; opts.confirm = false; return add(specs, opts) end' \
      '+MasonToolsInstallSync' \
      "+lua require('nvim-treesitter').install(vim.g.treesitter_parsers):wait(600000)" \
      '+qa' >"$log" 2>&1 || status=$?
    if [ "$status" = 0 ] && ! grep -qE "$errors" "$log"; then
      ok "nvim configurado"
      return 0
    fi
    [ "$attempt" = 1 ] && todo "algo falhou na primeira tentativa; tentando de novo..."
  done
  tr '\r' '\n' <"$log" | grep -vE '^[[:space:]]*$' | tail -n 15 || true
  mkdir -p "$DATA" && cp "$log" "$DATA/install.log"
  bad "o nvim terminou com erro (código $status). Log completo: $DATA/install.log"
  grep -nE "$errors" "$log" | head -5 || true
  FAILED+=("bootstrap do nvim")
}

ensure_path_in_shell() {
  local line='export PATH="$HOME/.local/bin:$PATH"' rc added=0
  local zshrc="${ZDOTDIR:-$HOME}/.zshrc" bashrc="$HOME/.bashrc"
  # O arquivo do shell que você usa ($SHELL) é criado se não existir; o do outro shell só é
  # atualizado se já existir.
  local login_rc=""
  case "${SHELL:-}" in
    */zsh) login_rc="$zshrc" ;;
    */bash) login_rc="$bashrc" ;;
  esac

  local needs=()
  for rc in "$bashrc" "$zshrc"; do
    if [ -f "$rc" ] || [ "$rc" = "$login_rc" ]; then
      grep -qF "$line" "$rc" 2>/dev/null || needs+=("$rc")
    fi
  done
  # Já no PATH e nenhum arquivo precisa da linha: nada a fazer.
  case ":$ORIG_PATH:" in *":$BIN:"*) [ "${#needs[@]}" -eq 0 ] && return 0 ;; esac

  if [ "$CHECK_ONLY" = 1 ]; then
    for rc in ${needs[@]+"${needs[@]}"}; do todo "PATH: ~/.local/bin será adicionado em $rc"; done
    return 0
  fi
  for rc in ${needs[@]+"${needs[@]}"}; do
    printf '\n# adicionado pelo install.sh da config do nvim\n%s\n' "$line" >>"$rc"
    added=1
    ok "PATH: ~/.local/bin adicionado em $rc"
  done
  [ "$added" = 1 ] || ok "PATH: ~/.local/bin já está configurado"
}

# --- macOS -------------------------------------------------------------------
mac_main() {
  title "macOS: dependências via Homebrew"
  if ! have brew; then
    bad "Homebrew não encontrado. Instale em https://brew.sh e rode de novo."
    exit 1
  fi
  if xcode-select -p >/dev/null 2>&1; then
    ok "ferramentas de linha de comando do Xcode (compilador C, clangd, git)"
  else
    bad "faltam as ferramentas do Xcode: rode 'xcode-select --install' e depois este script de novo"
    FAILED+=("Xcode Command Line Tools")
  fi

  # fórmula:comando
  local pairs=(neovim:nvim ripgrep:rg fd:fd lazygit:lazygit tree-sitter-cli:tree-sitter node:node uv:uv)
  local missing=() p formula cmd
  for p in "${pairs[@]}"; do
    formula="${p%%:*}" cmd="${p##*:}"
    if [ "$cmd" = nvim ] && have nvim && ! nvim_ok; then
      todo "neovim: versão antiga, precisa de $NVIM_MIN+"
      missing+=("$formula")
    elif [ "$cmd" = node ] && have node && ! node_ok; then
      todo "node: versão antiga, precisa de $NODE_MIN+"
      missing+=("$formula")
    elif have "$cmd"; then
      ok "$formula"
    else
      todo "$formula: falta"
      missing+=("$formula")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ] && [ "$CHECK_ONLY" = 0 ]; then
    brew install "${missing[@]}" || brew upgrade "${missing[@]}" || FAILED+=("brew install ${missing[*]}")
  fi

  title "Fonte"
  step "MesloLGS Nerd Font (Menlo com ícones)" font_mac_ok font_mac_install
  check_terminal_font

  title "Python do nvim (norminette e c_formatter_42)"
  step "Python $PY_VERSION (uv)" python_ok python_install
  step "ambiente Python em $VENV" venv_ok venv_install
}

font_mac_ok() { brew list --cask font-meslo-lg-nerd-font >/dev/null 2>&1; }
font_mac_install() { brew install --cask font-meslo-lg-nerd-font; }

# --- Linux -------------------------------------------------------------------
linux_main() {
  linux_arch
  title "Linux ($(uname -m)), instalando em ~/.local, sem sudo"

  local glibc
  glibc="$(ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+$' || true)"
  if [ -n "$glibc" ]; then ok "glibc $glibc"; else todo "não consegui ler a versão da glibc"; fi

  local req missing_req=0
  for req in curl git tar gzip; do
    if have "$req"; then ok "$req"; else bad "$req: obrigatório e não dá para instalar sem sudo"; missing_req=1; fi
  done
  [ "$missing_req" = 0 ] || { bad "peça ao administrador para instalar o que falta acima"; exit 1; }

  title "Ferramentas"
  step "uv (gerenciador de Python)" uv_ok uv_install
  step "Python $PY_VERSION (uv)" python_ok python_install
  step "Neovim $NVIM_MIN+" nvim_ok nvim_install
  step "ripgrep (busca de texto)" rg_ok rg_install
  step "fd (busca de arquivos)" fd_ok fd_install
  step "lazygit" lazygit_ok lazygit_install
  step "tree-sitter CLI" ts_ok ts_install
  step "Node.js $NODE_MIN+ (usado pelo pyright)" node_ok node_install
  step "compilador C (parsers do treesitter)" cc_ok cc_install
  step "unzip (usado pelo Mason)" unzip_ok unzip_install
  step "python3 com venv (usado pelo Mason)" py3venv_ok py3venv_install

  title "Opcionais"
  if have make; then ok "make"; else todo "make: ausente; a busca do telescope usa o ordenador em Lua (um pouco mais lento)"; fi
  if [ "$ARCH" = aarch64 ] && ! have clangd; then
    todo "clangd: o Mason não tem clangd para Linux ARM; C/C++ fica sem LSP até existir um clangd no PATH"
  fi

  title "Fonte"
  step "MesloLGS Nerd Font (em $FONT_DIR)" font_linux_ok font_linux_install
  check_terminal_font

  title "Python do nvim (norminette e c_formatter_42)"
  step "ambiente Python em $VENV" venv_ok venv_install

  title "PATH"
  ensure_path_in_shell
}

# --- verificações (rodam no --check e no fim da instalação) ------------------

# O terminal precisa estar configurado para usar a fonte; instalar não basta.
check_terminal_font() {
  if [ -n "${SSH_CONNECTION:-}" ]; then
    todo "sessão SSH: a fonte que aparece é a do terminal do seu computador, não a desta máquina"
  fi
  local xdg="${XDG_CONFIG_HOME:-$HOME/.config}" f checked=0
  for f in "$xdg/ghostty/config" "$xdg/ghostty/config.ghostty" "$HOME/Library/Application Support/com.mitchellh.ghostty/config"; do
    [ -f "$f" ] || continue
    checked=1
    if grep -qE '^[[:space:]]*font-family[[:space:]]*=.*Meslo.*Nerd' "$f"; then
      ok "Ghostty usa a MesloLGS Nerd Font"
    else
      warn "Ghostty não usa a fonte: adicione em $f a linha font-family = \"MesloLGS Nerd Font Mono\""
    fi
  done
  if have wezterm || [ -d /Applications/WezTerm.app ]; then
    for f in "$xdg/wezterm/wezterm.lua" "$HOME/.wezterm.lua"; do
      [ -f "$f" ] || continue
      checked=1
      if grep -q 'Meslo' "$f"; then
        ok "WezTerm usa a MesloLGS Nerd Font"
      else
        warn "WezTerm não usa a fonte: em $f, use font = wezterm.font(\"MesloLGS Nerd Font Mono\")"
      fi
    done
  fi
  [ "$checked" = 1 ] || todo "não achei config do Ghostty/WezTerm: escolha \"MesloLGS Nerd Font Mono\" nas preferências do seu terminal"
}

# Plugins, LSPs e parsers que a config usa, olhando direto nas pastas (sem abrir o nvim).
check_nvim_state() {
  title "Config do nvim"
  local pack="$DATA/site/pack/core/opt" lock="$CONFIG_DIR/nvim-pack-lock.json" name missing=()

  if [ -f "$lock" ]; then
    local total=0
    while IFS= read -r name; do
      case "$name" in
        telescope-fzf-native.nvim) continue ;; # opcional: depende do make
      esac
      total=$((total + 1))
      [ -d "$pack/$name" ] || missing+=("$name")
    done < <(grep -oE '^    "[^"]+": \{' "$lock" | sed -E 's/^    "([^"]+)".*/\1/')
    if [ "${#missing[@]}" -eq 0 ]; then
      ok "plugins instalados ($total)"
    elif [ "${#missing[@]}" -eq "$total" ]; then
      todo "nenhum plugin instalado ainda ($total serão instalados pelo nvim)"
    else
      todo "plugins faltando: ${missing[*]}"
    fi
  fi

  missing=()
  local mason="$DATA/mason/packages" tools=(clang-format lua-language-server pyright ruff stylua)
  if ! have clangd && ! { [ "$(uname -s)" = Linux ] && [ "$(uname -m)" = aarch64 ]; }; then tools+=(clangd); fi
  for name in "${tools[@]}"; do [ -d "$mason/$name" ] || missing+=("$name"); done
  if [ "${#missing[@]}" -eq 0 ]; then ok "LSPs e formatadores (Mason): ${tools[*]}"; else todo "Mason ainda não instalou: ${missing[*]}"; fi
  if have clangd; then ok "clangd do sistema: $(command -v clangd)"; fi

  missing=()
  for name in c cpp python lua; do [ -f "$DATA/site/parser/$name.so" ] || missing+=("$name"); done
  if [ "${#missing[@]}" -eq 0 ]; then ok "parsers do treesitter (c, cpp, python, lua)"; else todo "parsers faltando: ${missing[*]}"; fi
}

# Minuet: plugin, chave, acesso ao proxy, modelo e uma sugestão de verdade.
# Endpoint, modelo e nome da variável são lidos do próprio minuet.lua.
check_minuet() {
  title "Sugestões com IA (minuet)"
  local cfg="$CONFIG_DIR/lua/custom/plugins/minuet.lua"
  if [ ! -f "$cfg" ]; then
    todo "minuet não está na config"
    return 0
  fi
  local end_point model key_var base key
  end_point="$(sed -nE "s/.*end_point = '([^']+)'.*/\1/p" "$cfg" | head -1)"
  model="$(sed -nE "s/.*model = '([^']+)'.*/\1/p" "$cfg" | head -1)"
  key_var="$(sed -nE "s/.*api_key = '([^']+)'.*/\1/p" "$cfg" | head -1)"
  base="${end_point%/chat/completions}"

  if [ -d "$DATA/site/pack/core/opt/minuet-ai.nvim" ]; then ok "plugin minuet instalado"; else todo "plugin minuet: será instalado pelo nvim"; fi

  key="${!key_var:-}"
  if [ -z "$key" ]; then
    if grep -qs "$key_var=" "$HOME/.zshrc" "${ZDOTDIR:-$HOME}/.zshrc" "$HOME/.zprofile" "$HOME/.bashrc" "$HOME/.profile"; then
      warn "$key_var está no arquivo do shell, mas não neste terminal: abra um terminal novo e rode de novo"
    else
      warn "$key_var não definida: o minuet fica desligado. Adicione ao ~/.zshrc ou ~/.bashrc: export $key_var=\"sua-chave\""
    fi
    return 0
  fi
  ok "$key_var definida"

  # A chave vai num arquivo de cabeçalho (só seu), para não aparecer na lista de processos.
  local hdr="$TMP/auth-header" body="$TMP/minuet-check.json" code
  (umask 077 && printf 'Authorization: Bearer %s\n' "$key" >"$hdr")

  code="$(curl -sS -m 15 -o "$body" -w '%{http_code}' -H @"$hdr" "$base/models" 2>/dev/null || true)"
  case "$code" in
    200)
      if grep -q "\"$model\"" "$body"; then
        ok "proxy ${base#https://} aceita a chave e tem o modelo $model"
      else
        warn "proxy responde, mas o modelo $model não está na lista: troque em $cfg"
        return 0
      fi
      ;;
    401 | 403) warn "proxy recusou a chave (HTTP $code): confira $key_var"; return 0 ;;
    000 | "") warn "sem acesso a ${base#https://} (rede, firewall ou proxy da empresa)"; return 0 ;;
    *) warn "proxy respondeu HTTP $code em $base/models"; return 0 ;;
  esac

  # Pedido de sugestão igual ao do minuet (sem raciocínio), medindo o tempo.
  local req="$TMP/minuet-req.json" time
  printf '{"model":"%s","max_tokens":20,"reasoning_effort":"none","messages":[{"role":"user","content":"Complete only with code: def soma(a, b):"}]}' "$model" >"$req"
  time="$(curl -sS -m 20 -o "$body" -w '%{http_code} %{time_total}' -H @"$hdr" -H 'Content-Type: application/json' -d @"$req" "$end_point" 2>/dev/null || true)"
  if [ "${time%% *}" = 200 ] && grep -q '"content"' "$body"; then
    ok "sugestão de teste respondida em $(LC_ALL=C printf '%.1f' "${time##* }") s"
  else
    warn "o proxy não devolveu sugestão (HTTP ${time%% *}); veja $DATA/minuet-check.json"
    cp "$body" "$DATA/minuet-check.json" 2>/dev/null || true
  fi
}

# --- main --------------------------------------------------------------------
case "$(uname -s)" in
  Darwin) mac_main ;;
  Linux) linux_main ;;
  *) bad "sistema não suportado: $(uname -s)"; exit 1 ;;
esac

if [ "$CHECK_ONLY" = 0 ] && ! nvim_ok; then
  bad "Neovim $NVIM_MIN+ não está disponível; pulando a etapa dos plugins"
  FAILED+=("Neovim")
else
  bootstrap_nvim
fi

check_nvim_state
check_minuet

title "Resumo"
if [ "${#WARNINGS[@]}" -gt 0 ]; then
  todo "atenção (${#WARNINGS[@]}): o nvim funciona, mas veja os itens marcados com ✗ acima"
fi
if [ "${#FAILED[@]}" -gt 0 ]; then
  bad "falhou: ${FAILED[*]}"
  exit 1
elif [ "$CHECK_ONLY" = 1 ]; then
  ok "verificação concluída. Rode ./install.sh para instalar o que falta."
else
  ok "pronto. Abra um terminal novo e rode: nvim"
fi
