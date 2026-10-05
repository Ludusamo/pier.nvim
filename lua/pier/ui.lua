local config = require("pier.config")

local M = {}
local buffers = {}

local function valid(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

function M.buffer(session)
  local buf = buffers[session.id]
  if valid(buf) then
    return buf
  end

  buf = vim.api.nvim_create_buf(false, true)
  buffers[session.id] = buf
  vim.api.nvim_buf_set_name(buf, "pier://" .. session.id)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  return buf
end

local function win_at_end(win, buf)
  if not vim.api.nvim_win_is_valid(win) then
    return false
  end
  local cursor = vim.api.nvim_win_get_cursor(win)
  return cursor[1] >= vim.api.nvim_buf_line_count(buf)
end

function M.append(session, text)
  if not text or text == "" then
    return
  end
  local buf = M.buffer(session)
  local watching = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf and win_at_end(win, buf) then
      table.insert(watching, win)
    end
  end

  local lines = vim.split(text, "\n", { plain = true })
  local last = vim.api.nvim_buf_line_count(buf)
  local current = vim.api.nvim_buf_get_lines(buf, last - 1, last, false)[1] or ""
  lines[1] = current .. lines[1]
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, last - 1, last, false, lines)
  vim.bo[buf].modifiable = false

  for _, win in ipairs(watching) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
    end
  end
end

function M.open(session, opts)
  opts = opts or {}
  local focus = opts.focus ~= false
  local buf = M.buffer(session)
  local current_win = vim.api.nvim_get_current_win()
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    if focus then
      vim.api.nvim_set_current_win(win)
    end
    return buf
  end
  vim.cmd(config.options.window.split .. " " .. tostring(config.options.window.height) .. "split")
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(buf), 0 })
  if not focus and vim.api.nvim_win_is_valid(current_win) then
    vim.api.nvim_set_current_win(current_win)
  end
  return buf
end

-- Show new_session's buffer in every window currently showing old_session's buffer.
function M.replace(old_session, new_session)
  local old = buffers[old_session.id]
  if not valid(old) then
    return
  end
  local new = M.buffer(new_session)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == old then
      vim.api.nvim_win_set_buf(win, new)
      vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(new), 0 })
    end
  end
end

function M.toggle(session)
  local buf = M.buffer(session)
  local closed = false
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      vim.api.nvim_win_close(win, false)
      closed = true
    end
  end
  if closed then
    return buf
  end
  return M.open(session)
end

return M
