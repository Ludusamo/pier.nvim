describe("pier.rpc framing", function()
  local rpc = require("pier.rpc")

  it("splits jsonl across chunks", function()
    local state = {}
    assert.are.same({}, rpc.feed_lines(state, '{"a"'))
    assert.are.same({ '{"a":1}' }, rpc.feed_lines(state, ':1}\n'))
  end)

  it("strips carriage returns", function()
    assert.are.same({ '{"a":1}' }, rpc.feed_lines({}, '{"a":1}\r\n'))
  end)

  it("keeps trailing partial lines", function()
    local state = {}
    assert.are.same({ "one" }, rpc.feed_lines(state, "one\ntwo"))
    assert.are.equal("two", state.pending)
  end)
end)
