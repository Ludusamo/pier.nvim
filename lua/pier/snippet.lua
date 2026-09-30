local M = {}

local ns = vim.api.nvim_create_namespace("pier-snippet-preview")
local pending = {}
local last_buf

local function trim_blank_edges(lines)
  local first = 1
  local last = #lines
  while first <= last and lines[first]:match("^%s*$") do
    first = first + 1
  end
  while last >= first and lines[last]:match("^%s*$") do
    last = last - 1
  end
  local out = {}
  for i = first, last do
    table.insert(out, lines[i])
  end
  return out
end

function M.extract(text)
  if not text or text == "" then
    return nil
  end
  text = text:gsub("\r\n", "\n")
  local fenced = text:match("```[^\n]*\n(.-)\n```") or text:match("~~~[^\n]*\n(.-)\n~~~")
  if not fenced then
    return nil
  end
  local lines = trim_blank_edges(vim.split(fenced, "\n", { plain = true }))
  if #lines == 0 then
    return nil
  end
  return table.concat(lines, "\n")
end

function M.preview(buf, line, text)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    vim.notify("pier.nvim: snippet target buffer is no longer valid", vim.log.levels.WARN)
    return false
  end
  line = math.min(line or vim.api.nvim_win_get_cursor(0)[1], vim.api.nvim_buf_line_count(buf))
  local snippet = M.extract(text)
  if not snippet then
    vim.notify("pier.nvim: no fenced snippet found in response", vim.log.levels.WARN)
    return false
  end

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local lines = vim.split(snippet, "\n", { plain = true })
  local virt_lines = {
    { { "Pier snippet preview - :PierSnippetAccept or :PierSnippetReject", "Title" } },
  }
  for _, snippet_line in ipairs(lines) do
    table.insert(virt_lines, { { "+ " .. snippet_line, "DiffAdd" } })
  end

  local ok, mark = pcall(vim.api.nvim_buf_set_extmark, buf, ns, math.max(0, line - 1), 0, {
    virt_lines = virt_lines,
    virt_lines_above = false,
  })
  if not ok then
    vim.notify("pier.nvim: failed to preview snippet: " .. tostring(mark), vim.log.levels.ERROR)
    return false
  end

  pending[buf] = {
    line = line,
    lines = lines,
    mark = mark,
  }
  last_buf = buf
  vim.notify("pier.nvim: snippet preview ready", vim.log.levels.INFO)
  return true
end

local function target_buf(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if pending[buf] then
    return buf
  end
  if last_buf and pending[last_buf] then
    return last_buf
  end
  return buf
end

function M.accept(buf)
  buf = target_buf(buf)
  local item = pending[buf]
  if not item then
    vim.notify("pier.nvim: no pending snippet preview", vim.log.levels.INFO)
    return false
  end
  if not vim.api.nvim_buf_is_valid(buf) then
    pending[buf] = nil
    vim.notify("pier.nvim: snippet target buffer is no longer valid", vim.log.levels.WARN)
    return false
  end
  local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, item.mark, {})
  local row = pos and pos[1] or (item.line - 1)
  row = math.min(row + 1, vim.api.nvim_buf_line_count(buf))
  local ok, err = pcall(vim.api.nvim_buf_set_lines, buf, row, row, false, item.lines)
  if not ok then
    vim.notify("pier.nvim: failed to insert snippet: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  pending[buf] = nil
  if last_buf == buf then
    last_buf = nil
  end
  return true
end

function M.reject(buf)
  buf = target_buf(buf)
  if not pending[buf] then
    vim.notify("pier.nvim: no pending snippet preview", vim.log.levels.INFO)
    return false
  end
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
  pending[buf] = nil
  if last_buf == buf then
    last_buf = nil
  end
  return true
end

function M.has_pending(buf)
  return pending[buf or vim.api.nvim_get_current_buf()] ~= nil
end

return M
