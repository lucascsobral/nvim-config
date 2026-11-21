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
PY_PACKAGES=(pynvim jupyter_client ipykernel jupytext nbformat pillow cairosvg pyperclip matplotlib numpy pandas)
ZIG_VERSION=0.14.1

ORIG_PATH="$PATH"
export PATH="$BIN:$PATH"

FAILED=()
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- saída -------------------------------------------------------------------
if [ -t 1 ]; then G=$'\033[32m' Y=$'\033[33m' R=$'\033[31m' B=$'\033[1m' N=$'\033[0m'; else G='' Y='' R='' B='' N=''; fi
title() { printf '\n%s%s%s\n' "$B" "$*" "$N"; }
ok() { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
todo() { printf '  %s→%s %s\n' "$Y" "$N" "$*"; }
bad() { printf '  %s✗%s %s\n' "$R" "$N" "$*"; }

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
  json="$(curl -fsSL "${auth[@]}" "https://api.github.com/repos/$repo/releases/latest")" || return 1
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

# --- comum aos dois sistemas -------------------------------------------------
venv_ok() { [ -x "$VENV/bin/python" ] && "$VENV/bin/python" -c 'import pynvim, jupyter_client, jupytext, ipykernel' >/dev/null 2>&1; }
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
      '+UpdateRemotePlugins' \
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
  case ":$ORIG_PATH:" in *":$BIN:"*) return 0 ;; esac
  local line='export PATH="$HOME/.local/bin:$PATH"' rc added=0
  if [ "$CHECK_ONLY" = 1 ]; then
    todo "~/.local/bin não está no PATH: será adicionado ao ~/.bashrc / ~/.zshrc"
    return 0
  fi
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$rc" ] && ! grep -qF "$line" "$rc"; then
      printf '\n# adicionado pelo install.sh da config do nvim\n%s\n' "$line" >>"$rc"
      added=1
      ok "PATH: ~/.local/bin adicionado em $rc"
    fi
  done
  [ "$added" = 1 ] || todo "adicione ao seu shell: $line"
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
  local pairs=(neovim:nvim ripgrep:rg fd:fd lazygit:lazygit tree-sitter-cli:tree-sitter node:node uv:uv imagemagick:magick)
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

  title "Python do nvim (Jupyter)"
  step "Python $PY_VERSION (uv)" python_ok python_install
  step "ambiente Python em $VENV" venv_ok venv_install
}

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
  step "Node.js $NODE_MIN+ (Copilot e pyright)" node_ok node_install
  step "compilador C (parsers do treesitter)" cc_ok cc_install
  step "unzip (usado pelo Mason)" unzip_ok unzip_install
  step "python3 com venv (usado pelo Mason)" py3venv_ok py3venv_install

  title "Opcionais"
  if have make; then ok "make"; else todo "make: ausente; a busca do telescope usa o ordenador em Lua (um pouco mais lento)"; fi
  if [ "$ARCH" = aarch64 ] && ! have clangd; then
    todo "clangd: o Mason não tem clangd para Linux ARM; C/C++ fica sem LSP até existir um clangd no PATH"
  fi
  if have magick || have convert; then ok "ImageMagick"; else todo "ImageMagick: ausente; notebooks funcionam, mas sem gráficos dentro do nvim"; fi

  title "Python do nvim (Jupyter)"
  step "ambiente Python em $VENV" venv_ok venv_install

  title "PATH"
  ensure_path_in_shell
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

title "Resumo"
if [ "${#FAILED[@]}" -gt 0 ]; then
  bad "falhou: ${FAILED[*]}"
  exit 1
elif [ "$CHECK_ONLY" = 1 ]; then
  ok "verificação concluída. Rode ./install.sh para instalar o que falta."
else
  ok "pronto. Abra um terminal novo e rode: nvim"
  todo "IA: defina CLIPROXY_KEY no seu shell para as sugestões do minuet (veja o README)"
fi
