-- Jupyter notebooks no Neovim
--
--   jupytext.nvim  abre .ipynb como um arquivo .py com células `# %%` e converte de volta ao salvar
--   molten-nvim    conecta a um kernel Jupyter e mostra a saída abaixo de cada célula
--   image.nvim     desenha gráficos/imagens (só em terminais com protocolo gráfico do Kitty:
--                  Ghostty, WezTerm, Kitty)
--
-- Fluxo básico: abra o .ipynb, <leader>ji para iniciar o kernel, <leader>jr para rodar a célula.
-- O <leader>ji usa o venv do projeto (.venv, venv ou env), se houver; veja "Kernel do venv" abaixo.
-- Ambiente Python do nvim (pynvim, jupyter_client, jupytext, ipykernel, numpy, pandas, matplotlib):
--   ~/.local/share/nvim/python-venv

local venv = vim.fn.stdpath 'data' .. '/python-venv'

-- Provider Python do Neovim (necessário para o molten, que é um plugin remoto em Python)
vim.g.python3_host_prog = venv .. '/bin/python'
-- O jupytext.nvim chama o executável `jupytext`. Vai no fim do PATH para não trocar o `python` do terminal.
vim.env.PATH = vim.env.PATH .. ':' .. venv .. '/bin'

-- O molten precisa registrar seus comandos depois de instalado/atualizado.
-- (Este autocmd tem que existir antes do vim.pack.add.)
vim.api.nvim_create_autocmd('PackChanged', {
  group = vim.api.nvim_create_augroup('custom-molten-build', { clear = true }),
  callback = function(ev)
    if ev.data.spec.name == 'molten-nvim' and (ev.data.kind == 'install' or ev.data.kind == 'update') then
      -- Adiado: não pode rodar enquanto o vim.pack ainda está instalando.
      vim.schedule(function()
        if not ev.data.active then vim.cmd.packadd 'molten-nvim' end
        vim.cmd 'UpdateRemotePlugins'
      end)
    end
  end,
})

-- [[ image.nvim ]] ------------------------------------------------------------
local term = vim.env.TERM_PROGRAM or ''
local supports_images = term == 'ghostty' or term == 'WezTerm' or vim.env.KITTY_WINDOW_ID ~= nil

if supports_images then
  vim.pack.add { 'https://github.com/3rd/image.nvim' }
  require('image').setup {
    backend = 'kitty',
    processor = 'magick_cli', -- usa o `magick` do Homebrew, sem precisar de luarocks
    integrations = {}, -- só imagens vindas do molten, não de markdown
    max_width = 100,
    max_height = 12,
    max_height_window_percentage = math.huge,
    max_width_window_percentage = math.huge,
    window_overlap_clear_enabled = true,
    window_overlap_clear_ft_ignore = { 'cmp_menu', 'cmp_docs', 'blink-cmp-menu', 'blink-cmp-documentation', '' },
  }
end

-- [[ molten-nvim ]] -----------------------------------------------------------
-- Opções precisam ser definidas antes do plugin carregar. Veja `:help molten-config`.
vim.g.molten_image_provider = supports_images and 'image.nvim' or 'none'
vim.g.molten_output_win_max_height = 20
vim.g.molten_auto_open_output = false -- a saída aparece como texto virtual abaixo da célula
vim.g.molten_virt_text_output = true
vim.g.molten_virt_lines_off_by_1 = true -- saída depois do fim da célula (formato do jupytext)
vim.g.molten_wrap_output = true

vim.pack.add { { src = 'https://github.com/benlubas/molten-nvim', version = vim.version.range '1.*' } }

-- [[ jupytext.nvim ]] ---------------------------------------------------------
vim.pack.add { 'https://github.com/GCBallesteros/jupytext.nvim' }
require('jupytext').setup {
  style = 'percent', -- células marcadas com `# %%`
  output_extension = 'auto',
  force_ft = nil,
}

