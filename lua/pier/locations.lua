local M = {}

local function is_list(value)
  if type(value) ~= "table" then
    return false
  end
  local count = 0
  for key, _ in pairs(value) do
    if type(key) ~= "number" then
      return false
    end
    count = count + 1
  end
  return count > 0
end

local function normalize_path(path, root)
  if not path or path == "" then
    return nil
  end
  path = tostring(path):gsub("^file://", "")
  if path:match("^%a+://") then
    return nil
  end
  if path:sub(1, 1) == "/" then
    return path
  end
  return root .. "/" .. path
end

local function file_exists(path)
  return path and vim.fn.filereadable(path) == 1
end

local function add(out, root, loc)
  local path = loc.path or loc.file or loc.filename or loc.uri
  local line = loc.line or loc.lnum or loc.startLine or loc.start_line
  local col = loc.col or loc.column or loc.startColumn or loc.start_col or 1
  local filename = normalize_path(path, root)
  line = tonumber(line)
  col = tonumber(col) or 1
  if not filename or not line or line < 1 or not file_exists(filename) then
    return
  end
  table.insert(out, {
    filename = filename,
    lnum = line,
    col = math.max(1, col),
    text = tostring(loc.text or loc.message or loc.label or (path .. ":" .. tostring(line))),
  })
end

local function walk(value, root, out, seen)
  if type(value) ~= "table" or seen[value] then
    return
  end
  seen[value] = true

  add(out, root, value)

  if type(value.range) == "table" and type(value.range.start) == "table" then
    add(out, root, {
      path = value.path or value.file or value.filename or value.uri,
      line = (value.range.start.line and tonumber(value.range.start.line) or 0) + 1,
      col = (value.range.start.character and tonumber(value.range.start.character) or 0) + 1,
      text = value.text or value.message or value.label,
    })
  end

  for _, child in pairs(value) do
    if type(child) == "table" then
      if is_list(child) then
        for _, item in ipairs(child) do
          walk(item, root, out, seen)
        end
      else
        walk(child, root, out, seen)
      end
    end
  end
end

function M.from_event(event, root)
  local out = {}
  walk(event, root, out, {})
  return out
end

function M.from_text(text, root)
  local out = {}
  if not text or text == "" then
    return out
  end
  for path, line, col in text:gmatch("([%w%._%-%+/][%w%._%-%+/]*):(%d+):?(%d*)") do
    local token = path .. ":" .. line .. (col ~= "" and (":" .. col) or "")
    add(out, root, {
      path = path,
      line = line,
      col = col ~= "" and col or 1,
      text = token,
    })
  end
  return out
end

function M.to_qf(locations)
  local out = {}
  local seen = {}
  for _, loc in ipairs(locations or {}) do
    local key = table.concat({ loc.filename or "", loc.lnum or "", loc.col or "" }, "\0")
    if not seen[key] then
      seen[key] = true
      table.insert(out, loc)
    end
  end
  return out
end

return M
