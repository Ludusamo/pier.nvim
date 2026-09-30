describe("pier.locations", function()
  local locations = require("pier.locations")

  it("extracts locations from text", function()
    local path = vim.fn.getcwd() .. "/README.md"
    local text = "See README.md:1 for details"
    local found = locations.from_text(text, vim.fn.getcwd())
    assert.are.equal(path, found[1].filename)
    assert.are.equal(1, found[1].lnum)
  end)

  it("extracts nested event locations", function()
    local found = locations.from_event({ data = { locations = { { path = "README.md", line = 1, col = 2, label = "readme" } } } }, vim.fn.getcwd())
    assert.are.equal(1, #found)
    assert.are.equal(2, found[1].col)
  end)

  it("deduplicates by position", function()
    local path = vim.fn.getcwd() .. "/README.md"
    local items = locations.to_qf({
      { filename = path, lnum = 1, col = 1, text = "first" },
      { filename = path, lnum = 1, col = 1, text = "second" },
    })
    assert.are.equal(1, #items)
  end)
end)
