# Changelog

## [Unreleased]

## [0.0.1] - 2026-10-09

### Fixed

- Run, Start and "I ran this" buttons are disabled when they cannot work,
  with a tooltip saying why: until the runbook on screen has a run. Before,
  they looked live and a click only showed a small "not run" status.
- Single-file runbooks are reloaded from their own file. Before, a session
  reloaded the containing directory, so edits to a single-file runbook were
  never picked up.
- Stopping the server (Ctrl-C) ends the active run as `abandoned` and stops
  everything it left running. Before, background blocks outlived the server
  and the run record stayed `running` forever.
- Every page carries a Content-Security-Policy with a per-response nonce on
  its own inline script and stylesheet, and `Cache-Control: no-store`. Raw
  HTML in runbook markdown still renders, but a `<script>` in it no longer
  runs, so a runbook cannot use the page's session token to execute its own
  blocks or answer its own destructive confirmation.
- `/files/*` no longer follows a symbolic link out of the runbook directory.
- `--bind` to a wildcard address (`0.0.0.0`, `::`) works. The Host check is
  off for a wildcard bind, since no host list can be right, and the CLI warns
  on any non-loopback bind. A specific non-loopback address permits itself.
- `POST /run/finish` with a status other than `completed` or `abandoned` is
  refused with 422 before anything is stopped. Before, every running
  execution was stopped and then the request failed with 500, leaving the
  run active.
- Only numbered steps can be marked done or skipped (422 otherwise). Marking
  the landing page or the `verify`/`rollback` documents used to count toward
  "every step done".
- A step whose `timeout` is not a positive integer warns and uses the default
  instead of timing out at once.
- `Pages` requires `rack/utils` itself, so it works without `Web` loaded;
  `step.kind` is HTML-escaped in badges.

### Added (milestone 5: sessions)

- Sessions: everything between starting runsheets and stopping it is one
  session (`Runsheets::Session`). It starts on a page asking who is
  starting it and why (`GET /session/new`, `POST /session`), or straight
  away with `--engineer` and `--why` (`RUNSHEETS_ENGINEER`,
  `RUNSHEETS_WHY`, config `engineer:`); the engineer is prefilled from
  config, `git config user.name`, then `$USER`. The why is the first note.
- Selecting a runbook starts its run (`POST /runs`, `Runsheets::Run`): in a
  library the runbook pane carries the inputs form and a Start run button;
  on one runbook the landing page does. Selecting it again returns to the
  same run, and switching between runbooks finishes nothing. Inputs given
  earlier in the session are offered as defaults (never secrets).
- A session page (`GET /session`) with timestamped notes
  (`POST /session/notes`), the runs and their progress, the tail of the
  session log, and an End session button (`POST /session/end`). The header
  shows the session: engineer, elapsed time, runbooks.
- Ending the session (the button, or Ctrl-C) closes every run with a status
  worked out from what was done: `completed`, `partial` or `opened`. A
  session left running by a killed process is closed as `interrupted` at
  the next start, with its runs.
