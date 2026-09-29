# pier.nvim MVP Plan

## Summary

Build a standalone Neovim plugin at `/home/brendan/dev/pier.nvim`.
It runs one persisted, read-only `pi --mode rpc` process per git root.
Output goes to a scratch buffer and is tee'd to log files so tmux or raw inspection can follow along.

## Decisions

| #   | Topic             | Decision                                                                                                |
| --- | ----------------- | ------------------------------------------------------------------------------------------------------- |
| 1   | Process ownership | Neovim spawns `pi --mode rpc` and mirrors output to viewers.                                            |
| 2   | Session           | Persisted from day one.                                                                                 |
| 3   | Scope             | One process and one session per git root.                                                               |
| 4   | Context           | Hybrid: inline selection, hunk and diagnostics, references for whole files, with size caps.             |
| 5   | Location          | Standalone plugin repo at `/home/brendan/dev/pier.nvim`, loaded as a local plugin from the nvim config. |
| 6   | Output view       | Scratch buffer plus log tee, with an optional tmux tail.                                                |
| 7   | Tools             | Read-only tools only: `read,grep,find,ls`. Write and edit are opt-in later.                             |
| 8   | Model             | No `--model` or `--provider` flags, so pi defaults are used.                                            |
| 9   | Session ID        | `nvim-<sanitized-repo-basename>-<8-char-hash-of-root>`.                                                 |
| 10  | Log directory     | `~/.cache/pier.nvim/<session-id>/`.                                                                     |

## Goals

- Ask pi about the current file, cursor position or visual selection from inside Neovim.
- Stream the answer into a scratch buffer.
- Reuse the same pi session for a repo across Neovim restarts.
- Keep the agent read-only.
- Always tee rendered output and raw RPC events to files.
- Recover cleanly if the pi process dies.

## Non-goals

- An editor-embedded chat UI.
- Applying diffs or edits from Neovim.
- Multi-client sync.
- LSP integration.
- Steering or follow-up prompts while a run is busy.

## Grounding facts

- Startup command is `pi --mode rpc --session-id <id> --tools read,grep,find,ls`, run with `cwd` set to the git root.
- `--session-id` opens the session if it exists and creates it otherwise.
- Session IDs may only contain letters, numbers, `.`, `_` and `-`, and must start and end with a letter or number.
- Framing is strict JSONL, split only on LF, with a trailing CR stripped.
- Stdout carries protocol records only.
- Stderr is diagnostics and must never be parsed.
- Commands used are `prompt` (with `id`), `abort` and `get_state`.
- A successful `response` only means the prompt was accepted.
- A run is finished only when `agent_settled` arrives, not at `agent_end`.
- `message_update` events carry `assistantMessageEvent`, including `text_delta`.
- Extensions may send `extension_ui_request`, and the client must reply with a cancellation or pi can block.

## File layout

```text
/home/brendan/dev/pier.nvim/
  README.md
  plugin/pier.lua
  lua/pier/init.lua
  lua/pier/config.lua
  lua/pier/project.lua
  lua/pier/rpc.lua
  lua/pier/session.lua
  lua/pier/context.lua
  lua/pier/render.lua
  lua/pier/ui.lua
  lua/pier/log.lua
  lua/pier/tmux.lua
  lua/pier/health.lua
  tests/
    framing_spec.lua
    project_spec.lua
    context_spec.lua
    render_spec.lua
    fixtures/events.jsonl
```

Log layout per session:

```text
~/.cache/pier.nvim/<session-id>/
  rendered.log
  raw.jsonl
  stderr.log
```

## Module responsibilities

| Module      | Responsibility                                                                                                                                                                         |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| plugin/pier | Registers user commands and lazy-requires the plugin.                                                                                                                                  |
| init        | Exposes `setup(opts)` and the public API: ask, ask_visual, abort, open_log.                                                                                                            |
| config      | Holds defaults and merges user options: `cmd`, `tools`, `cache_dir`, context limits, window layout.                                                                                    |
| project     | Finds the git root with `vim.fs.root`, falling back to `git rev-parse --show-toplevel` and then cwd. Derives the session id and cache dir, and creates the directory.                  |
| rpc         | Spawns pi, splits stdout on LF, decodes JSON in pcall, correlates responses by id, dispatches events through `vim.schedule`, handles exit and stderr, and stops with a kill timeout.   |
| session     | Keeps a registry keyed by git root and starts rpc lazily. Tracks busy state from prompt accept to `agent_settled`. Rejects prompts while busy. Auto-cancels blocking UI requests.      |
| context     | Builds the hybrid prompt: root, relative path, filetype, cursor line, and an inline fenced selection with its line range when present. Truncates large selections with a note.         |
| render      | Pure function from event and state to text. Streams deltas, prints tool calls and short result summaries, marks run start and end, and shows errors and aborts. No nvim API calls.     |
| ui          | Owns one scratch buffer per session (`buftype=nofile`, `ft=markdown`, named `pier://<id>`). Appends with partial-line continuation and autoscrolls only when the cursor is at the end. |
| log         | Opens append handles for the three log files, receives raw lines before decode and rendered text from render, and flushes on each write.                                               |
| tmux        | Opens a split running `tail -n +1 -F <rendered.log>` when `$TMUX` is set, and reports an error otherwise.                                                                              |
| health      | Implements `:checkhealth pier`: pi on PATH, `--session-id` and `--mode` supported, git present, tmux optional.                                                                         |

