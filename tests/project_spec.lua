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

describe("pier.project branch sessions", function()
  local project = require("pier.project")
  local config = require("pier.config")

  it("scopes ids by branch and keeps the legacy id without one", function()
    local legacy = project.session_id("/tmp/a/repo")
    local main = project.session_id("/tmp/a/repo", "main")
    local feature = project.session_id("/tmp/a/repo", "feature/x")
    assert.are_not.equal(legacy, main)
    assert.are_not.equal(main, feature)
    assert.are.equal(legacy, project.session_id("/tmp/a/repo", nil))
    assert.is_truthy(feature:match("^nvim%-repo%-feature%-x%-%x+$"))
  end)

  it("uses a fresh id after a new session override and keeps the old one distinct", function()
    local dir = vim.fn.tempname()
    local saved = config.options.cache_dir
    config.options.cache_dir = dir
    local repo = vim.fn.tempname()
    vim.fn.mkdir(repo, "p")
    vim.system({ "git", "-C", repo, "init", "-q", "-b", "main" }):wait()
    local before = project.info(repo)
    local overridden = project.new_session_override(repo, "main")
    local after = project.info(repo)
    config.options.cache_dir = saved
    assert.are_not.equal(before.id, after.id)
    assert.are.equal(overridden, after.id)
    assert.is_truthy(after.id:find(before.id, 1, true))
  end)

  it("uses a branch-scoped id on a branch and the legacy id when detached", function()
    local repo = vim.fn.tempname()
    vim.fn.mkdir(repo, "p")
    vim.system({ "git", "-C", repo, "init", "-q", "-b", "feature/x" }):wait()
    vim.system({ "git", "-C", repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "i" }):wait()
    assert.are.equal("feature/x", project.git_branch(repo))
    local on_branch = project.session_id(repo, project.git_branch(repo))
    vim.system({ "git", "-C", repo, "checkout", "-q", "--detach" }):wait()
    assert.is_nil(project.git_branch(repo))
    assert.are_not.equal(on_branch, project.session_id(repo, project.git_branch(repo)))
    assert.are.equal(project.session_id(repo), project.session_id(repo, project.git_branch(repo)))
  end)

  it("reports corrupt override files and leaves them untouched", function()
    local dir = vim.fn.tempname()
    local saved = config.options.cache_dir
    config.options.cache_dir = dir
    vim.fn.mkdir(dir, "p")
    local f = io.open(dir .. "/session-overrides.json", "w")
    f:write("{oops")
    f:close()
    local id, err = project.new_session_override("/tmp/a/repo")
    config.options.cache_dir = saved
    assert.is_nil(id)
    assert.is_truthy(err:find("corrupt"))
    assert.are.equal("{oops", table.concat(vim.fn.readfile(dir .. "/session-overrides.json"), "\n"))
  end)

  it("reports write failures without raising", function()
    local saved = config.options.cache_dir
    local file = vim.fn.tempname()
    vim.fn.writefile({ "x" }, file)
    config.options.cache_dir = file .. "/sub"
    local id, err = project.new_session_override("/tmp/a/repo")
    config.options.cache_dir = saved
    assert.is_nil(id)
    assert.is_truthy(err)
  end)
end)
