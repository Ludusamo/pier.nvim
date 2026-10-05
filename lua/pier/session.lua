local project = require("pier.project")
local rpc_mod = require("pier.rpc")
local render = require("pier.render")
local ui = require("pier.ui")
local locations = require("pier.locations")

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
      self.on_settled = nil
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

function Session:add_locations(new_locations)
  self.locations = self.locations or {}
  self.location_keys = self.location_keys or {}
  for _, loc in ipairs(new_locations or {}) do
    local key = table.concat({ loc.filename or "", loc.lnum or "", loc.col or "" }, "\0")
    if not self.location_keys[key] then
      self.location_keys[key] = true
      table.insert(self.locations, loc)
    end
  end
end

function Session:on_event(event)
  if (event.type or event.event) == "extension_ui_request" and self.rpc then
    self.rpc:cancel_ui(event)
  end

  local typ = event.type or event.event
  if typ == "agent_settled" then
    self.busy = false
    self:add_locations(locations.from_text(self.location_text or "", self.root))
    if self.on_settled then
      local cb = self.on_settled
      self.on_settled = nil
      local ok, err = pcall(cb, self.assistant_text or "")
      if not ok then
        vim.notify("pier.nvim: settled callback failed: " .. tostring(err), vim.log.levels.ERROR)
      end
    end
  end

  if typ ~= "message_update" then
    self:add_locations(locations.from_event(event, self.root))
  end

  if typ == "message_update" and type(event.assistantMessageEvent) == "table" and event.assistantMessageEvent.type == "text_delta" then
    self.assistant_text = (self.assistant_text or "") .. (event.assistantMessageEvent.delta or event.assistantMessageEvent.text_delta or "")
  end

  local text = render.event(event, self.render_state)
  if text and text ~= "" then
    ui.append(self, text)
    if self.rpc and self.rpc.log then
      self.rpc.log:rendered_text(text)
    end
    self.current_text = (self.current_text or "") .. text
    self.location_text = (self.location_text or "") .. text
  end
end

function Session:add_context(block)
  if not block or block == "" then
    return
  end
  self.pending_context = self.pending_context or {}
  table.insert(self.pending_context, block)
end

function Session:pending_context_blocks()
  return vim.deepcopy(self.pending_context or {})
end

function Session:clear_pending_context()
  self.pending_context = {}
end

function Session:ask(prompt, opts)
  opts = opts or {}
  if self.superseded then
    vim.notify("pier.nvim: this session was replaced by :PierNew", vim.log.levels.WARN)
    return false
  end
  if self.busy then
    vim.notify("pier.nvim: pi is busy for this repo", vim.log.levels.WARN)
    return false
  end
  self:ensure_rpc()
  self.busy = true
  self.render_state = render.new_state()
  self.locations = {}
  self.location_keys = {}
  self.location_text = ""
  self.current_text = ""
  self.assistant_text = ""
  self.on_settled = opts.on_settled
  local shown_prompt = prompt:match("User question:\n(.*)") or prompt:gsub("\n.*", "")
  local header = "\n## Pier prompt\n\n" .. shown_prompt .. "\n\n"
  ui.open(self, { focus = false })
  ui.append(self, header)
  self.rpc.log:rendered_text(header)
  local _, err = self.rpc:prompt(prompt, function(response)
    if response.error or response.success == false or response.ok == false then
      self.busy = false
      self.on_settled = nil
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
  self.on_settled = nil
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

function Session:open_locations()
  local items = locations.to_qf(self.locations or {})
  if #items == 0 then
    vim.notify("pier.nvim: no locations captured for this session", vim.log.levels.INFO)
    return false
  end
  vim.fn.setqflist({}, " ", { title = "Pier locations", items = items })
  vim.cmd("copen")
  return true
end

function Session:stop()
  if self.rpc then
    self.rpc:stop()
    self.rpc = nil
  end
end

local function for_info(info)
  local session = sessions[info.id]
  if session then
    if session.superseded then
      -- The override was lost or is unreadable, so this id is the live scope again.
      session.superseded = nil
    end
    return session
  end
  session = setmetatable({
    root = info.root,
    id = info.id,
    info = info,
    busy = false,
    render_state = render.new_state(),
    pending_context = {},
    locations = {},
    location_keys = {},
  }, Session)
  sessions[info.id] = session
  return session
end

function M.for_path(path)
  return for_info(project.info(path))
end

-- Session for an explicit root and branch scope, independent of the current checkout.
function M.for_scope(root, branch)
  return for_info(project.scope_info(root, branch))
end

-- Start a fresh durable pi session for the scope (root and branch) of `old`.
-- Old logs, buffers, and pi sessions are kept on disk.
-- Returns the new session, or nil plus an error message.
function M.new(old)
  if old.busy then
    return nil, "pi is busy for this repo, abort before starting a new session"
  end
  local _, err = project.new_session_override(old.root, old.info.branch)
  if err then
    return nil, err
  end
  old:stop()
  old:clear_pending_context()
  old.superseded = true
  local new = M.for_scope(old.root, old.info.branch)
  ui.replace(old, new)
  return new
end

function M.current()
  local path = vim.api.nvim_buf_get_name(0)
  local session_id = path:match("^pier://(.+)$")
  if session_id then
    for _, session in pairs(sessions) do
      if session.id == session_id then
        if session.superseded then
          return M.for_scope(session.root, session.info.branch)
        end
        return session
      end
    end
    -- Unknown pier:// buffer: fall back to the working directory scope.
    path = vim.fn.getcwd()
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
