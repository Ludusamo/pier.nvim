local M = {}

M.defaults = {
  cmd = "pi",
  tools = { "read", "grep", "find", "ls" },
  cache_dir = vim.fn.stdpath("cache") .. "/pier.nvim",
  context = {
    snippet_lines = 40,
    max_selection_lines = 200,
    max_selection_bytes = 20000,
  },
  review = {
    max_diff_bytes = 120000,
  },
  window = {
    split = "botright",
    height = 15,
  },
  kill_timeout_ms = 2000,
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M
