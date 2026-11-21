-- Norma da 42 para arquivos C (.c e .h): indentação com tab de 4 colunas, limite de 80 colunas
-- e os erros da `norminette` como diagnósticos (sublinhado + mensagem, como os do LSP).
--
-- A norminette confere todos os limites da norma: 25 linhas por função, 4 parâmetros,
-- 5 variáveis, 5 funções por arquivo, linhas vazias e espaços consecutivos, entre outros.
-- Ela roda ao abrir e ao salvar o arquivo. `<leader>tN` liga e desliga.
--
-- Ao salvar, o código C é formatado pelo c_formatter_42 (configurado no conform, em init.lua).
-- Os dois programas ficam no ambiente Python do nvim, instalados pelo install.sh.

-- Arquivos .h são C, não C++ (o padrão do Neovim é tratá-los como C++).
vim.g.c_syntax_for_h = true

local venv_bin = vim.fn.stdpath 'data' .. '/python-venv/bin/'
local function tool(name)
  if vim.fn.executable(venv_bin .. name) == 1 then return venv_bin .. name end
  if vim.fn.executable(name) == 1 then return name end
end

vim.api.nvim_create_autocmd('FileType', {
  desc = 'Indentação da norma da 42 em C',
  group = vim.api.nvim_create_augroup('custom-norm-indent', { clear = true }),
  pattern = 'c',
  callback = function()
    vim.bo.expandtab = false -- a norma exige tabs; espaços consecutivos são erro
    vim.bo.tabstop = 4
    vim.bo.shiftwidth = 4
    vim.bo.softtabstop = 4
  end,
})

local ns = vim.api.nvim_create_namespace 'norminette'
local enabled = true

-- A norminette conta a coluna na tela (tab = 4); o diagnóstico precisa do byte na linha.
local function byte_col(line, screen_col)
  local col = 1
  for i = 1, #line do
    if col >= screen_col then return i - 1 end
    col = line:sub(i, i) == '\t' and (math.floor((col - 1) / 4) + 1) * 4 + 1 or col + 1
  end
  return #line
end

local function lint(bufnr)
  local file = vim.api.nvim_buf_get_name(bufnr)
  local cmd = tool 'norminette'
  if not enabled or not cmd or file == '' or vim.bo[bufnr].buftype ~= '' then return end
  vim.system({ cmd, vim.fn.fnamemodify(file, ':t') }, { cwd = vim.fn.fnamemodify(file, ':h'), text = true }, function(out)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then return end
      local diagnostics = {}
      for raw in (out.stdout or ''):gmatch '[^\n]+' do
        local text = raw:gsub('\27%[[%d;]*m', '')
        local kind, code, lnum, col, msg = text:match '^(%a+):%s+([%w_]+)%s+%(line:%s*(%d+), col:%s*(%d+)%):%s*(.*)$'
        if kind then
          lnum = tonumber(lnum) - 1
          local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1] or ''
          table.insert(diagnostics, {
            lnum = lnum,
            col = byte_col(line, tonumber(col)),
            severity = kind == 'Error' and vim.diagnostic.severity.ERROR or vim.diagnostic.severity.WARN,
            source = 'norminette',
            code = code,
            message = msg,
          })
        end
      end
      vim.diagnostic.set(ns, bufnr, diagnostics)
    end)
  end)
end

local group = vim.api.nvim_create_augroup('custom-norminette', { clear = true })
vim.api.nvim_create_autocmd('FileType', {
  desc = 'Roda a norminette ao abrir',
  group = group,
  pattern = 'c',
  callback = function(ev) lint(ev.buf) end,
})
vim.api.nvim_create_autocmd('BufWritePost', {
  desc = 'Roda a norminette ao salvar',
  group = group,
  callback = function(ev)
    if vim.bo[ev.buf].filetype == 'c' then lint(ev.buf) end
  end,
})

vim.keymap.set('n', '<leader>tN', function()
  enabled = not enabled
  if enabled then
    lint(0)
  else
    vim.diagnostic.reset(ns)
  end
  vim.notify('norminette ' .. (enabled and 'ligada' or 'desligada'))
end, { desc = '[T]oggle [N]orminette' })
