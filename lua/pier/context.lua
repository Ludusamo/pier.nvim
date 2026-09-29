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

local function selection_text(buf, start_line, end_line)
  local lines = read_lines(buf, start_line, end_line)
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

  table.insert(out, "")
  table.insert(out, "User question:")
  table.insert(out, user_prompt)
  return table.concat(out, "\n")
end

return M
