# Changelog

## [Unreleased]

### Added

- `runsheets --new [DIR]` asks what kind of runbook to make (a directory or a
  single file, a template, a name, a title, when to use it and who to call)
  and writes it into `DIR`. Enter accepts each default, and answers can be
  piped in. Without `DIR` it asks for one, offering the `dir:` a config file
  sets, else `RUNSHEETS_DIR`.
- Runbook templates in `templates/`, a ladder of structure: `checks` (checks
  only), `tasks` (checks and tasks, the default), `rollback`, `timeouts`,
  `inputs` and `asgard` (tasks in `.loki` files beside the runbook). Each is
  written once as a directory runbook and produces either shape; a single
  file from a template with support files gets a folder of its own.

### Removed

- `--init`, `--no-init`, `RUNSHEETS_INIT` and the `init` setting. Use
  `--new`; the `tasks` template is the nearest to what `--init` wrote.

## [0.0.1] - 2026-10-11

First release. runsheets turns a markdown runbook into a local web page
where marked commands get a Run button, and records everything that
happens during a run as a *runsheet*.

### Runbooks

- A runbook is a directory (`runbook.md` with YAML front matter, ordered
  `steps/`, optional `verify.md` and `rollback.md`) or a single markdown
  file whose `##` headings are the steps.
- Front matter declares `inputs` (with secrets) and `interpreters` that map
  other languages, such as `sql` through `psql`, to a command.
- `runsheets --init PATH` scaffolds a starter runbook; `runsheets --check`
  reports authoring warnings.
- Runbooks are re-read when their files change on disk.

### The fenced block convention

- The info string marks a block as `run`, `destructive`, `background`,
  `terminal` or `expect`.
- `run` blocks execute `bash`, `sh`, `zsh`, `ruby` or any mapped language
  as a fresh process group with a per-step timeout.
- `destructive` blocks need a typed confirmation, checked on the server.
- `background` blocks get Start and Stop buttons and appear in a Running
  panel on every page.
- `terminal` blocks are run by the operator, who confirms with "I ran this"
  and an optional note.
- `text expect` blocks are compared with the output of the block above
  them. `{{any}}` matches text that changes on each run, and a mismatch
  shows the output and the expected text side by side with the differences
  highlighted.

### Libraries, search and documents

- `runsheets DIR` on a folder of runbooks opens a library: a folder tree
  with a filter box, each folder's `README.md`, and a summary of each
  runbook with its inputs, steps and previous runs.
- Full-text search across every runbook in the library, with ranked
  results and highlighted snippets.
- Relative links to other markdown files open as pages: another runbook,
  or a plain document with nothing executable.
- A Checks page gathers every verify document and runs them all with one
  button.

### Sessions and the run record

- Everything between starting and stopping runsheets is one session, with
  an engineer and a reason (from the start page, or `--engineer` and
  `--why`).
- The session page holds timestamped notes, every run's progress, the tail
  of the session log, and an End session button. Ending a session, or
  Ctrl-C, closes each run as `completed`, `partial` or `opened`. A session
  left open by a killed process is closed as `interrupted` at the next
  start.
- Each run records the exact command, output, exit status, timing, step
  acknowledgements and notes in `run.json` and a readable `run.md`.
- `session.log` records every action and line of output, timestamped and
  levelled, and echoes it to the terminal.
- Run history, and a diff for every block whose code has changed since a
  past run.

### Security

- Binds to loopback by default. Every request needs the session key the
  printed `?token=` link gives the browser as a cookie, so other accounts
  on the machine see nothing; every state-changing request also needs the
  per-process session token and an allowed Host header.
- Secret inputs are redacted from output and logs, however the output is
  split, and never written back into the page.
- Every page has a Content-Security-Policy with a per-response nonce, so a
  `<script>` in a runbook's markdown does not run, and the page's script
  acts only on blocks runsheets rendered, so a copied Run button does
  nothing. Run refuses a block edited since the page loaded. Files served
  from a runbook are sandboxed and cannot follow a symlink out of it.
- Anything a block leaves running in its process group is stopped when
  the block finishes.
- A project `./config/runsheets.yml` cannot by itself bind runsheets to a
  non-loopback address.

### Settings

- Layered settings through `myway_config`. Command-line flags override
  `RUNSHEETS_*` environment variables, which override `./config/runsheets.yml`,
  which overrides `~/.config/runsheets/runsheets.yml`, which overrides the
  bundled defaults.
- `runsheets --dump` prints the settings in force as a config file.

### Examples

- `examples/` holds directory and single-file runbooks: `hello`,
  `staging-teardown`, `db-maintenance.md`, `disk-space-triage.md` with the
  plain documents it links to, and `asgard-tasks.md`, whose blocks call
  asgard tasks.
