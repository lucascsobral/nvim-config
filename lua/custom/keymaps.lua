-- Atalhos trazidos da sua config antiga (ajustados para não colidir com o kickstart).
-- Liste tudo com <leader>sk, ou aperte <leader> e espere o which-key.

local map = function(mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { silent = true, desc = desc }) end

-- Salvar
map('n', '<C-s>', '<cmd>w<CR>', 'Salvar arquivo')
map('n', '<leader>W', '<cmd>noautocmd w<CR>', 'Salvar sem formatar')

-- Edição
map('n', 'x', '"_x', 'Apagar caractere sem copiar')
map('v', 'p', '"_dP', 'Colar sem perder o que foi copiado')
map('v', '<', '<gv', 'Indentar à esquerda e manter seleção')
map('v', '>', '>gv', 'Indentar à direita e manter seleção')

-- Rolagem centralizada
map('n', '<C-d>', '<C-d>zz', 'Meia página para baixo (centralizado)')
map('n', '<C-u>', '<C-u>zz', 'Meia página para cima (centralizado)')

-- Buffers (aparecem na tabline do topo)
map('n', '<Tab>', '<cmd>bnext<CR>', 'Próximo buffer')
map('n', '<S-Tab>', '<cmd>bprevious<CR>', 'Buffer anterior')
map('n', '<leader>x', function() require('mini.bufremove').delete(0, false) end, 'Fechar buffer')
map('n', '<leader>b', '<cmd>enew<CR>', 'Novo buffer')

-- Janelas (<C-h/j/k/l> para navegar já vem do kickstart)
-- Antes eram <leader>v / <leader>h; <leader>h agora é o grupo de git hunks.
map('n', '<leader>wv', '<C-w>v', 'Dividir na vertical')
map('n', '<leader>ws', '<C-w>s', 'Dividir na horizontal')
map('n', '<leader>we', '<C-w>=', 'Igualar tamanhos')
map('n', '<leader>wx', '<cmd>close<CR>', 'Fechar janela')
map('n', '<C-Up>', '<cmd>resize -2<CR>', 'Diminuir altura')
map('n', '<C-Down>', '<cmd>resize +2<CR>', 'Aumentar altura')
map('n', '<C-Left>', '<cmd>vertical resize -2<CR>', 'Diminuir largura')
map('n', '<C-Right>', '<cmd>vertical resize +2<CR>', 'Aumentar largura')

-- Abas
map('n', '<leader>to', '<cmd>tabnew<CR>', 'Nova aba')
map('n', '<leader>tx', '<cmd>tabclose<CR>', 'Fechar aba')
map('n', '<leader>tn', '<cmd>tabnext<CR>', 'Próxima aba')
map('n', '<leader>tp', '<cmd>tabprevious<CR>', 'Aba anterior')

-- Diversos
map('n', '<leader>lw', '<cmd>set wrap!<CR>', 'Alternar quebra de linha')
map('n', '<leader>d', vim.diagnostic.open_float, 'Diagnóstico da linha (janela flutuante)')
map('n', '<leader>e', '<cmd>Neotree toggle<CR>', 'Alternar árvore de arquivos')

-- Diagnósticos: [d / ]d já são nativos do Neovim 0.11+, <leader>q vem do kickstart.
