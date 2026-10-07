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

vim.api.nvim_create_user_command("PierSnippet", function(opts)
  pier().ask_snippet(opts.args)
end, { nargs = "*", desc = "Ask pi for a snippet and preview it inline" })

vim.api.nvim_create_user_command("PierSnippetAccept", function()
  pier().accept_snippet()
end, { desc = "Accept the pending pier snippet preview" })

vim.api.nvim_create_user_command("PierSnippetReject", function()
  pier().reject_snippet()
end, { desc = "Reject the pending pier snippet preview" })

vim.api.nvim_create_user_command("PierChange", function(opts)
  pier().ask_change(opts.args)
end, { nargs = "*", desc = "Ask Pi for a patch and review it hunk by hunk" })

vim.api.nvim_create_user_command("PierPatchAccept", function()
  pier().accept_patch_hunk()
end, { desc = "Apply or mark reviewed the current pending pier patch hunk" })

vim.api.nvim_create_user_command("PierPatchReject", function()
  pier().reject_patch_hunk()
end, { desc = "Reject or skip the current pending pier patch hunk" })

vim.api.nvim_create_user_command("PierPatchClose", function()
  pier().close_patch_review()
end, { desc = "Close the pending pier patch review" })

vim.api.nvim_create_user_command("PierPatchAsk", function(opts)
  pier().ask_patch_hunk(opts.args)
end, { nargs = "*", desc = "Ask Pi about the current pending patch hunk" })

vim.api.nvim_create_user_command("PierReviewBranch", function(opts)
  pier().review_branch(opts.args)
end, { nargs = "?", desc = "Ask Pi for a clustered code-tour quickfix of the branch diff" })

vim.api.nvim_create_user_command("PierHunk", function(opts)
  pier().ask_hunk(opts.args)
end, { nargs = "*", desc = "Ask pi about the current git hunk" })

vim.api.nvim_create_user_command("PierDiag", function(opts)
  pier()._command_diag(opts)
end, { nargs = "*", range = true, desc = "Ask pi about diagnostics" })

vim.api.nvim_create_user_command("PierAdd", function(opts)
  pier()._command_add(opts)
end, { nargs = "*", range = true, desc = "Add context to the next pier prompt" })

vim.api.nvim_create_user_command("PierNew", function()
  pier().new_session()
end, { desc = "Start a fresh durable pi session for this repo and branch" })

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
