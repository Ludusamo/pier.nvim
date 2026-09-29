describe("pier.project", function()
  local project = require("pier.project")

  it("sanitizes ids to allowed boundary characters", function()
    assert.are.equal("repo", project.sanitize_name("..."))
    assert.are.equal("abc", project.sanitize_name("***abc***"))
    assert.are.equal("a-b_c.d", project.sanitize_name("a b_c.d"))
  end)

  it("hashes roots stably", function()
    assert.are.equal(project.hash_root("/tmp/example"), project.hash_root("/tmp/example"))
  end)

  it("distinguishes same basenames under different roots", function()
    assert.are_not.equal(project.session_id("/tmp/a/repo"), project.session_id("/tmp/b/repo"))
  end)
end)
