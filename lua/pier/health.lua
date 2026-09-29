local config = require("pier.config")

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

  local cmd = config.options.cmd or "pi"
  local pi_available = vim.fn.executable(cmd) == 1
  if pi_available then
    ok(cmd .. " is on PATH")
  else
    error_(cmd .. " is not on PATH")
  end

  if vim.fn.executable("git") == 1 then
    ok("git is on PATH")
  else
    warn("git is not on PATH, root detection falls back to cwd")
  end

  if pi_available then
    local ok_system, help = pcall(function()
      return vim.system({ cmd, "--help" }, { text = true }):wait()
    end)
    local text = ok_system and ((help.stdout or "") .. (help.stderr or "")) or ""
    if text:find("%-%-mode") then
      ok(cmd .. " advertises --mode")
    else
      warn("could not confirm " .. cmd .. " --mode support from help output")
    end
    if text:find("%-%-session%-id") then
      ok(cmd .. " advertises --session-id")
    else
      warn("could not confirm " .. cmd .. " --session-id support from help output")
    end
  end

  if vim.fn.executable("tmux") == 1 then
    ok("tmux is available")
  else
    warn("tmux is optional and not on PATH")
  end
end

return M
