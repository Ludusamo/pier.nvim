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
| `:PierReviewBranch`  | Review the current branch diff against `main` hunk by hunk.      |
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
`:PierReviewBranch [base]` reviews an existing branch diff without applying anything; accepting marks a hunk reviewed and moves to the next hunk.

## Health

Run:

```vim
:checkhealth pier
```
