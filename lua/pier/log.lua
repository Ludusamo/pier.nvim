local M = {}

local Log = {}
Log.__index = Log

local function open(path)
  local handle, err = io.open(path, "a")
  if not handle then
    vim.schedule(function()
      vim.notify("pier.nvim: failed to open log " .. path .. ": " .. tostring(err), vim.log.levels.ERROR)
    end)
  end
  return handle
end

function M.new(info)
  return setmetatable({
    rendered = open(info.rendered_log),
    raw = open(info.raw_log),
    stderr = open(info.stderr_log),
  }, Log)
end

local function write(handle, text)
  if not handle or not text or text == "" then
    return
  end
  handle:write(text)
  handle:flush()
end

function Log:raw_line(line)
  write(self.raw, line .. "\n")
end

function Log:stderr_text(text)
  write(self.stderr, text)
end

function Log:rendered_text(text)
  write(self.rendered, text)
end

function Log:close()
  for _, handle in pairs({ self.rendered, self.raw, self.stderr }) do
    if handle then
      pcall(function()
        handle:close()
      end)
    end
  end
end

return M
