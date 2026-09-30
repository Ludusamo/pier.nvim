describe("pier.patch_review", function()
  local patch_review = require("pier.patch_review")

  it("extracts hunks from a fenced diff", function()
    local text = table.concat({
      "Here is the patch:",
      "```diff",
      "diff --git a/a.txt b/a.txt",
      "index 111..222 100644",
      "--- a/a.txt",
      "+++ b/a.txt",
      "@@ -1,2 +1,2 @@",
      " one",
      "-two",
      "+deux",
      "@@ -5,2 +5,2 @@",
      " five",
      "-six",
      "+six!",
      "```",
    }, "\n")

    local hunks = patch_review.parse(text)

    assert.are.equal(2, #hunks)
    assert.are.equal("diff --git a/a.txt b/a.txt", hunks[1].headers[1])
    assert.are.equal("@@ -1,2 +1,2 @@", hunks[1].lines[1])
    assert.are.equal("@@ -5,2 +5,2 @@", hunks[2].lines[1])
  end)

  it("returns no hunks when no diff is present", function()
    assert.are.same({}, patch_review.parse("no patch here"))
  end)
end)
