local M = {}

local active = nil

local function split_lines(text)
  return vim.split(text:gsub("\r\n", "\n"), "\n", { plain = true })
end

local function extract_diff(text)
  local fenced = text:match("```diff[ \t]*\n(.-)\n```") or text:match("```patch[ \t]*\n(.-)\n```")
  if fenced then
    return fenced
  end
  local diff_start = text:find("diff %-%-git ") or text:find("^%-%-%- ")
  if diff_start then
    return text:sub(diff_start)
  end
  return nil
end

function M.parse(text)
  local diff = extract_diff(text)
  if not diff then
    return {}
  end

  local hunks = {}
  local file_headers = {}
  local hunk_lines = nil

  local function finish_hunk()
    if hunk_lines and #hunk_lines > 0 then
      table.insert(hunks, {
        headers = vim.deepcopy(file_headers),
        lines = hunk_lines,
      })
    end
    hunk_lines = nil
  end

  for _, line in ipairs(split_lines(diff)) do
    if line:match("^diff %-%-git ") then
      finish_hunk()
      file_headers = { line }
    elseif line:match("^@@") then
      finish_hunk()
      hunk_lines = { line }
    elseif hunk_lines then
      table.insert(hunk_lines, line)
    elseif #file_headers > 0 then
      table.insert(file_headers, line)
    end
  end
  finish_hunk()

  return hunks
end

local function hunk_patch(hunk)
  local lines = {}
  vim.list_extend(lines, hunk.headers)
  vim.list_extend(lines, hunk.lines)
  return table.concat(lines, "\n") .. "\n"
end

local function ensure_window()
  if not active.buf or not vim.api.nvim_buf_is_valid(active.buf) then
    active.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[active.buf].buftype = "nofile"
    vim.bo[active.buf].bufhidden = "wipe"
    vim.bo[active.buf].swapfile = false
    vim.api.nvim_buf_set_name(active.buf, "pier://patch-review")
  end
  if active.win and vim.api.nvim_win_is_valid(active.win) then
    return
  end
  vim.cmd("botright split")
  active.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(active.win, active.buf)
end

local function current_hunk()
  if not active then
    return nil
  end
  return active.hunks[active.index]
end

local function render()
  ensure_window()
  local hunk = current_hunk()
  local lines = {}
  if hunk then
    table.insert(lines, string.format("Pier patch review hunk %d/%d", active.index, #active.hunks))
    if active.title then
      table.insert(lines, active.title)
    end
    table.insert(lines, "")
    if active.mode == "review" then
      table.insert(lines, "Press a or run :PierPatchAccept to mark this hunk reviewed.")
      table.insert(lines, "Press r or run :PierPatchReject to skip this hunk.")
    else
      table.insert(lines, "Press a or run :PierPatchAccept to apply this hunk.")
      table.insert(lines, "Press r or run :PierPatchReject to skip this hunk.")
    end
    table.insert(lines, "Press q or run :PierPatchClose to close the review.")
    table.insert(lines, "")
    vim.list_extend(lines, vim.split(hunk_patch(hunk):gsub("\n$", ""), "\n", { plain = true }))
  else
    table.insert(lines, "Pier patch review complete.")
  end

  vim.bo[active.buf].modifiable = true
  vim.api.nvim_buf_set_lines(active.buf, 0, -1, false, lines)
  vim.bo[active.buf].modifiable = false
  vim.bo[active.buf].filetype = "diff"
end

local function map(lhs, rhs, desc)
  vim.keymap.set("n", lhs, rhs, { buffer = active.buf, nowait = true, desc = desc })
end

local function setup_maps()
  map("a", function()
    M.accept()
  end, "Apply pier patch hunk")
  map("r", function()
    M.reject()
  end, "Reject pier patch hunk")
  map("q", function()
    M.close()
  end, "Close pier patch review")
end

function M.start(root, text, opts)
  opts = opts or {}
  local hunks = M.parse(text)
  if #hunks == 0 then
    vim.notify("pier.nvim: no unified diff found in response", vim.log.levels.WARN)
    return false
  end

  active = {
    root = root,
    hunks = hunks,
    index = 1,
    mode = opts.mode or "apply",
    title = opts.title,
  }
  render()
  setup_maps()
  vim.notify(string.format("pier.nvim: reviewing %d patch hunks", #hunks), vim.log.levels.INFO)
  return true
end

function M.accept()
  local hunk = current_hunk()
  if not hunk then
    vim.notify("pier.nvim: no pending patch hunk", vim.log.levels.INFO)
    return false
  end

  if active.mode ~= "review" then
    local patch = hunk_patch(hunk)
    local tmp = vim.fn.tempname()
    vim.fn.writefile(vim.split(patch, "\n", { plain = true }), tmp)
    local result = vim.system({ "git", "-C", active.root, "apply", "--whitespace=nowarn", tmp }, { text = true }):wait()
    vim.fn.delete(tmp)
    if result.code ~= 0 then
      vim.notify("pier.nvim: failed to apply hunk: " .. vim.trim(result.stderr or result.stdout or "unknown error"), vim.log.levels.ERROR)
      return false
    end
  end

  active.index = active.index + 1
  render()
  if not current_hunk() then
    vim.notify("pier.nvim: patch review complete", vim.log.levels.INFO)
  end
  return true
end

function M.reject()
  local hunk = current_hunk()
  if not hunk then
    vim.notify("pier.nvim: no pending patch hunk", vim.log.levels.INFO)
    return false
  end
  active.index = active.index + 1
  render()
  if not current_hunk() then
    vim.notify("pier.nvim: patch review complete", vim.log.levels.INFO)
  end
  return true
end

function M.close()
  if not active then
    return false
  end
  if active.win and vim.api.nvim_win_is_valid(active.win) then
    vim.api.nvim_win_close(active.win, true)
  end
  active = nil
  return true
end

function M.current_root()
  return active and active.root or nil
end

function M.current_block()
  local hunk = current_hunk()
  if not hunk then
    return nil
  end
  local label = "Pending patch hunk under review:"
  if active.mode == "review" then
    label = "Existing diff hunk under review:"
  end
  return table.concat({
    label,
    "```diff",
    hunk_patch(hunk):gsub("\n$", ""),
    "```",
  }, "\n")
end

return M
