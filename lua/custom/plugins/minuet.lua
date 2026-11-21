-- Minuet: sugestões de código com IA em texto cinza, usando o seu
-- CLI Proxy API (compatível com OpenAI) em llm.alphaspark.com.br.
--
-- A chave NÃO fica aqui (o repositório é público): ela é lida da variável de ambiente
-- CLIPROXY_KEY. No ~/.zshrc ou ~/.bashrc de cada máquina:
--   export CLIPROXY_KEY="..."
-- Sem a variável, o minuet simplesmente não dispara.
--
-- Atalhos (modo insert). No Mac, precisam do Option esquerdo como Alt no terminal
-- (no Ghostty: macos-option-as-alt = left):
--   <A-A>  aceitar a sugestão inteira       <A-a>  aceitar só a próxima linha
--   <A-]>  próxima sugestão / pedir uma      <A-[>  sugestão anterior
--   <A-z>  aceitar N linhas                  <A-e>  descartar
-- <leader>tm liga/desliga as sugestões automáticas. Troque o modelo com :Minuet change_model

vim.pack.add { 'https://github.com/milanglacier/minuet-ai.nvim' }

require('minuet').setup {
  provider = 'openai_compatible',
  provider_options = {
    openai_compatible = {
      name = 'CLIProxy',
      end_point = 'https://llm.alphaspark.com.br/v1/chat/completions',
      api_key = 'CLIPROXY_KEY', -- nome da variável de ambiente, não a chave
      model = 'claude-haiku-5-5', -- rápido; modelos maiores deixam a sugestão lenta
      stream = true,
      optional = {
        max_tokens = 256,
        -- Sem isto o modelo "pensa" antes de responder: gasta os 256 tokens no raciocínio
        -- e não devolve código. Com 'none' a sugestão chega em ~2 s.
        reasoning_effort = 'none',
      },
    },
  },
  virtualtext = {
    auto_trigger_ft = { 'c', 'cpp', 'python', 'lua', 'sh', 'make', 'cmake' },
    keymap = {
      accept = '<A-A>',
      accept_line = '<A-a>',
      accept_n_lines = '<A-z>',
      prev = '<A-[>',
      next = '<A-]>',
      dismiss = '<A-e>',
    },
    show_on_completion_menu = false, -- some quando o menu do blink.cmp abre
  },
  n_completions = 1, -- uma sugestão por pedido: mais rápido e gasta menos
  request_timeout = 4,
  debounce = 400,
  throttle = 1000,
  notify = 'warn',
  -- Só dispara se a chave existir nesta máquina
  enable_predicates = {
    function() return vim.env.CLIPROXY_KEY ~= nil and vim.env.CLIPROXY_KEY ~= '' end,
  },
}

vim.keymap.set('n', '<leader>tm', '<cmd>Minuet virtualtext toggle<CR>', { desc = '[T]oggle sugestões do [M]inuet' })
