local config = require("pier.config")
local session_mod = require("pier.session")
local context = require("pier.context")
local tmux = require("pier.tmux")

local M = {}

local function get_prompt(args)
  if args and args ~= "" then
    return args
  end
  return vim.fn.input("Pier: ")
end

function M.setup(opts)
  config.setup(opts)
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("pier-nvim-shutdown", { clear = true }),
    callback = function()
      session_mod.stop_all()
    end,
  })
end

function M.ask(args, opts)
  opts = opts or {}
  local user_prompt = get_prompt(args)
  if not user_prompt or user_prompt == "" then
    return
  end
  local session = session_mod.current()
  local prompt = context.build(user_prompt, {
    root = session.root,
    range = opts.range,
  })
  session:ask(prompt)
end

function M.ask_visual(args, line1, line2)
  M.ask(args, { range = { start_line = line1, end_line = line2 } })
end

function M.abort()
  session_mod.current():abort()
end

function M.open_log()
  session_mod.current():open_log()
end

function M.open_raw_log()
  session_mod.current():open_raw_log()
end

function M.open_tmux_log()
  local session = session_mod.current()
  vim.fn.mkdir(session.info.cache_dir, "p")
  tmux.open(session.info.rendered_log)
end

function M._command_pier(opts)
  if opts.range and opts.range > 0 then
    M.ask_visual(opts.args, opts.line1, opts.line2)
  else
    M.ask(opts.args)
  end
end

return M
