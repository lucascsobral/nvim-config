-- GitHub Copilot.
-- Vem DESLIGADO, porque as sugestões em texto cinza agora são do minuet (minuet.lua);
-- com os dois ligados, as sugestões se sobrepõem.
-- <leader>tc liga/desliga o Copilot. Quando ligado, <C-j> no modo insert aceita a sugestão.
-- Na primeira vez que for usar, rode :Copilot setup.

vim.g.copilot_no_tab_map = true
vim.g.copilot_enabled = false
vim.pack.add { 'https://github.com/github/copilot.vim' }

vim.keymap.set('i', '<C-j>', 'copilot#Accept("\\<CR>")', {
  expr = true,
  replace_keycodes = false,
  silent = true,
  desc = 'Copilot: aceitar sugestão',
})

vim.keymap.set('n', '<leader>tc', function()
  if vim.g.copilot_enabled == false or vim.g.copilot_enabled == 0 then
    vim.cmd 'Copilot enable'
    vim.notify 'Copilot ligado'
  else
    vim.cmd 'Copilot disable'
    vim.notify 'Copilot desligado'
  end
end, { desc = '[T]oggle [C]opilot' })
