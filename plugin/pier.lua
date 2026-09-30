if vim.g.loaded_pier_nvim then
  return
end
vim.g.loaded_pier_nvim = true

local function pier()
  return require("pier")
end

vim.api.nvim_create_user_command("Pier", function(opts)
  pier()._command_pier(opts)
end, { nargs = "*", range = true, desc = "Ask pi about the current file or selection" })

vim.api.nvim_create_user_command("PierHunk", function(opts)
  pier().ask_hunk(opts.args)
end, { nargs = "*", desc = "Ask pi about the current git hunk" })

vim.api.nvim_create_user_command("PierDiag", function(opts)
  pier()._command_diag(opts)
end, { nargs = "*", range = true, desc = "Ask pi about diagnostics" })

vim.api.nvim_create_user_command("PierAdd", function(opts)
  pier()._command_add(opts)
end, { nargs = "*", range = true, desc = "Add context to the next pier prompt" })

vim.api.nvim_create_user_command("PierLocations", function()
  pier().open_locations()
end, { desc = "Open captured pier locations in quickfix" })

vim.api.nvim_create_user_command("PierLog", function()
  pier().open_log()
end, { desc = "Toggle the pier scratch buffer" })

vim.api.nvim_create_user_command("PierRawLog", function()
  pier().open_raw_log()
end, { desc = "Open the raw pier JSONL log" })

vim.api.nvim_create_user_command("PierTmuxLog", function()
  pier().open_tmux_log()
end, { desc = "Open a tmux pane tailing the pier rendered log" })

vim.api.nvim_create_user_command("PierAbort", function()
  pier().abort()
end, { desc = "Abort the current pier run" })
