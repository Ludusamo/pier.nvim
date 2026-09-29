local project = require("pier.project")
local rpc_mod = require("pier.rpc")
local render = require("pier.render")
local ui = require("pier.ui")

local M = {}
local sessions = {}

local Session = {}
Session.__index = Session

function Session:start_rpc()
  self.rpc = rpc_mod.start(self.info, {
    on_event = function(event)
      self:on_event(event)
    end,
    on_exit = function()
      local text = "\n[error] pi process exited. The next prompt will restart it.\n"
      if self.rpc and self.rpc.log then
        self.rpc.log:rendered_text(text)
      end
      self.rpc = nil
      self.busy = false
      ui.append(self, text)
    end,
  })
end

function Session:ensure_rpc()
  if not self.rpc then
    self:start_rpc()
  end
end

function Session:on_event(event)
  if (event.type or event.event) == "extension_ui_request" and self.rpc then
    self.rpc:cancel_ui(event)
  end

  if (event.type or event.event) == "agent_settled" then
    self.busy = false
  end

  local text = render.event(event, self.render_state)
  if text and text ~= "" then
    ui.append(self, text)
    if self.rpc and self.rpc.log then
      self.rpc.log:rendered_text(text)
    end
  end
end

function Session:ask(prompt)
  if self.busy then
    vim.notify("pier.nvim: pi is busy for this repo", vim.log.levels.WARN)
    return false
  end
  self:ensure_rpc()
  self.busy = true
  self.render_state = render.new_state()
  local shown_prompt = prompt:match("User question:\n(.*)") or prompt:gsub("\n.*", "")
  local header = "\n## Pier prompt\n\n" .. shown_prompt .. "\n\n"
  ui.open(self, { focus = false })
  ui.append(self, header)
  self.rpc.log:rendered_text(header)
  local _, err = self.rpc:prompt(prompt, function(response)
    if response.error or response.success == false or response.ok == false then
      self.busy = false
      local msg = "\n[error] prompt rejected: " .. tostring(response.error or response.message or "unknown") .. "\n"
      ui.append(self, msg)
      self.rpc.log:rendered_text(msg)
    end
  end)
  if err then
    self.busy = false
    vim.notify("pier.nvim: " .. err, vim.log.levels.ERROR)
    return false
  end
  return true
end

function Session:abort()
  if not self.rpc then
    vim.notify("pier.nvim: no active pi process", vim.log.levels.INFO)
    return
  end
  self.rpc:abort(function(response)
    if response and (response.error or response.success == false or response.ok == false) then
      self.busy = false
    end
  end)
end

function Session:open_log()
  ui.toggle(self)
end

function Session:open_raw_log()
  vim.cmd("split " .. vim.fn.fnameescape(self.info.raw_log))
  vim.bo.autoread = true
  vim.cmd("checktime")
end

function Session:stop()
  if self.rpc then
    self.rpc:stop()
    self.rpc = nil
  end
end

function M.for_path(path)
  local info = project.info(path)
  local session = sessions[info.root]
  if session then
    return session
  end
  session = setmetatable({
    root = info.root,
    id = info.id,
    info = info,
    busy = false,
    render_state = render.new_state(),
  }, Session)
  sessions[info.root] = session
  return session
end

function M.current()
  local path = vim.api.nvim_buf_get_name(0)
  local session_id = path:match("^pier://(.+)$")
  if session_id then
    for _, session in pairs(sessions) do
      if session.id == session_id then
        return session
      end
    end
  end
  if path == "" then
    path = vim.fn.getcwd()
  end
  return M.for_path(path)
end

function M.stop_all()
  for _, session in pairs(sessions) do
    session:stop()
  end
end

return M
