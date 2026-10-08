# Changelog

## [Unreleased]

### Added

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
