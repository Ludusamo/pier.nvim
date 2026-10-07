# pier.nvim

A small Neovim client for `pi --mode rpc`.
It keeps one persisted, read-only Pi RPC process per git root and branch, streams answers into a scratch buffer, and tees raw and rendered output into log files.

## Status

MVP implementation with hunk, diagnostics, add-context, patch-review, and quickfix location helpers.
It only applies patch hunks after you explicitly accept them.

## Setup

With a local plugin manager entry:

```lua
{
  dir = "/home/brendan/dev/pier.nvim",
  config = function()
    require("pier").setup()
  end,
}
```

Options:

```lua
require("pier").setup({
  cmd = "pi",
  tools = { "read", "grep", "find", "ls" },
  cache_dir = vim.fn.stdpath("cache") .. "/pier.nvim",
  review = { max_diff_bytes = 120000 },
})
```

## Commands

| Command              | Behavior                                                        |
| -------------------- | --------------------------------------------------------------- |
| `:Pier {msg}`        | Ask Pi about the current file and cursor.                       |
| `:'<,'>Pier`         | Ask Pi about a visual line range with the selected text inlined. |
| `:PierHunk {msg}`    | Ask Pi about the git hunk under the cursor.                     |
| `:PierSnippet {msg}` | Ask Pi for a code snippet and preview it inline.                 |
| `:PierSnippetAccept` | Insert the pending snippet preview.                             |
| `:PierSnippetReject` | Clear the pending snippet preview.                              |
| `:PierChange {msg}`  | Ask Pi for a unified diff, then review each hunk before apply.   |
| `:PierPatchAccept`   | Apply the current pending patch hunk.                            |
| `:PierPatchReject`   | Skip the current pending patch hunk.                             |
| `:PierPatchAsk {q}`  | Ask Pi a question about the current pending patch hunk.          |
| `:PierPatchClose`    | Close the pending patch review.                                  |
| `:PierReviewBranch`  | Build a clustered code-tour quickfix list of the branch diff.    |
| `:PierDiag {msg}`    | Ask Pi about diagnostics in the buffer or visual range.          |
| `:PierAdd`           | Add the current snippet, note, or visual selection to next ask.  |
| `:PierNew`           | Start a fresh durable Pi session for this repo and branch.       |
| `:PierLocations`     | Open captured file references from Pi output in quickfix.        |
| `:PierLog`           | Toggle the rendered scratch buffer.                             |
| `:PierRawLog`        | Open `raw.jsonl` for the current repository session.             |
| `:PierTmuxLog`       | Open a tmux split tailing `rendered.log`.                        |
| `:PierAbort`         | Abort the active run for the current repository.                 |

## Logs

Logs are written under:

```text
~/.cache/pier.nvim/<session-id>/
  rendered.log
  raw.jsonl
  stderr.log
```

Session ids use this format:

```text
nvim-<sanitized-repo-basename>-<sanitized-branch>-<8-char-hash-of-root-and-branch>
```

Sessions are scoped by git root and branch, so switching branches switches Pi sessions.
In detached HEAD, outside a git repository, or without git, the legacy root-only id is used:

```text
nvim-<sanitized-repo-basename>-<8-char-hash-of-root>
```

`:PierNew` starts a fresh Pi session for the current repo and branch.
It stores a suffix override in `~/.cache/pier.nvim/session-overrides.json`, so the new session survives restarts.
It refuses to run while Pi is busy and drops pending `:PierAdd` context.
Old session logs, buffers, and Pi sessions are never deleted.

## Safety

The spawned command is:

```text
pi --mode rpc --session-id <id> --tools read,grep,find,ls
```

No write, edit, or bash tools are enabled for Pi by pier.nvim.
`:PierChange` asks Pi to produce a unified diff, then pier.nvim applies only the hunks you accept with `git apply`.
`:PierReviewBranch [base]` asks Pi for a code tour of the committed diff `base...HEAD`.
The base defaults to the first of `main`, `origin/main`, `master`, `origin/master` that exists.
Uncommitted changes are not included.
Pi groups related changes into clusters and picks stops inside them.
The result opens in quickfix with one heading per cluster, the stops under it, and an "Uncovered changes" section for hunks Pi did not mention.
Use `:cnext`, `:cprevious`, or `:cc` to walk the tour, and ask follow-ups with `:Pier` as usual.
If Pi's reply cannot be parsed, every hunk is listed in one group instead.
The prompt diff is cut at the last full line before `review.max_diff_bytes` (default 120000).
Pi can only read current files and cannot run git, so it cannot see omitted hunks.
Hunks Pi did not cover, including omitted ones, are still listed from the full local diff under "Uncovered changes".
Deleted files are listed as text-only entries.

## Health

Run:

```vim
:checkhealth pier
```
