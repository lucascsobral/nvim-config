-- GitHub Copilot (da sua config antiga).
-- <C-j> no modo insert aceita a sugestão; <Tab> fica livre para o autocomplete/snippets.
-- Na primeira vez rode :Copilot setup (se já estava logado antes, continua valendo).

vim.g.copilot_no_tab_map = true
vim.pack.add { 'https://github.com/github/copilot.vim' }

vim.keymap.set('i', '<C-j>', 'copilot#Accept("\\<CR>")', {
  expr = true,
  replace_keycodes = false,
  silent = true,
  desc = 'Copilot: aceitar sugestão',
})