-- [[ Células ]] ---------------------------------------------------------------
local CELL = [[^# %%]]

--- Primeira e última linha da célula onde o cursor está.
local function cell_range()
  local first = vim.fn.search(CELL, 'bcnW')
  local next_marker = vim.fn.search(CELL, 'nW')
  local start_line = first == 0 and 1 or first + 1
  local end_line = next_marker == 0 and vim.fn.line '$' or next_marker - 1
  return start_line, end_line, next_marker
end

local function run_cell(go_next)
  local start_line, end_line, next_marker = cell_range()
  if end_line >= start_line then vim.fn.MoltenEvaluateRange(start_line, end_line) end
  if go_next and next_marker ~= 0 then vim.api.nvim_win_set_cursor(0, { math.min(next_marker + 1, vim.fn.line '$'), 0 }) end
end

local function jump_cell(flags)
  local line = vim.fn.search(CELL, flags .. 'W')
  if line ~= 0 then vim.api.nvim_win_set_cursor(0, { math.min(line + 1, vim.fn.line '$'), 0 }) end
end

-- [[ Kernel do venv do projeto ]] ---------------------------------------------
-- <leader>ji procura um venv do projeto: o ativado no terminal ($VIRTUAL_ENV) ou uma pasta
-- .venv, venv ou env subindo a partir do arquivo. Se achar, instala o ipykernel nele (pergunta
-- antes), registra o kernel com o nome da pasta do projeto e inicia esse kernel.
-- Sem venv, abre a lista de kernels (como <leader>jk).

local function find_project_venv()
  local active = vim.env.VIRTUAL_ENV
  if active and active ~= venv and vim.uv.fs_stat(active .. '/bin/python') then return active end
  local start = vim.fn.expand '%:p:h'
  if start == '' then start = vim.fn.getcwd() end
  for _, dir in ipairs(vim.fs.find({ '.venv', 'venv', 'env' }, { path = start, upward = true, stop = vim.env.HOME, type = 'directory', limit = math.huge })) do
    if vim.uv.fs_stat(dir .. '/bin/python') and vim.uv.fs_stat(dir .. '/pyvenv.cfg') then return dir end
  end
end

local function jupyter_data_dir()
  if vim.env.JUPYTER_DATA_DIR then return vim.env.JUPYTER_DATA_DIR end
  if vim.fn.has 'mac' == 1 then return vim.env.HOME .. '/Library/Jupyter' end
  return (vim.env.XDG_DATA_HOME or (vim.env.HOME .. '/.local/share')) .. '/jupyter'
end
local function jupyter_kernels_dir() return jupyter_data_dir() .. '/kernels' end

-- O molten grava o arquivo de conexão do kernel em <dados do jupyter>/runtime, mas ninguém
-- cria essa pasta. Numa máquina onde o Jupyter nunca rodou, iniciar o kernel falha com
-- "No such file or directory: .../jupyter/runtime/kernel-....json".
vim.fn.mkdir(jupyter_data_dir() .. '/runtime', 'p', tonumber('700', 8))

--- Comando assíncrono; chama on_ok só se der certo, senão mostra o erro.
local function run(cmd, what, on_ok)
  vim.system(cmd, { text = true }, function(out)
    vim.schedule(function()
      if out.code == 0 then
        on_ok()
      else
        vim.notify(what .. ' falhou:\n' .. vim.trim((out.stderr or '') .. (out.stdout or '')), vim.log.levels.ERROR)
      end
    end)
  end)
end

local function init_project_kernel()
  local project_venv = find_project_venv()
  if not project_venv then return vim.cmd 'MoltenInit' end

  local python = project_venv .. '/bin/python'
  local project = vim.fs.basename(vim.fs.dirname(project_venv))
  local name = project:lower():gsub('[^%w%.%-_]', '-')
  local kernel_json = jupyter_kernels_dir() .. '/' .. name .. '/kernel.json'

  local function start() vim.cmd('MoltenInit ' .. name) end

  local function register()
    local ok, spec = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(kernel_json), '\n')) end)
    if ok and spec.argv and spec.argv[1] == python then return start() end
    vim.notify('Registrando o kernel ' .. name .. '...')
    run({ python, '-m', 'ipykernel', 'install', '--user', '--name', name, '--display-name', 'Python (' .. project .. ')' }, 'Registrar o kernel', start)
  end

  if vim.system({ python, '-c', 'import ipykernel' }):wait().code == 0 then return register() end

  local answer = vim.fn.confirm('O venv ' .. project_venv .. ' não tem o ipykernel. Instalar agora?', '&Sim\n&Não', 1)
  if answer ~= 1 then return end
  -- venvs criados pelo uv não têm pip; nesse caso usa o próprio uv.
  local has_pip = vim.system({ python, '-m', 'pip', '--version' }):wait().code == 0
  local cmd = has_pip and { python, '-m', 'pip', 'install', 'ipykernel' } or { 'uv', 'pip', 'install', '--python', python, 'ipykernel' }
  vim.notify 'Instalando o ipykernel no venv do projeto...'
  run(cmd, 'Instalar o ipykernel', register)
end

-- [[ Atalhos ]] ---------------------------------------------------------------
local map = function(mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { silent = true, desc = 'Jupyter: ' .. desc }) end

map('n', '<leader>ji', init_project_kernel, 'iniciar kernel (venv do projeto, se houver)')
map('n', '<leader>jk', '<cmd>MoltenInit<CR>', 'escolher kernel da lista')
map('n', '<leader>jr', function() run_cell(false) end, 'rodar célula')
map('n', '<leader>jn', function() run_cell(true) end, 'rodar célula e ir para a próxima')
map('n', '<leader>jl', '<cmd>MoltenEvaluateLine<CR>', 'rodar linha')
map('x', '<leader>jr', ':<C-u>MoltenEvaluateVisual<CR>gv<Esc>', 'rodar seleção')
map('n', '<leader>jo', '<cmd>noautocmd MoltenEnterOutput<CR>', 'abrir/entrar na saída')
map('n', '<leader>jh', '<cmd>MoltenHideOutput<CR>', 'esconder saída')
map('n', '<leader>jd', '<cmd>MoltenDelete<CR>', 'apagar célula do molten (e sua saída)')
map('n', '<leader>jx', '<cmd>MoltenInterrupt<CR>', 'interromper kernel')
map('n', '<leader>jR', '<cmd>MoltenRestart!<CR>', 'reiniciar kernel (limpa saídas)')
map('n', '<leader>js', '<cmd>MoltenExportOutput!<CR>', 'salvar saídas no .ipynb')
map('n', '<leader>jI', '<cmd>MoltenImportOutput<CR>', 'carregar saídas do .ipynb')
map('n', ']j', function() jump_cell '' end, 'próxima célula')
map('n', '[j', function() jump_cell 'b' end, 'célula anterior')

require('which-key').add { { '<leader>j', group = '[J]upyter', mode = { 'n', 'x' } } }
