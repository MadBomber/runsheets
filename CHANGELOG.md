# Changelog

## [Unreleased]

### Added (milestone 2: the full block set)

- `background` blocks execute: Start and Stop buttons, no timeout, output
  streamed, a Running panel in the sidebar on every page, and everything
  still running is stopped when the run finishes. A new execution state
  `stopped`, which is not a failure.
- `terminal` blocks have an "I ran this" button. The confirmation and an
  optional note are recorded as an `ack` event and in `run.json`'s `acks`.
- Destructive confirmation is checked server-side: `POST /blocks/:id/execute`
  answers 428 with a per-block code, and runs the block only when the code
  comes back in `confirm`. The `execute` event carries `confirmed: true`.
- `expect` blocks are linked to the executable block above them and shown
  beside its real output with a matches/differs hint.
- Secret input values are redacted from captured output before it is
  written, including secrets split across two writes (`Runsheets::Redactor`).
- Output is captured through a pipe and a reader thread instead of a file
  handle passed to the child.
- `POST /executions/:id/stop` and `POST /blocks/:id/acknowledge`.
- Execution JSON gains `background` and `output_truncated`; the page marks
  output shown from its tail.
- Manual steps get acknowledgement wording in the step panel; the active
  run panel shows secret inputs as set without their values.
- `examples/hello` gains a background step and a redaction check in
  `verify.md`.

### Added (milestone 1)

- `runsheet RUNBOOK_DIR` serves a runbook directory on loopback; `--check`
  loads it and reports authoring warnings.
- Runbook model: `runbook.md` front matter and preamble, ordered `steps/`,
  optional `verify.md` and `rollback.md`, `inputs` with secrets,
  `interpreters` mapping.
- Fenced block convention: `run`, `destructive`, `terminal`, `expect`
  parsed from the info string; `background` recognised but not executable.
- Execution of `bash`, `sh`, `zsh` and `ruby` blocks as fresh processes in
  their own process group, with per-step timeouts that kill the group.
- Run records under `~/.local/share/runsheets/runs/<slug>/<timestamp>/`
  with `run.json`, `run.md`, and per-execution `.cmd` and `.out` files.
- Landing page with inputs form, step list, run history; step pages with
  Run buttons, live output polling, step done/skipped acknowledgements with
  notes, and the rollback document in the sidebar.
- Per-process session token and loopback host authorization on every
  state-changing request.
