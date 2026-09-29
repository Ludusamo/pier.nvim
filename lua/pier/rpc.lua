local log_mod = require("pier.log")
local config = require("pier.config")

local M = {}

function M.feed_lines(state, chunk)
  state.pending = state.pending or ""
  local text = state.pending .. chunk
  local lines = {}
  local start = 1
  while true do
    local idx = text:find("\n", start, true)
    if not idx then
      break
    end
    local line = text:sub(start, idx - 1)
    if line:sub(-1) == "\r" then
      line = line:sub(1, -2)
    end
    table.insert(lines, line)
    start = idx + 1
  end
  state.pending = text:sub(start)
  return lines
end

local Rpc = {}
Rpc.__index = Rpc

local next_id = 0
local function request_id()
  next_id = next_id + 1
  return "nvim-" .. tostring(next_id)
end

local function data_to_chunks(data)
  if type(data) == "string" then
    return { data }
  end
  if type(data) ~= "table" then
    return {}
  end
  local chunks = {}
  for i, part in ipairs(data) do
    if part ~= "" then
      table.insert(chunks, part)
    end
    if i < #data then
      table.insert(chunks, "\n")
    end
  end
  return chunks
end

function M.start(info, handlers)
  local self = setmetatable({
    info = info,
    handlers = handlers or {},
    pending = {},
    line_state = {},
    log = log_mod.new(info),
  }, Rpc)

  local args = { config.options.cmd, "--mode", "rpc", "--session-id", info.id, "--tools", table.concat(config.options.tools, ",") }
  self.job = vim.fn.jobstart(args, {
    cwd = info.root,
    stdin = "pipe",
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      self:on_stdout(data)
    end,
    on_stderr = function(_, data)
      self:on_stderr(data)
    end,
    on_exit = function(_, code, signal)
      self:on_exit(code, signal)
    end,
  })

  if self.job <= 0 then
    error("pier.nvim: failed to start pi rpc process")
  end

  return self
end

function Rpc:on_stdout(data)
  for _, chunk in ipairs(data_to_chunks(data)) do
    for _, line in ipairs(M.feed_lines(self.line_state, chunk)) do
      self.log:raw_line(line)
      local ok, decoded = pcall(vim.json.decode, line)
      if ok then
        vim.schedule(function()
          self:dispatch(decoded)
        end)
      else
        vim.schedule(function()
          vim.notify("pier.nvim: invalid RPC JSON: " .. line, vim.log.levels.WARN)
        end)
      end
    end
  end
end

function Rpc:on_stderr(data)
  for _, chunk in ipairs(data_to_chunks(data)) do
    self.log:stderr_text(chunk)
  end
end

function Rpc:on_exit(code, signal)
  local msg = string.format("pi rpc exited with code %s signal %s", tostring(code), tostring(signal))
  self.log:stderr_text("\n" .. msg .. "\n")
  if self.stopping then
    self.log:close()
    return
  end
  vim.schedule(function()
    if self.handlers.on_exit then
      self.handlers.on_exit(code, signal)
    end
    vim.notify("pier.nvim: " .. msg, vim.log.levels.WARN)
    self.log:close()
  end)
end

function Rpc:dispatch(record)
  if record.type == "response" and record.id and self.pending[record.id] then
    local cb = self.pending[record.id]
    self.pending[record.id] = nil
    cb(record)
    return
  end
  if record.id and self.pending[record.id] and (record.ok ~= nil or record.error ~= nil) then
    local cb = self.pending[record.id]
    self.pending[record.id] = nil
    cb(record)
    return
  end
  if self.handlers.on_event then
    self.handlers.on_event(record)
  end
end

function Rpc:send(record, cb)
  if not self.job or self.job <= 0 then
    return nil, "process is not running"
  end
  if not record.id then
    record.id = request_id()
  end
  if cb then
    self.pending[record.id] = cb
  end
  local line = vim.json.encode(record) .. "\n"
  local ok, err = pcall(vim.fn.chansend, self.job, line)
  if not ok then
    self.pending[record.id] = nil
    return nil, tostring(err)
  end
  return record.id
end

function Rpc:prompt(text, cb)
  return self:send({ type = "prompt", id = request_id(), message = text }, cb)
end

function Rpc:abort(cb)
  return self:send({ type = "abort", id = request_id() }, cb)
end

function Rpc:get_state(cb)
  return self:send({ type = "get_state", id = request_id() }, cb)
end

function Rpc:cancel_ui(event)
  self:send({ type = "extension_ui_response", id = event.id, cancelled = true })
end

function Rpc:stop()
  if not self.job or self.job <= 0 then
    return
  end
  self.stopping = true
  local job = self.job
  self.job = nil
  pcall(vim.fn.chanclose, job, "stdin")
  vim.defer_fn(function()
    pcall(vim.fn.jobstop, job)
  end, config.options.kill_timeout_ms)
end

return M
