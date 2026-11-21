# nvim

Minha config do Neovim, baseada no [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim).
Funciona no macOS e no Linux (inclusive sem sudo).

Linguagens: C/C++ (clangd, clang-format), Python (pyright, ruff) e Lua (lua_ls, stylua).
Extras: git (gitsigns, lazygit), neo-tree, Copilot e Jupyter notebooks (jupytext, molten, image.nvim).

## Instalar numa máquina nova

```bash
git clone <url-deste-repo> ~/.config/nvim
~/.config/nvim/install.sh --check   # só mostra o que existe e o que falta
~/.config/nvim/install.sh           # instala
```

- **macOS:** usa o Homebrew, sem sudo.
- **Linux:** baixa tudo para `~/.local` (Neovim, ripgrep, fd, lazygit, tree-sitter, Node, uv/Python), sem sudo e sem apt.
  Se faltar compilador C, `unzip` ou `python3-venv`, o script cria substitutos em
  `~/.local/share/nvim/shims`, que só valem dentro do nvim.

Precisa existir na máquina: `git`, `curl`, `tar` e `gzip`.
Em Linux ARM (aarch64), o Mason não tem clangd: o LSP de C/C++ só funciona se já houver um `clangd` no PATH.
Se algo falhar no meio (rede, por exemplo), rode o `install.sh` de novo: o que já foi instalado é pulado.
Os gráficos nos notebooks só aparecem em terminais com o protocolo gráfico do Kitty (Ghostty, WezTerm, Kitty).

Depois de instalar, abra um terminal novo, rode `nvim` e, na primeira vez, `:Copilot setup`.

## Onde fica cada coisa

| Arquivo | O que tem |
|---|---|
| `init.lua` | Base do kickstart: opções, LSP, autocomplete, formatação, treesitter |
| `lua/custom/options.lua` | Minhas opções |
| `lua/custom/keymaps.lua` | Meus atalhos |
| `lua/custom/plugins/*.lua` | Plugins extras; qualquer arquivo novo aqui é carregado sozinho |
| `nvim-pack-lock.json` | Versão exata de cada plugin (mantém as máquinas iguais) |
| `install.sh` | Instalador para macOS e Linux |

## Atualizar plugins

Dentro do nvim: `:lua vim.pack.update()`. Depois faça commit do `nvim-pack-lock.json`.
