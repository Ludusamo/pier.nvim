describe("pier.review_tour", function()
  local review_tour = require("pier.review_tour")

  local diff = table.concat({
    "diff --git a/a.txt b/a.txt",
    "--- a/a.txt",
    "+++ b/a.txt",
    "@@ -1,2 +1,3 @@",
    " one",
    "+two",
    " three",
    "@@ -20,2 +21,2 @@",
    " x",
    "-y",
    "+z",
    "diff --git a/b.lua b/b.lua",
    "--- a/b.lua",
    "+++ b/b.lua",
    "@@ -0,0 +1 @@",
    "+print(1)",
  }, "\n")

  it("builds anchors from new-side hunk ranges", function()
    local anchors = review_tour.anchors(diff)
    assert.are.equal(3, #anchors)
    assert.are.same({ file = "a.txt", line = 1, end_line = 3 }, anchors[1])
    assert.are.same({ file = "a.txt", line = 21, end_line = 22 }, anchors[2])
    assert.are.same({ file = "b.lua", line = 1, end_line = 1 }, anchors[3])
  end)

  it("uses the last json fence and drops invalid stops", function()
    local anchors = review_tour.anchors(diff)
    local text = table.concat({
      "```json",
      '{"groups":[{"title":"old","stops":[{"file":"a.txt","line":1}]}]}',
      "```",
      "final:",
      "```json",
      '{"groups":[{"title":"G","summary":"s","stops":[',
      '{"file":"a.txt","line":2,"title":"ok"},',
      '{"file":"missing.txt","line":1},',
      '{"file":"a.txt","line":0},',
      '{"file":"a.txt","line":1.5}]},',
      '{"title":"empty","stops":[{"file":"nope","line":1}]}]}',
      "```",
    }, "\n")
    local tour = review_tour.parse(text, anchors)
    assert.is_nil(tour.fallback)
    assert.are.equal(1, #tour.groups)
    assert.are.equal("G", tour.groups[1].title)
    assert.are.equal(1, #tour.groups[1].stops)
  end)

  it("falls back to all hunks when parsing fails", function()
    local anchors = review_tour.anchors(diff)
    for _, text in ipairs({ "no json", "```json\n{bad\n```", '```json\n{"groups":[]}\n```' }) do
      local tour = review_tour.parse(text, anchors)
      assert.is_true(tour.fallback)
      assert.are.equal(3, #tour.groups[1].stops)
    end
  end)

  it("builds quickfix items with headings, stops, and uncovered changes", function()
    local anchors = review_tour.anchors(diff)
    local tour = {
      groups = { { title = "G", summary = "s", stops = { { file = "a.txt", line = 2, title = "t", note = "n" } } } },
    }
    local items = review_tour.to_qf(tour, anchors, "/repo")
    assert.are.equal(5, #items)
    assert.are.equal(0, items[1].valid)
    assert.is_truthy(items[1].text:find("G", 1, true))
    assert.are.equal("/repo/a.txt", items[2].filename)
    assert.are.equal(2, items[2].lnum)
    assert.are.equal("t: n", items[2].text)
    assert.are.equal("Uncovered changes", items[3].text)
    assert.are.equal(21, items[4].lnum)
    assert.are.equal("/repo/b.lua", items[5].filename)
  end)

  it("skips deleted files and rejects stops on them", function()
    local d = table.concat({
      "diff --git a/gone.txt b/gone.txt",
      "deleted file mode 100644",
      "--- a/gone.txt",
      "+++ /dev/null",
      "@@ -1,2 +0,0 @@",
      "-a",
      "-b",
      diff,
    }, "\n")
    local anchors, deleted = review_tour.anchors(d)
    assert.are.equal(3, #anchors)
    assert.are.same({ "gone.txt" }, deleted)
    local tour = review_tour.parse('```json\n{"groups":[{"title":"G","stops":[{"file":"gone.txt","line":1}]}]}\n```', anchors)
    assert.is_true(tour.fallback)
    local items = review_tour.to_qf(tour, anchors, "/repo", deleted)
    local found
    for _, item in ipairs(items) do
      assert.is_nil(item.filename and item.filename:find("gone.txt", 1, true))
      found = found or item.text == "Deleted: gone.txt"
    end
    assert.is_true(found)
  end)

  it("handles paths with spaces and trailing tabs", function()
    local d = table.concat({
      "diff --git a/my file.txt b/my file.txt",
      "--- a/my file.txt\t",
      "+++ b/my file.txt\t",
      "@@ -1 +1,2 @@",
      " x",
      "+y",
    }, "\n")
    local anchors = review_tour.anchors(d)
    assert.are.equal("my file.txt", anchors[1].file)
  end)

  it("clamps anchors for files emptied but not deleted", function()
    local d = table.concat({
      "diff --git a/e.txt b/e.txt",
      "--- a/e.txt",
      "+++ b/e.txt",
      "@@ -1,3 +0,0 @@",
      "-a",
      "-b",
      "-c",
    }, "\n")
    local anchors = review_tour.anchors(d)
    assert.are.same({ file = "e.txt", line = 1, end_line = 1 }, anchors[1])
    local tour = { groups = { { title = "G", stops = { { file = "e.txt", line = 1 } } } } }
    local items = review_tour.to_qf(tour, anchors, "/repo")
    for _, item in ipairs(items) do
      assert.is_nil(item.text:match("^Uncovered"))
    end
  end)

  it("normalizes ./ and b/ stop paths", function()
    local anchors = review_tour.anchors(diff)
    local text = '```json\n{"groups":[{"title":"G","stops":[{"file":"./a.txt","line":1},{"file":"b/b.lua","line":1}]}]}\n```'
    local tour = review_tour.parse(text, anchors)
    assert.are.equal("a.txt", tour.groups[1].stops[1].file)
    assert.are.equal("b.lua", tour.groups[1].stops[2].file)
  end)

  it("tolerates null and non-string fields", function()
    local anchors = review_tour.anchors(diff)
    local text = '```json\n{"groups":[{"title":null,"summary":null,"stops":[{"file":"a.txt","line":1,"title":null,"note":null},{"file":null,"line":1},{"file":"a.txt","line":null}]},{"title":5,"stops":null}]}\n```'
    local tour = review_tour.parse(text, anchors)
    assert.is_nil(tour.fallback)
    assert.are.equal(1, #tour.groups)
    assert.are.equal("Group 1", tour.groups[1].title)
    assert.are.equal(1, #tour.groups[1].stops)
    local items = review_tour.to_qf(tour, anchors, "/repo")
    assert.are.equal("a.txt", items[2].text)
  end)
end)
