# Changelog

## [Unreleased]

### Added (milestone 4: packaging)

- Single-file runbooks: `runsheet path/to/file.md` reads one markdown
  file whose `##` headings are the steps, with step attributes in an HTML
  comment after the heading and Verify and Rollback sections standing in
  for `verify.md` and `rollback.md` (`Runsheets::SingleFile`).
- A language mapped under `interpreters` in the front matter now executes;
  `sql run` through `psql` works. Previously the mapping was honoured at
  spawn time but blocks were classified against the built-in languages
  only, so such blocks warned and had no Run button.
- `runsheet --init PATH` scaffolds a starter runbook (directory, or a
  single file when the path ends in `.md`) that passes `--check`.
- `examples/staging-teardown` (directory, the shape of a real AWS
  teardown) and `examples/db-maintenance.md` (single file, `sql run`
  blocks via `psql`).
- Vocabulary: the record of a run is the *runsheet* in the page, sidebar
  and buttons.

### Changed

- Development: `.loki` task file for asgard, `.rubocop.yml`, `.reek.yml` and a
  Reek baseline under `.quality/`; the quality tools are in the Gemfile and
  `asgard quality` passes every gate. Ten methods were split to get under the
  Flog threshold; behaviour is unchanged.
- `Runbook.load` raises "no such runbook" for a missing path; `Runbook`
  gains `main_path`, `single_file?`; `Step.new` takes `data:` and
  `interpreters:`; `Renderer.render` and `Block.new` take `interpreters:`.
- The CLI's parsed option is `:runbook` (was `:dir`).

### Added (milestone 3: verification and history)

- Verification runs: `POST /run` with `kind=verify` (the landing page's
  "Verify only" button) starts a run that may execute only verify-kind
  steps and `verify.md`. Run ids get a `-verify` suffix and `run.json` a
  `kind` field.
- A Checks page (`GET /verify`) gathers every verify document with a
  "Run all" button that executes each check in order.
- `last_verified` write-back: after a completed run with every step done,
  or a verification with every check run and nothing left failing, the
  landing page offers to stamp the run's date into `runbook.md`
  (`POST /run/stamp`, `POST /run/stamp/dismiss`). The stamp replaces that
  one front-matter line and is recorded as a `stamp` event.
- Run verdicts: `RunRecord#verified?`, `latest_executions`,
  `unresolved_failures`, `last_step`. The history list shows kind, verdict,
  start time, duration, counts, and the step a run stopped at.
- Drift: a finished run's page shows a line diff for every block whose
  code has changed since it ran, or that is gone (`Runsheets::Diff`,
  `RunRecord#drift`).
- The runbook is re-read on the next GET whenever one of its markdown
  files changes on disk.
- `examples/hello` gains a `verify` step.

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
