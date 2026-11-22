-- Opções trazidas da sua config antiga, por cima dos padrões do kickstart.
-- Veja `:help option-list` e `:help 'nome-da-opção'`.

local o = vim.o

o.relativenumber = true -- números relativos (o kickstart já liga `number`)
o.scrolloff = 8
o.sidescrolloff = 8
o.wrap = false -- <leader>lw alterna
o.linebreak = true -- se wrap estiver ligado, quebra em palavras
o.list = false -- não mostrar caracteres invisíveis
o.laststatus = 3 -- uma statusline global
o.showtabline = 2 -- sempre mostra a tabline (lista de buffers do mini.tabline)

-- Limite de 80 colunas: `gq` reformata nesse tamanho e a coluna 81 fica marcada.
-- Ao salvar, quem decide a quebra do código é o formatador (clang-format: 80; ruff: 88).
o.textwidth = 80
o.colorcolumn = '+1'

-- Indentação: 4 espaços por padrão. O guess-indent detecta o estilo de cada arquivo.
o.expandtab = true
o.tabstop = 4
o.shiftwidth = 4
o.softtabstop = 4
o.shiftround = true

-- Nenhum plugin usa Python pelo provider do Neovim (a norminette roda como programa externo).
vim.g.loaded_python3_provider = 0

o.swapfile = false
o.writebackup = false
o.autoread = true

o.ttimeoutlen = 10
o.virtualedit = 'block' -- cursor livre no modo visual em bloco
o.whichwrap = 'b,s,<,>,[,],h,l' -- h/l e setas passam para a linha anterior/seguinte

-- Folds: o treesitter define onde ficam, mas tudo começa aberto.
o.foldlevel = 99
o.foldlevelstart = 99

-- Não continuar comentários automaticamente ao dar <Enter>/o/O.
-- Precisa ser um autocmd porque os ftplugins redefinem `formatoptions` por tipo de arquivo.
vim.api.nvim_create_autocmd('FileType', {
  desc = 'Não continuar comentários em novas linhas',
  group = vim.api.nvim_create_augroup('custom-formatoptions', { clear = true }),
  callback = function() vim.opt_local.formatoptions:remove { 'c', 'r', 'o' } end,
})
