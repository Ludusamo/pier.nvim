local config = require("pier.config")
local session_mod = require("pier.session")
local context = require("pier.context")
local snippet = require("pier.snippet")
local patch_review = require("pier.patch_review")
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

local function build_extra(session, extra)
  local blocks = session:pending_context_blocks()
  for _, block in ipairs(extra or {}) do
    table.insert(blocks, block)
  end
  return blocks
end

local function ask_with_extra(args, extra, opts)
  opts = opts or {}
  local user_prompt = opts.prompt or get_prompt(args)
  if not user_prompt or user_prompt == "" then
    return false
  end
  local session = opts.session or session_mod.current()
  local prompt = context.build(user_prompt, {
    root = session.root,
    range = opts.range,
    extra_context = build_extra(session, extra),
  })
  local ok = session:ask(prompt, { on_settled = opts.on_settled })
  if ok then
    session:clear_pending_context()
  end
  return ok
end

function M.ask(args, opts)
  return ask_with_extra(args, nil, opts)
end

function M.ask_visual(args, line1, line2)
  return M.ask(args, { range = { start_line = line1, end_line = line2 } })
end

function M.ask_hunk(args)
  local session = session_mod.current()
  local block, err = context.hunk_block(session.root, vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_cursor(0)[1])
  if not block then
    vim.notify("pier.nvim: " .. tostring(err), vim.log.levels.WARN)
    return false
  end
  return ask_with_extra(args, { block })
end

function M.ask_snippet(args)
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local user_prompt = get_prompt(args)
  if not user_prompt or user_prompt == "" then
    return false
  end
  local prompt = table.concat({
    user_prompt,
    "",
    "Return the requested code snippet as one fenced code block.",
    "Do not apply edits.",
    "Do not include commentary outside the code block unless it is essential.",
  }, "\n")
  return ask_with_extra(nil, nil, {
    prompt = prompt,
    on_settled = function(text)
      snippet.preview(buf, line, text)
    end,
  })
end

function M.accept_snippet()
  return snippet.accept()
end

function M.reject_snippet()
  return snippet.reject()
end

function M.ask_change(args)
  local session = session_mod.current()
  local user_prompt = get_prompt(args)
  if not user_prompt or user_prompt == "" then
    return false
  end
  local prompt = table.concat({
    user_prompt,
    "",
    "Make the requested change as a unified diff only.",
    "Do not apply edits directly.",
    "Return one diff that can be applied with git apply.",
    "Use normal file headers and hunk headers so each hunk can be reviewed independently.",
    "Do not include commentary outside the diff unless the change cannot be represented as a patch.",
  }, "\n")
  return ask_with_extra(nil, nil, {
    prompt = prompt,
    on_settled = function(text)
      patch_review.start(session.root, text)
    end,
  })
end

function M.accept_patch_hunk()
  return patch_review.accept()
end

function M.reject_patch_hunk()
  return patch_review.reject()
end

function M.close_patch_review()
  return patch_review.close()
end

local function git_output(command)
  local result = vim.system(command, { text = true }):wait()
  if result.code ~= 0 then
    return nil, vim.trim(result.stderr or result.stdout or "git command failed")
  end
  return result.stdout or ""
end

local function default_review_base(root)
  local branches = { "main", "origin/main", "master", "origin/master" }
  for _, branch in ipairs(branches) do
    local ok = git_output({ "git", "-C", root, "rev-parse", "--verify", branch })
    if ok then
      return branch
    end
  end
  return "main"
end

function M.review_branch(args)
  local session = session_mod.current()
  local base = args and args ~= "" and args or default_review_base(session.root)
  local diff, err = git_output({ "git", "-C", session.root, "diff", "--no-ext-diff", "--no-color", "--unified=3", base .. "...HEAD" })
  if not diff then
    vim.notify("pier.nvim: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  if diff == "" then
    vim.notify("pier.nvim: no diff found against " .. base, vim.log.levels.INFO)
    return false
  end
  return patch_review.start(session.root, diff, {
    mode = "review",
    title = "Reviewing current branch against " .. base,
  })
end

function M.ask_patch_hunk(args)
  local block = patch_review.current_block()
  if not block then
    vim.notify("pier.nvim: no pending patch hunk", vim.log.levels.INFO)
    return false
  end
  local root = patch_review.current_root()
  local session = root and session_mod.for_path(root) or nil
  return ask_with_extra(args, { block }, { session = session })
end

function M.ask_diagnostics(args, opts)
  opts = opts or {}
  local session = session_mod.current()
  local buf = vim.api.nvim_get_current_buf()
  local start_line = opts.range and opts.range.start_line or 1
  local end_line = opts.range and opts.range.end_line or vim.api.nvim_buf_line_count(buf)
  local block, err = context.diagnostics_block(session.root, buf, start_line, end_line)
  if not block then
    vim.notify("pier.nvim: " .. tostring(err), vim.log.levels.WARN)
    return false
  end
  return ask_with_extra(args, { block }, { range = opts.range })
end

function M.add(args, opts)
  opts = opts or {}
  local session = session_mod.current()
  local block
  if opts.range then
    block = context.range_block(vim.api.nvim_get_current_buf(), session.root, opts.range.start_line, opts.range.end_line, "User-added selection")
    if args and args ~= "" then
      block = block .. "\n\n" .. context.note_block(args)
    end
  elseif args and args ~= "" then
    block = context.note_block(args)
  else
    block = context.nearby_block(vim.api.nvim_get_current_buf(), session.root)
  end
  session:add_context(block)
  vim.notify("pier.nvim: added context to next prompt", vim.log.levels.INFO)
  return true
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

function M.open_locations()
  session_mod.current():open_locations()
end

function M._command_pier(opts)
  if opts.range and opts.range > 0 then
    M.ask_visual(opts.args, opts.line1, opts.line2)
  else
    M.ask(opts.args)
  end
end

function M._command_diag(opts)
  local range = nil
  if opts.range and opts.range > 0 then
    range = { start_line = opts.line1, end_line = opts.line2 }
  end
  M.ask_diagnostics(opts.args, { range = range })
end

function M._command_add(opts)
  local range = nil
  if opts.range and opts.range > 0 then
    range = { start_line = opts.line1, end_line = opts.line2 }
  end
  M.add(opts.args, { range = range })
end

return M