- `session.log` (`Runsheets::SessionLog`, Ruby's Logger underneath): every
  action and every line of output, timestamped, tagged and levelled like a
  Rails log, written as it happens and echoed to the terminal. Secrets
  never reach it. `--log-level`, `--verbose` (debug), `--quiet`,
  `RUNSHEETS_LOG_LEVEL`, `RUNSHEETS_QUIET`.
- Change a run's inputs partway (`POST /run/inputs`); a secret left blank
  keeps its value and never comes back to the page. Recorded as an
  `inputs` event.
- The Running panel lists background processes from every runbook in the
  session, each with Stop.
- Records: `runs/sessions/<id>/session.json` and `session.log`; a run's
  directory is named by its session id and its `run.json` names the
  session. Blocks see `RUNSHEETS_SESSION_ID`.

### Added (milestone 4: packaging)

- Full-text search (`GET /search`, `Runsheets::Search`): a search box in
  every header ([f] focuses it) searches every runbook in the library, or
  the one runbook: titles, front matter prose, preambles, steps, verify
  and rollback, code included. Every word must appear; "quoted phrases"
  match as written. Results are ranked, with the matching steps and a
  highlighted snippet for each, linking to the step (the open runbook) or
  to its row in the library. Works before a runbook is open.
- A relative link to a markdown file opens it as a page (`/docs/*`): one of
  the runbook's own files goes to its step page, another runbook in the
  library to its library page, and any other renders as a plain document
  with nothing executable, in a new tab. Links resolve within the directory `runsheets`
  was started on, so a runbook in a library can link anywhere in it, and
  they work from the library pane before any runbook is opened.
- Docs: a Concepts section (runbooks and plain documents, runs and
  runsheets).
- A directory of runbooks (`Runsheets::Library`): `runsheets DIR` where DIR
  holds single-file runbooks and runbook directories, in folders nested to
  any depth, opens on the library page (`/library`): a folder tree in the
  left pane with a filter box and keyboard cursor, and in the main pane
  whatever is selected. A folder shows its `README.md` and cards for what it
  holds; a runbook (`/library/<path>`) shows its description, prerequisites,
  inputs, steps, previous runs and preamble beside the Open button. The tree
  never descends into a runbook directory. A runbook's slug is its path
  inside the library, so run records of `a/backup` and `b/backup` stay
  apart; the header breadcrumbs of an open runbook lead back through its
  folders. Runbooks added, removed or edited while serving appear on the
  next visit. Switching is refused while a run is active. `--check` on such
  a directory checks every runbook.
- Layered settings through `myway_config` (`Runsheets::Config`): the command
  line beats `RUNSHEETS_*` environment variables (`RUNSHEETS_PORT`,
  `RUNSHEETS_BIND`, `RUNSHEETS_RUNS_DIR`, `RUNSHEETS_OPEN`, `RUNSHEETS_CHECK`,
  `RUNSHEETS_INIT`, `RUNSHEETS_DUMP`, and `RUNSHEETS_DIR` for the `RUNBOOK` argument), which beat
  the project config `./config/runsheets.yml` (or the file `--config FILE` /
  `RUNSHEETS_CONFIG` names), which beats the XDG user config
  `~/.config/runsheets/runsheets.yml`, which beats the bundled
  `lib/runsheets/config/defaults.yml`. `--no-open`, `--no-check` and `--no-init` switch a
  flag off that a lower layer turned on. `Runsheets.config` exposes the
  settings in force; `Runsheets.configure` installs others.
- `runsheets --dump` prints the settings in force in the shape of a config
  file to stdout and exits; redirect it to save a run's options as the
  defaults for later runs. `RUNSHEETS_DUMP` and `--no-dump` as for any flag.
- Single-file runbooks: `runsheets path/to/file.md` reads one markdown
  file whose `##` headings are the steps, with step attributes in an HTML
  comment after the heading and Verify and Rollback sections standing in
  for `verify.md` and `rollback.md` (`Runsheets::SingleFile`).
- A language mapped under `interpreters` in the front matter now executes;
  `sql run` through `psql` works. Previously the mapping was honoured at
  spawn time but blocks were classified against the built-in languages
  only, so such blocks warned and had no Run button.
- `runsheets --init PATH` scaffolds a starter runbook (directory, or a
  single file when the path ends in `.md`) that passes `--check`.
- `examples/staging-teardown` (directory, the shape of a real AWS
  teardown) and `examples/db-maintenance.md` (single file, `sql run`
  blocks via `psql`).
- `examples/disk-space-triage.md`: a safe single-file runbook whose steps
  link to plain markdown documents in the examples directory (a glossary,
  a cleanup policy with an SVG diagram, and an overview of the examples).
  None of them has runbook front matter, so none appears in the tree.
- Vocabulary: the record of a run is the *runsheet* in the page, sidebar
  and buttons.

### Changed

- A run is no longer started, finished or abandoned by hand, and there are
  no verification runs: `POST /run`, `POST /run/finish`,
  `POST /library/open`, the Finish, Abandon and Verify only buttons, and
  the rule that refused switching runbooks during a run are gone. The
  Checks page and Run all work inside the runbook's run. Older records
  still load.
- The `last_verified` front matter key and the offer to stamp it into the
  runbook are gone, along with the `verified` history verdict. runsheets
  never writes inside a runbook directory.
- A markdown file is a runbook only when it starts with YAML front matter
  that has a `title`. A `runbook.md` or single-file runbook without one no
  longer loads (it was a warning), and a library leaves such files out of
  its tree as plain documents.
- The executable is `runsheets`, the same name as the gem (was `runsheet`).
- `-c` is now short for `--config`; `--check` has no short form.
- `myway_config` is a runtime dependency.
- `runsheets` with no RUNBOOK serves the bundled `examples/hello`. `--init`
  still needs an explicit path.
- The `runsheets` executable lives in `bin/` (was `exe/`); `bin/console` and
  `bin/setup` are gone, so `bin/` holds only what the gem installs.
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
- Run history: `RunRecord#latest_executions`, `unresolved_failures`,
  `last_step`. The history list shows kind, status, start time, duration, counts, and the step a run stopped at.
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

- `runsheets RUNBOOK_DIR` serves a runbook directory on loopback; `--check`
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
