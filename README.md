# pier.nvim

A small Neovim client for `pi --mode rpc`.
It keeps one persisted, read-only Pi RPC process per git root, streams answers into a scratch buffer, and tees raw and rendered output into log files.

## Status

MVP implementation with hunk, diagnostics, add-context, and quickfix location helpers.
It does not apply edits.

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

| Command             | Behavior                                                         |
| ------------------- | ---------------------------------------------------------------- |
| `:Pier {msg}`       | Ask Pi about the current file and cursor.                        |
| `:'<,'>Pier`        | Ask Pi about a visual line range with the selected text inlined.  |
| `:PierHunk {msg}`   | Ask Pi about the git hunk under the cursor.                      |
| `:PierDiag {msg}`   | Ask Pi about diagnostics in the buffer or visual range.           |
| `:PierAdd`          | Add the current snippet, note, or visual selection to next ask.   |
| `:PierLocations`    | Open captured file references from Pi output in quickfix.         |
| `:PierLog`          | Toggle the rendered scratch buffer.                              |
| `:PierRawLog`       | Open `raw.jsonl` for the current repository session.              |
| `:PierTmuxLog`      | Open a tmux split tailing `rendered.log`.                         |
| `:PierAbort`        | Abort the active run for the current repository.                  |

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
nvim-<sanitized-repo-basename>-<8-char-hash-of-root>
```

## Safety

The spawned command is:

```text
pi --mode rpc --session-id <id> --tools read,grep,find,ls
```

No write, edit, or bash tools are enabled by pier.nvim.

## Health

Run:

```vim
:checkhealth pier
```
