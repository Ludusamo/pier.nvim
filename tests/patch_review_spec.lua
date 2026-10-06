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

  describe("previous", function()
    local diff = table.concat({
      "```diff",
      "diff --git a/a.txt b/a.txt",
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

    after_each(function()
      patch_review.close()
    end)

    it("goes back one hunk in review mode", function()
      patch_review.start(".", diff, { mode = "review" })
      patch_review.accept()
      assert.is_true(patch_review.previous())
      assert.is_truthy(patch_review.current_block():find("deux", 1, true))
    end)

    it("goes back from complete state to the last hunk", function()
      patch_review.start(".", diff, { mode = "review" })
      patch_review.accept()
      patch_review.accept()
      assert.is_nil(patch_review.current_block())
      assert.is_true(patch_review.previous())
      assert.is_truthy(patch_review.current_block():find("six!", 1, true))
    end)

    it("returns false from the first hunk", function()
      patch_review.start(".", diff, { mode = "review" })
      assert.is_false(patch_review.previous())
    end)

    local function has_p_map()
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
        if m.lhs == "p" then
          return true
        end
      end
      return false
    end

    it("maps p only in review mode", function()
      patch_review.start(".", diff, { mode = "review" })
      assert.is_true(has_p_map())
      patch_review.close()
      patch_review.start(".", diff, { mode = "apply" })
      assert.is_false(has_p_map())
    end)

    it("is unavailable in apply mode", function()
      patch_review.start(".", diff, { mode = "apply" })
      patch_review.reject()
      assert.is_false(patch_review.previous())
    end)
  end)

  it("returns no hunks when no diff is present", function()
    assert.are.same({}, patch_review.parse("no patch here"))
  end)
end)
