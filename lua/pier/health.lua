local M = {}

local function ok(msg)
  vim.health.ok(msg)
end

local function warn(msg)
  vim.health.warn(msg)
end

local function error_(msg)
  vim.health.error(msg)
end

function M.check()
  vim.health.start("pier.nvim")

  if vim.fn.executable("pi") == 1 then
    ok("pi is on PATH")
  else
    error_("pi is not on PATH")
  end

  if vim.fn.executable("git") == 1 then
    ok("git is on PATH")
  else
    warn("git is not on PATH, root detection falls back to cwd")
  end

  local help = vim.system({ "pi", "--help" }, { text = true }):wait()
  local text = (help.stdout or "") .. (help.stderr or "")
  if text:find("%-%-mode") then
    ok("pi advertises --mode")
  else
    warn("could not confirm pi --mode support from help output")
  end
  if text:find("%-%-session%-id") then
    ok("pi advertises --session-id")
  else
    warn("could not confirm pi --session-id support from help output")
  end

  if vim.fn.executable("tmux") == 1 then
    ok("tmux is available")
  else
    warn("tmux is optional and not on PATH")
  end
end

return M
