local patch_review = require("pier.patch_review")

local M = {}

function M.prompt(base, stat, commits, diff)
  return table.concat({
    "Create a code-review tour of the committed branch diff " .. base .. "...HEAD.",
    "Group related changes into a few clusters ordered so a reviewer can read them top to bottom.",
    "Use the read, grep, find, and ls tools to read current files if you need surrounding code.",
    "You cannot run git, and a truncated diff means the omitted hunks are not visible to you.",
    "Do not apply edits.",
    "",
    "End your reply with exactly one fenced json block of this shape:",
    "```json",
    '{"groups":[{"title":"short title","summary":"why these changes belong together","stops":[{"file":"path/relative/to/repo","line":12,"title":"short title","note":"what to check here"}]}]}',
    "```",
    "Each stop must point at a line in the new version of a changed file.",
    "",
    "Commits:",
    commits,
    "",
    "Diff stat:",
    stat,
    "",
    "Diff:",
    "```diff",
    diff,
    "```",
  }, "\n")
end

local function str(value)
  return type(value) == "string" and value or nil
end

local function strip_path(file)
  return (file:gsub("\t.*$", ""))
end

-- One anchor per hunk: { file, line, end_line } in the new version of the file.
-- Second return value lists deleted files, which have no new side to jump to.
function M.anchors(diff)
  local anchors, deleted, seen = {}, {}, {}
  for _, hunk in ipairs(patch_review.parse(diff)) do
    local file, old, gone
    for _, header in ipairs(hunk.headers) do
      local new = header:match("^%+%+%+ (.+)$")
      if new == "/dev/null" then
        gone = true
      elseif new then
        file = strip_path(new:gsub("^b/", "", 1))
      end
      local prev = header:match("^%-%-%- a/(.+)$")
      if prev then
        old = strip_path(prev)
      end
    end
    if gone then
      if old and not seen[old] then
        seen[old] = true
        table.insert(deleted, old)
      end
    else
      file = file or hunk.headers[1]:match("^diff %-%-git a/.- b/(.+)$")
      local start, count = hunk.lines[1]:match("^@@ %-%d+,?%d* %+(%d+),?(%d*) @@")
      if file and start then
        start = tonumber(start)
        count = count ~= "" and tonumber(count) or 1
        local line = math.max(start, 1)
        table.insert(anchors, { file = file, line = line, end_line = math.max(start + count - 1, line) })
      end
    end
  end
  return anchors, deleted
end

-- Returns a sanitized stop for a changed, non-deleted file, or nil.
local function clean_stop(stop, files)
  if type(stop) ~= "table" then
    return nil
  end
  local file = str(stop.file)
  if file and not files[file] then
    local normalized = file:gsub("^%./", ""):gsub("^b/", "")
    file = files[normalized] and normalized or nil
  end
  local line = stop.line
  if not file or type(line) ~= "number" or line < 1 or line % 1 ~= 0 then
    return nil
  end
  return { file = file, line = line, title = str(stop.title), note = str(stop.note) }
end

local function fallback(anchors)
  local stops = {}
  for _, anchor in ipairs(anchors) do
    table.insert(stops, { file = anchor.file, line = anchor.line, title = anchor.file })
  end
  return { groups = #stops > 0 and { { title = "All changes", stops = stops } } or {}, fallback = true }
end

-- Parses the last ```json fence. Invalid stops are dropped; falls back to all hunks.
-- Only files with a new side (anchors) are valid, so deleted files are never accepted.
function M.parse(text, anchors)
  local files = {}
  for _, anchor in ipairs(anchors) do
    files[anchor.file] = true
  end

  local json
  for body in (text or ""):gmatch("```json[ \t]*\n(.-)\n[ \t]*```") do
    json = body
  end
  local ok, data = pcall(vim.json.decode, json or "")
  if not ok or type(data) ~= "table" or type(data.groups) ~= "table" then
    return fallback(anchors)
  end

  local groups = {}
  for i, group in ipairs(data.groups) do
    if type(group) == "table" and type(group.stops) == "table" then
      local stops = {}
      for _, stop in ipairs(group.stops) do
        stop = clean_stop(stop, files)
        if stop then
          table.insert(stops, stop)
        end
      end
      if #stops > 0 then
        table.insert(groups, { title = str(group.title) or ("Group " .. i), summary = str(group.summary), stops = stops })
      end
    end
  end
  if #groups == 0 then
    return fallback(anchors)
  end
  return { groups = groups }
end

local function covered(anchor, groups)
  for _, group in ipairs(groups) do
    for _, stop in ipairs(group.stops) do
      if stop.file == anchor.file and stop.line >= anchor.line and stop.line <= anchor.end_line then
        return true
      end
    end
  end
  return false
end

function M.to_qf(tour, anchors, root, deleted)
  local items = {}
  local function heading(text)
    table.insert(items, { text = text, valid = 0 })
  end
  local function path(file)
    return root and (root .. "/" .. file) or file
  end

  for i, group in ipairs(tour.groups) do
    heading(string.format("[%d/%d] %s%s", i, #tour.groups, group.title, group.summary and (" - " .. group.summary) or ""))
    for _, stop in ipairs(group.stops) do
      local text = stop.title or stop.file
      if stop.note and stop.note ~= "" then
        text = text .. ": " .. stop.note
      end
      table.insert(items, { filename = path(stop.file), lnum = stop.line, text = text })
    end
  end

  if deleted and #deleted > 0 then
    heading("Deleted files (not jumpable)")
    for _, file in ipairs(deleted) do
      table.insert(items, { text = "Deleted: " .. file, valid = 0 })
    end
  end

  if not tour.fallback then
    local uncovered = {}
    for _, anchor in ipairs(anchors) do
      if not covered(anchor, tour.groups) then
        table.insert(uncovered, { filename = path(anchor.file), lnum = anchor.line, text = "Uncovered change: " .. anchor.file })
      end
    end
    if #uncovered > 0 then
      heading("Uncovered changes")
      vim.list_extend(items, uncovered)
    end
  end
  return items
end

function M.start(root, text, diff, opts)
  opts = opts or {}
  local anchors, deleted = M.anchors(diff)
  if #anchors == 0 and #deleted == 0 then
    vim.notify("pier.nvim: no hunks found in branch diff", vim.log.levels.WARN)
    return false
  end
  local tour = M.parse(text, anchors)
  local items = M.to_qf(tour, anchors, root, deleted)
  vim.fn.setqflist({}, " ", { title = opts.title or "Pier review tour", items = items })
  vim.cmd("copen")
  if tour.fallback then
    vim.notify("pier.nvim: could not parse review tour, listing all hunks", vim.log.levels.WARN)
  end
  return true
end

return M
