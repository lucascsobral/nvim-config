# nvim

Minha config do Neovim, baseada no [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim).
Funciona no macOS e no Linux (inclusive sem sudo).

Linguagens: C na norma da 42 (clangd, norminette, c_formatter_42), C++ (clangd, clang-format),
Python (pyright, ruff) e Lua (lua_ls, stylua).
Extras: git (gitsigns, lazygit), neo-tree e sugestões de código com IA (minuet).

## Instalar numa máquina nova

```bash
git clone https://github.com/lucascsobral/nvim-config.git ~/.config/nvim
~/.config/nvim/install.sh --check   # só mostra o que existe e o que falta
~/.config/nvim/install.sh           # instala
```

- **macOS:** usa o Homebrew, sem sudo.
- **Linux:** baixa tudo para `~/.local` (Neovim, ripgrep, fd, lazygit, tree-sitter, Node, uv/Python), sem sudo e sem apt.
  Se faltar compilador C, `unzip` ou `python3-venv`, o script cria substitutos em
  `~/.local/share/nvim/shims`, que só valem dentro do nvim.
  Também coloca `~/.local/bin` no PATH, no `~/.zshrc` e/ou no `~/.bashrc`. O arquivo do shell
  que você usa é criado se ainda não existir; o script funciona igual com zsh ou bash.

Precisa existir na máquina: `git`, `curl`, `tar` e `gzip`.
Em Linux ARM (aarch64), o Mason não tem clangd: o LSP de C/C++ só funciona se já houver um `clangd` no PATH.
Se algo falhar no meio (rede, por exemplo), rode o `install.sh` de novo: o que já foi instalado é pulado.

Depois de instalar, abra um terminal novo e rode `nvim`.

## Fonte

O `install.sh` instala a **MesloLGS Nerd Font**, uma versão da Menlo (a fonte monoespaçada do macOS)
com os ícones usados pela árvore de arquivos, pela barra de status e pelo autocomplete.
No macOS ela vem do Homebrew; no Linux vai para `~/.local/share/fonts`, sem sudo.

Escolha a fonte no terminal. No Ghostty (`~/.config/ghostty/config` no Linux,
`~/Library/Application Support/com.mitchellh.ghostty/config` no macOS):

```
font-family = "MesloLGS Nerd Font Mono"
```

Se você acessa o Linux por SSH, a fonte que vale é a do terminal do seu computador, não a do servidor.

## C na norma da 42

Em arquivos `.c` e `.h` (os `.h` são tratados como C, não C++):

- A indentação é com tab, e cada tab conta como 4 colunas. A coluna 81 fica marcada.
- A `norminette` roda ao abrir e ao salvar. Os erros aparecem como os do LSP: sublinhado,
  mensagem no fim da linha e `<leader>d` para ver o texto completo. `<leader>tN` liga e desliga.
  Ela confere toda a norma: 25 linhas por função, 80 colunas, 4 parâmetros, 5 variáveis,
  5 funções por arquivo, linhas vazias e espaços consecutivos, o cabeçalho da 42 etc.
- Ao salvar, o `c_formatter_42` formata o arquivo (tabs, alinhamento, `return (x);`).
  Ele não resolve tudo: funções longas, parâmetros demais e o cabeçalho ficam por sua conta.
  Para salvar sem formatar, use `<leader>W`. Em Linux ARM ele não roda (só existe para x86_64).

Os dois ficam no ambiente Python do nvim e são instalados pelo `install.sh`.

## Sugestões com IA (minuet)

O minuet usa o CLI Proxy API em `llm.alphaspark.com.br` (compatível com OpenAI), com o modelo
`claude-haiku-5-5`. A chave não fica no repositório: defina-a no `~/.zshrc` ou `~/.bashrc` de cada máquina.

```bash
export CLIPROXY_KEY="sua-chave"
```

Sem essa variável, o minuet não dispara. Atalhos no modo insert:

| Atalho | Ação |
|---|---|
| `Alt+Shift+a` | Aceita a sugestão inteira |
| `Alt+a` | Aceita só a próxima linha |
| `Alt+]` / `Alt+[` | Próxima / anterior (também pede uma sugestão) |
| `Alt+e` | Descarta |

No Mac, o Option esquerdo precisa funcionar como Alt; no Ghostty, use `macos-option-as-alt = left`.
`<leader>tm` liga e desliga as sugestões automáticas, e `:Minuet change_model` troca o modelo.

## Onde fica cada coisa

| Arquivo | O que tem |
|---|---|
| `init.lua` | Base do kickstart: opções, LSP, autocomplete, formatação, treesitter |
| `lua/custom/options.lua` | Minhas opções |
| `lua/custom/keymaps.lua` | Meus atalhos |
| `lua/custom/plugins/*.lua` | Plugins extras; qualquer arquivo novo aqui é carregado sozinho |
| `lua/custom/plugins/norminette.lua` | Norma da 42 em C: tabs, norminette e `.h` como C |
| `nvim-pack-lock.json` | Versão exata de cada plugin (mantém as máquinas iguais) |
| `install.sh` | Instalador para macOS e Linux |

## Atualizar plugins

Dentro do nvim: `:lua vim.pack.update()`. Depois faça commit do `nvim-pack-lock.json`.
