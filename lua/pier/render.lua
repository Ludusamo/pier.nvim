local M = {}

local function content_text(event)
  local msg = event.assistantMessageEvent or event.message or event
  if msg.type == "text_delta" then
    return msg.delta or msg.text_delta
  end
  return msg.text_delta or msg.delta or event.text_delta or event.content_delta
end

local function tool_name(event)
  local tool = event.tool or event.tool_call or event.toolCall or {}
  return event.tool_name or event.name or tool.name or tool.tool_name
end

function M.new_state()
  return { started = false }
end

function M.event(event, state)
  state = state or M.new_state()
  local typ = event.type or event.event or event.kind

  if typ == "agent_start" or typ == "agent_started" then
    state.started = true
    return "\n--- pier run started ---\n"
  end

  if typ == "agent_end" then
    return "\n--- agent ended, waiting for settle ---\n"
  end

  if typ == "agent_settled" then
    return "\n--- pier run settled ---\n"
  end

  if typ == "message_update" then
    return content_text(event) or ""
  end

  if typ == "tool_call" or typ == "tool_start" or typ == "tool_use" or typ == "tool_execution_start" then
    return string.format("\n[tool] %s\n", event.toolName or tool_name(event) or "unknown")
  end

  if typ == "tool_result" or typ == "tool_end" or typ == "tool_execution_end" then
    local name = event.toolName or tool_name(event) or "tool"
    local ok = event.ok
    if ok == nil then
      ok = event.success
    end
    local status = ok == false and "failed" or "done"
    return string.format("[tool] %s %s\n", name, status)
  end

  if typ == "error" then
    return "\n[error] " .. tostring(event.message or event.error or "unknown") .. "\n"
  end

  if typ == "aborted" or typ == "abort" then
    return "\n--- pier run aborted ---\n"
  end

  if typ == "extension_ui_request" then
    return "\n[extension-ui] cancelled blocking request\n"
  end

  return ""
end

return M
