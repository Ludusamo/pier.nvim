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

function M.open(session)
  local buf = M.buffer(session)
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    vim.api.nvim_set_current_win(win)
    return buf
  end
  vim.cmd(config.options.window.split .. " " .. tostring(config.options.window.height) .. "split")
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(buf), 0 })
  return buf
end

return M
