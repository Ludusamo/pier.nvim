local config = require("pier.config")

local M = {}

local function relpath(path, root)
  local normalized = vim.fn.fnamemodify(path, ":p")
  local prefix = vim.fn.fnamemodify(root, ":p")
  if normalized:sub(1, #prefix) == prefix then
    return normalized:sub(#prefix + 1)
  end
  return path
end

local function fence(ft)
  if ft and ft ~= "" then
    return "```" .. ft
  end
  return "```"
end

local function read_lines(buf, start_line, end_line)
  return vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
end

local function limited_text(lines)
  local max_lines = config.options.context.max_selection_lines
  local truncated = false
  if #lines > max_lines then
    local kept = {}
    for i = 1, max_lines do
      kept[i] = lines[i]
    end
    lines = kept
    truncated = true
  end
  local text = table.concat(lines, "\n")
  local max_bytes = config.options.context.max_selection_bytes
  if #text > max_bytes then
    text = text:sub(1, max_bytes)
    truncated = true
  end
  return text, truncated
end

local function selection_text(buf, start_line, end_line)
  return limited_text(read_lines(buf, start_line, end_line))
end

function M.range_block(buf, root, start_line, end_line, label)
  root = root or vim.fn.getcwd()
  local path = vim.api.nvim_buf_get_name(buf)
  local rel = path ~= "" and relpath(path, root) or "[No Name]"
  local ft = vim.bo[buf].filetype
  local first_line = math.min(start_line, end_line)
  local last_line = math.max(start_line, end_line)
  start_line = first_line
  end_line = last_line
  local text, truncated = selection_text(buf, start_line, end_line)
  local out = {
    string.format("%s from %s:L%d-L%d:", label or "Additional selected text", rel, start_line, end_line),
    fence(ft),
    text,
    "```",
  }
  if truncated then
    table.insert(out, "This context was truncated. Use the read tool if you need more.")
  end
  return table.concat(out, "\n")
end

local function system_output(cmd, opts)
  local ok, result = pcall(function()
    return vim.system(cmd, vim.tbl_extend("force", { text = true }, opts or {})):wait()
  end)
  if not ok then
    return nil, result
  end
  if result.code == 0 then
    return result.stdout or ""
  end
  return nil, result.stderr or result.stdout or "command failed"
end

local function parse_hunks(diff, cursor_line)
  local best
  local current
  for line in (diff .. "\n"):gmatch("(.-)\n") do
    local old_start, old_count, new_start, new_count = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
    if old_start then
      if current then
        table.insert(best, current)
      end
      new_start = tonumber(new_start)
      new_count = tonumber(new_count ~= "" and new_count or "1")
      current = {
        start_line = new_start,
        end_line = math.max(new_start, new_start + new_count - 1),
        lines = { line },
      }
      best = best or {}
    elseif current then
      table.insert(current.lines, line)
    end
  end
  if current and best then
    table.insert(best, current)
  end
  for _, hunk in ipairs(best or {}) do
    if cursor_line >= hunk.start_line and cursor_line <= hunk.end_line then
      return table.concat(hunk.lines, "\n")
    end
  end
  return nil
end

function M.hunk_block(root, buf, cursor_line)
  root = root or vim.fn.getcwd()
  buf = buf or vim.api.nvim_get_current_buf()
  cursor_line = cursor_line or vim.api.nvim_win_get_cursor(0)[1]
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" then
    return nil, "current buffer has no file path"
  end
  local rel = relpath(path, root)
  local unstaged, unstaged_err = system_output({ "git", "-C", root, "diff", "--no-ext-diff", "--no-color", "--unified=3", "--", path })
  local staged, staged_err = system_output({ "git", "-C", root, "diff", "--cached", "--no-ext-diff", "--no-color", "--unified=3", "--", path })
  unstaged = unstaged or ""
  staged = staged or ""
  if unstaged == "" and staged == "" then
    return nil, vim.trim(unstaged_err or staged_err or "no git diff hunk found for current file")
  end
  local hunk = parse_hunks(unstaged, cursor_line) or parse_hunks(staged, cursor_line)
  if not hunk then
    return nil, "cursor is not inside a changed hunk"
  end
  local text, truncated = limited_text(vim.split(hunk, "\n", { plain = true }))
  local out = {
    "Current git hunk from " .. rel .. ":",
    "```diff",
    text,
    "```",
  }
  if vim.bo[buf].modified then
    table.insert(out, "The buffer has unsaved changes, so hunk line numbers may differ from the file on disk.")
  end
  if truncated then
    table.insert(out, "Hunk context was truncated. Use read if you need more context.")
  end
  return table.concat(out, "\n")
end

function M.diagnostics_block(root, buf, start_line, end_line)
  root = root or vim.fn.getcwd()
  buf = buf or vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  local rel = path ~= "" and relpath(path, root) or "[No Name]"
  start_line = start_line or 1
  end_line = end_line or vim.api.nvim_buf_line_count(buf)
  local first_line = math.min(start_line, end_line)
  local last_line = math.max(start_line, end_line)
  start_line = first_line
  end_line = last_line
  local severity = vim.diagnostic.severity
  local names = {
    [severity.ERROR] = "ERROR",
    [severity.WARN] = "WARN",
    [severity.INFO] = "INFO",
    [severity.HINT] = "HINT",
  }
  local out = { string.format("Diagnostics from %s:L%d-L%d:", rel, start_line, end_line) }
  local count = 0
  local diagnostics = vim.diagnostic.get(buf)
  table.sort(diagnostics, function(a, b)
    if a.lnum == b.lnum then
      return (a.col or 0) < (b.col or 0)
    end
    return (a.lnum or 0) < (b.lnum or 0)
  end)
  for _, diag in ipairs(diagnostics) do
    local lnum = (diag.lnum or 0) + 1
    if lnum >= start_line and lnum <= end_line then
      count = count + 1
      local source = diag.source and (" [" .. diag.source .. "]") or ""
      local code = diag.code and (" " .. tostring(diag.code)) or ""
      local message = tostring(diag.message or ""):gsub("\n", " ")
      table.insert(out, string.format("- L%d:%d %s%s%s: %s", lnum, (diag.col or 0) + 1, names[diag.severity] or "DIAG", source, code, message))
      local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1]
      if line and line ~= "" then
        table.insert(out, "  ```")
        table.insert(out, line)
        table.insert(out, "  ```")
      end
    end
  end
  if count == 0 then
    return nil, "no diagnostics found in range"
  end
  return table.concat(out, "\n")
end

function M.nearby_block(buf, root)
  root = root or vim.fn.getcwd()
  buf = buf or vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local total = vim.api.nvim_buf_line_count(buf)
  local radius = math.floor(config.options.context.snippet_lines / 2)
  local start_line = math.max(1, cursor[1] - radius)
  local end_line = math.min(total, cursor[1] + radius)
  return M.range_block(buf, root, start_line, end_line, "Additional nearby snippet")
end

function M.note_block(text)
  if not text or text == "" then
    return nil
  end
  return "User-added context note:\n" .. text
end

function M.build(user_prompt, opts)
  opts = opts or {}
  local buf = opts.buf or vim.api.nvim_get_current_buf()
  local root = opts.root or vim.fn.getcwd()
  local path = vim.api.nvim_buf_get_name(buf)
  local rel = path ~= "" and relpath(path, root) or "[No Name]"
  local ft = vim.bo[buf].filetype
  local cursor = opts.cursor or vim.api.nvim_win_get_cursor(0)
  local dirty = vim.bo[buf].modified and "yes" or "no"

  local out = {
    "You are answering from Neovim via pier.nvim.",
    "Repository root: " .. root,
    "Current file: " .. rel,
    "Filetype: " .. (ft ~= "" and ft or "unknown"),
    "Cursor line: " .. tostring(cursor[1]),
    "Buffer has unsaved changes: " .. dirty,
    "",
  }

  if opts.range then
    local start_line = math.min(opts.range.start_line, opts.range.end_line)
    local end_line = math.max(opts.range.start_line, opts.range.end_line)
    local text, truncated = selection_text(buf, start_line, end_line)
    table.insert(out, string.format("Selected text from %s:L%d-L%d:", rel, start_line, end_line))
    table.insert(out, fence(ft))
    table.insert(out, text)
    table.insert(out, "```")
    if truncated then
      table.insert(out, "Selection was truncated. Use the read tool if you need more context.")
    end
  else
    local total = vim.api.nvim_buf_line_count(buf)
    local radius = math.floor(config.options.context.snippet_lines / 2)
    local start_line = math.max(1, cursor[1] - radius)
    local end_line = math.min(total, cursor[1] + radius)
    local lines = read_lines(buf, start_line, end_line)
    table.insert(out, string.format("Nearby snippet from %s:L%d-L%d:", rel, start_line, end_line))
    table.insert(out, fence(ft))
    table.insert(out, table.concat(lines, "\n"))
    table.insert(out, "```")
    table.insert(out, "Use read if you need the whole file.")
  end

  if opts.extra_context and #opts.extra_context > 0 then
    table.insert(out, "")
    table.insert(out, "Additional context:")
    for i, block in ipairs(opts.extra_context) do
      table.insert(out, "")
      table.insert(out, "Context " .. tostring(i) .. ":")
      table.insert(out, block)
    end
  end

  table.insert(out, "")
  table.insert(out, "User question:")
  table.insert(out, user_prompt)
  return table.concat(out, "\n")
end

return M
