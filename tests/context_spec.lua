describe("pier.context", function()
  it("inlines visual selection with line range", function()
    local context = require("pier.context")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, vim.fn.getcwd() .. "/sample.lua")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "local x = 1", "return x" })
    vim.bo[buf].filetype = "lua"
    local text = context.build("explain", {
      buf = buf,
      root = vim.fn.getcwd(),
      cursor = { 1, 0 },
      range = { start_line = 1, end_line = 2 },
    })
    assert.truthy(text:find("sample.lua:L1%-L2"))
    assert.truthy(text:find("local x = 1", 1, true))
  end)

  it("adds extra context blocks", function()
    local context = require("pier.context")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, vim.fn.getcwd() .. "/extra.lua")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "return true" })
    local text = context.build("explain", {
      buf = buf,
      root = vim.fn.getcwd(),
      cursor = { 1, 0 },
      extra_context = { "extra details" },
    })
    assert.truthy(text:find("Additional context", 1, true))
    assert.truthy(text:find("extra details", 1, true))
  end)

  it("formats diagnostics blocks", function()
    local context = require("pier.context")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, vim.fn.getcwd() .. "/diag.lua")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "local x" })
    local old_get = vim.diagnostic.get
    vim.diagnostic.get = function()
      return { { lnum = 0, col = 6, severity = vim.diagnostic.severity.ERROR, message = "expected =" } }
    end
    local text = context.diagnostics_block(vim.fn.getcwd(), buf, 1, 1)
    vim.diagnostic.get = old_get
    assert.truthy(text:find("expected =", 1, true))
  end)
end)
