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

function M.session_id(root)
  local base = vim.fn.fnamemodify(root, ":t")
  return string.format("nvim-%s-%s", M.sanitize_name(base), M.hash_root(root))
end

local function git_root_from_cmd(path)
  local result = vim.system({ "git", "-C", path, "rev-parse", "--show-toplevel" }, { text = true }):wait()
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

function M.info(path)
  local root = M.find_root(path)
  local id = M.session_id(root)
  local dir = config.options.cache_dir .. "/" .. id
  vim.fn.mkdir(dir, "p")
  return {
    root = root,
    id = id,
    cache_dir = dir,
    rendered_log = dir .. "/rendered.log",
    raw_log = dir .. "/raw.jsonl",
    stderr_log = dir .. "/stderr.log",
  }
end

return M