## Commands

MVP:

| Command            | Behavior                                                           |
| ------------------ | ------------------------------------------------------------------ |
| `:Pier {msg}`      | Ask about the current file and cursor. Prompts for input if empty. |
| `:'<,'>Pier {msg}` | Ask about the selected range, with the text inlined.               |
| `:PierLog`         | Toggle the rendered scratch buffer.                                |
| `:PierTmuxLog`     | Open a tmux pane tailing the rendered log.                         |
| `:PierRawLog`      | Open `raw.jsonl` in a split with `autoread`.                       |
| `:PierAbort`       | Send `abort` for the current git root.                             |

Post-MVP:

| Command          | Behavior                                   |
| ---------------- | ------------------------------------------ |
| `:PierHunk`      | Ask about the current git or diff hunk.    |
| `:PierDiag`      | Ask about diagnostics in the range.        |
| `:PierAdd`       | Add context to the next prompt.            |
| `:PierTui`       | Open the full pi TUI.                      |
| `:PierLocations` | Show agent-provided locations in quickfix. |

## Context rules

- Normal `:Pier` sends the repo, file, cursor line and a small nearby snippet or reference.
- Visual `:Pier` inlines the selected text with `path:Lx-Ly`.
- Large selections are truncated at `max_selection_lines`, with a note telling pi to use `read`.
- Hunks and diagnostics are inlined post-MVP.

## Milestones

1. Scaffold.
   - Create the repo and layout.
   - Add config defaults and stub commands.
   - Add `health.lua`.
2. Project and session paths.
   - Detect the git root.
   - Derive a stable session id.
   - Create the cache dir.
   - Unit test sanitizing, the start and end character rule, hash stability, and distinct ids for same-basename roots.
3. RPC transport.
   - Spawn pi with the agreed arguments.
   - Parse JSONL safely, including records split across chunks, CRLF and trailing partial lines.
   - Correlate responses by id.
   - Stream events and log raw and stderr output.
4. Session manager.
   - One session per git root, started lazily on first `:Pier`.
   - Busy and idle tracking via `agent_settled`.
   - Abort support.
   - Auto-cancel blocking extension UI requests.
5. Rendering and UI.
   - Scratch buffer.
   - Stream assistant deltas and show tool calls.
   - Append to the rendered log.
   - `:PierLog`.
6. Context.
   - Current file and cursor.
   - Visual range inline.
   - Prompt template and truncation.
7. Log helpers.
   - `:PierRawLog` and `:PierTmuxLog`.
   - Shutdown cleanup on `VimLeavePre`.

## Acceptance criteria

- `:Pier what does this file do?` streams an answer into a scratch buffer.
- A visual selection with `:'<,'>Pier explain` includes the selected text and line range.
- Restarting Neovim reuses the same pi session for the repo.
- Two repos with the same basename get different sessions.
- The agent cannot use write, edit or bash tools.
- `:PierAbort` stops an active run.
- Logs appear under `~/.cache/pier.nvim/<session-id>/`.
- `:PierTmuxLog` opens a tmux pane tailing live output.
- Killing the pi process surfaces an error, and the next `:Pier` restarts it with the same session.

## Risks

| Risk                        | Mitigation                                                                                      |
| --------------------------- | ----------------------------------------------------------------------------------------------- |
| RPC event shape drift       | Record a real stream as a fixture, and keep render tolerant of unknown events.                  |
| Extension UI deadlocks      | Always reply to `extension_ui_request` with a cancellation, and route `notify` to `vim.notify`. |
| Buffer update performance   | Batch appends per scheduled tick and avoid full-buffer rewrites.                                |
| Log growth                  | Document the cache location, and consider rotation after the MVP.                               |
| Orphaned child processes    | Stop on `VimLeavePre`, close stdin first, and kill after a timeout.                             |
| Stale line numbers          | Selections are sent inline at send time, and unsaved buffers are noted in the prompt.           |
| Scope creep toward full IDE | Hold the line at ask, log and abort until the MVP is accepted.                                  |
