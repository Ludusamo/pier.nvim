local M = {}

function M.open(path)
  if not vim.env.TMUX or vim.env.TMUX == "" then
    vim.notify("pier.nvim: not inside tmux", vim.log.levels.ERROR)
    return false
  end
  local cmd = { "tmux", "split-window", "tail", "-n", "+1", "-F", path }
  vim.system(cmd, {}, function(result)
    if result.code ~= 0 then
      vim.schedule(function()
        vim.notify("pier.nvim: tmux split failed: " .. tostring(result.stderr), vim.log.levels.ERROR)
      end)
    end
  end)
  return true
end

return M
