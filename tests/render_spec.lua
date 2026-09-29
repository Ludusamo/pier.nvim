describe("pier.render", function()
  local render = require("pier.render")

  it("streams assistant text deltas", function()
    local text = render.event({ type = "message_update", assistantMessageEvent = { type = "text_delta", delta = "hi" } }, render.new_state())
    assert.are.equal("hi", text)
  end)

  it("does not stream non-text assistant deltas", function()
    local text = render.event({ type = "message_update", assistantMessageEvent = { type = "thinking_delta", delta = "hidden" } }, render.new_state())
    assert.are.equal("", text)
  end)

  it("renders tool execution starts", function()
    local text = render.event({ type = "tool_execution_start", toolName = "read" }, render.new_state())
    assert.truthy(text:find("read", 1, true))
  end)

  it("renders tool errors", function()
    local text = render.event({ type = "tool_execution_end", toolName = "read", isError = true }, render.new_state())
    assert.truthy(text:find("failed", 1, true))
  end)
end)
