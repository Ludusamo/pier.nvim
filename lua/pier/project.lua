local config = require("pier.config")

local M = {}

local function starts_with_alnum(s)
  return s:match("^[A-Za-z0-9]") ~= nil
end

local function ends_with_alnum(s)
  return s:match("[A-Za-z0-9]$") ~= nil
end

function M.sanitize_name(name)
  local sanitized = tostring(name or "repo"):gsub("[^A-Za-z0-9._-]", "-")
  sanitized = sanitized:gsub("^[^A-Za-z0-9]+", "")
  sanitized = sanitized:gsub("[^A-Za-z0-9]+$", "")
  if sanitized == "" then
    sanitized = "repo"
  end
  if not starts_with_alnum(sanitized) then
    sanitized = "r" .. sanitized
  end
  if not ends_with_alnum(sanitized) then
    sanitized = sanitized .. "r"
  end
  return sanitized
end

function M.hash_root(root)
  return vim.fn.sha256(vim.fn.fnamemodify(root, ":p")):sub(1, 8)
end

function M.session_id(root, branch)
  local base = vim.fn.fnamemodify(root, ":t")
  if not branch or branch == "" then
    return string.format("nvim-%s-%s", M.sanitize_name(base), M.hash_root(root))
  end
  local hash = vim.fn.sha256(vim.fn.fnamemodify(root, ":p") .. "\0" .. branch):sub(1, 8)
  local short_branch = M.sanitize_name(branch):sub(1, 32)
  return string.format("nvim-%s-%s-%s", M.sanitize_name(base), M.sanitize_name(short_branch), hash)
end

local GIT_TIMEOUT_MS = 2000

function M.git_branch(root)
  local ok, result = pcall(function()
    return vim.system({ "git", "-C", root, "symbolic-ref", "--quiet", "--short", "HEAD" }, { text = true }):wait(GIT_TIMEOUT_MS)
  end)
  if not ok or result.code ~= 0 or not result.stdout then
    return nil
  end
  local branch = vim.trim(result.stdout)
  if branch == "" then
    return nil
  end
  return branch
end

local function overrides_path()
  return config.options.cache_dir .. "/session-overrides.json"
end

-- Returns the overrides table, or nil plus an error when the file exists but is unreadable or corrupt.
local function read_overrides()
  local f = io.open(overrides_path(), "r")
  if not f then
    return {}
  end
  local text = f:read("*a")
  f:close()
  if vim.trim(text or "") == "" then
    return {}
  end
  local ok, data = pcall(vim.json.decode, text)
  if ok and type(data) == "table" then
    return data
  end
  return nil, "corrupt session override file " .. overrides_path() .. " (fix or delete it)"
end

-- Atomic write: temp file in the same directory, then rename over the target.
local function write_overrides(data)
  local path = overrides_path()
  local tmp = string.format("%s.%d.tmp", path, vim.uv.hrtime() % 0x100000000)
  local ok, err = pcall(function()
    vim.fn.mkdir(config.options.cache_dir, "p")
    local f = assert(io.open(tmp, "w"))
    local wrote, werr = f:write(vim.json.encode(data))
    local closed, cerr = f:close()
    if not wrote or not closed then
      error(tostring(werr or cerr))
    end
    assert(vim.uv.fs_rename(tmp, path))
  end)
  if not ok then
    pcall(os.remove, tmp)
    return nil, "failed to write session override: " .. tostring(err)
  end
  return true
end

local function new_suffix()
  return string.format("%s%04x", os.date("!%Y%m%d%H%M%S"), vim.uv.hrtime() % 0x10000)
end

-- Durable per-scope override: a fresh suffix makes pi start a new session id.
-- The scope is the given root and branch (nil branch means detached HEAD), not the current checkout.
-- Returns the new id, or nil plus an error message.
function M.new_session_override(root, branch)
  local key = M.session_id(root, branch)
  local overrides, err = read_overrides()
  if not overrides then
    return nil, err
  end
  overrides[key] = new_suffix()
  local ok, werr = write_overrides(overrides)
  if not ok then
    return nil, werr
  end
  return key .. "-" .. overrides[key]
end

local function git_root_from_cmd(path)
  local result = vim.system({ "git", "-C", path, "rev-parse", "--show-toplevel" }, { text = true }):wait(GIT_TIMEOUT_MS)
  if result.code == 0 and result.stdout then
    local root = vim.trim(result.stdout)
    if root ~= "" then
      return root
    end
  end
end

function M.find_root(path)
  path = path or vim.fn.getcwd()
  local root
  if vim.fs and vim.fs.root then
    root = vim.fs.root(path, ".git")
  end
  root = root or git_root_from_cmd(path)
  return root or vim.fn.getcwd()
end

-- Session info for an explicit root and branch scope.
function M.scope_info(root, branch)
  local id = M.session_id(root, branch)
  local suffix = (read_overrides() or {})[id]
  if suffix then
    id = id .. "-" .. suffix
  end
  local dir = config.options.cache_dir .. "/" .. id
  vim.fn.mkdir(dir, "p")
  return {
    root = root,
    branch = branch,
    id = id,
    cache_dir = dir,
    rendered_log = dir .. "/rendered.log",
    raw_log = dir .. "/raw.jsonl",
    stderr_log = dir .. "/stderr.log",
  }
end

function M.info(path)
  local root = M.find_root(path)
  return M.scope_info(root, M.git_branch(root))
end

return M
