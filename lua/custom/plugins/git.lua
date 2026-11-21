-- Git: o gitsigns (sinais na margem, blame, hunks em <leader>h...) já vem do kickstart.
-- Aqui entra o lazygit numa janela flutuante.

vim.pack.add {
  'https://github.com/nvim-lua/plenary.nvim',
  'https://github.com/kdheepak/lazygit.nvim',
}

vim.keymap.set('n', '<leader>gg', '<cmd>LazyGit<CR>', { desc = '[G]it: abrir lazygit' })
vim.keymap.set('n', '<leader>gf', '<cmd>LazyGitCurrentFile<CR>', { desc = '[G]it: lazygit no repo do arquivo' })
vim.keymap.set('n', '<leader>gl', '<cmd>LazyGitLog<CR>', { desc = '[G]it: log de commits' })
vim.keymap.set('n', '<leader>gb', function() require('gitsigns').blame() end, { desc = '[G]it: blame do arquivo' })
