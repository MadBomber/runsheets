# runsheets — Executable Runbook Viewer

Plan and discussion log for `runsheets`, an open-source tool that turns a directory of
markdown files into an executable, recorded runbook served in the browser.

Status: all four milestones built and passing (see the 2026-10-07 and 2026-10-08 log). What remains is use against real runbooks.
Started: 2026-10-07.
Repo: `~/sandbox/git_repos/madbomber/runsheets`. Origin copy of this plan: `~/scripts/runbook_plan.md`.

## Contents

- [Why](#why)
- [Decisions so far](#decisions-so-far)
- [Document structure](#document-structure)
- [Fenced block convention](#fenced-block-convention)
- [Inputs and secrets](#inputs-and-secrets)
- [Execution model](#execution-model)
- [The run record](#the-run-record)
- [Architecture](#architecture)
- [Security posture](#security-posture)
- [Sessions (milestone 5 design)](#sessions-milestone-5-design)
- [Activity database (milestone 6 design)](#activity-database-milestone-6-design)
- [Rails engine (milestone 7 design)](#rails-engine-milestone-7-design)
- [Milestones](#milestones)
- [Open questions](#open-questions)
- [Discussion log](#discussion-log)

## Why

Operational runbooks are prose with commands in them. An operator reads a step, copies
the command into a terminal, eyeballs the output, and moves on. Nothing records what
was run, what came back, or who confirmed the manual steps. The authoring guidance in
the project that prompted this (xyzzy, see the log) asks operators to "test the runbook
by following it" and to "date the last verification" by hand, and neither happens
reliably.

`runsheets` closes that gap:

- the runbook renders as HTML, so it reads as well as any doc site
- fenced blocks the author marks as executable get a Run button
- every execution and its output is captured, in order, into a run record
- manual steps are acknowledged by the operator and that acknowledgement is recorded

The rendering is the vehicle. The run record is the point.

## Decisions so far

| Decision | Choice | Why |
| --- | --- | --- |
| Name | `runsheets` gem, `runsheets` command | `runbook` and `rb` are taken on RubyGems; `myrb` and `mrb` are taken and `mrb` is the mruby ecosystem's own abbreviation; `livedoc` already means living documentation in BDD circles and is taken on npm and PyPI. `runsheets` was free on RubyGems, npm, PyPI, Homebrew and PATH on 2026-10-07. A runsheet is the theatre and broadcast term for the timed, ordered list of what happens, which matches "the run record is the point". |
| Project home | Standalone open-source project, not part of xyzzy | Generic tool; xyzzy's gates (95% per-file coverage, Trunk) would be a tax on a shell-heavy tool. xyzzy's runbooks are inspiration only. |
| GUI or CLI | Browser GUI served from a local Sinatra process | Markdown renders properly; the page is a natural home for the run log. Terminal markdown is possible but not pleasant. |
| Attached or detached | Detached (runs on the operator's machine or devcontainer) | The blocks are shell against the operator's environment: SSO sessions, tunnels, local DBs, `gh`. None of that exists inside a deployed app process, and executing markdown blocks in a web app is a security hole. |
| Executability | Opt-in per block via the info string | Real runbooks mix runnable shell, expected-output samples, config to copy, SQL for a separate client, and destructive commands. Default must be "display only". |
| Document shape | A directory per runbook with one file per step; a single file with `##` steps is also read (milestone 4) | The directory suits authoring; the single file is how every existing runbook already looks, so it is read directly. Step attributes in a single file go in an HTML comment after the heading, invisible to every other renderer. |
| Vocabulary | The document is the *runbook*; the record of one run is the *runsheet* | Closer to the theatre meaning, keeps the record in the product name, and the page already distinguished the two. Settled in milestone 4. |
| Process model | Fresh process per block, own process group | Blocks stay copy-pasteable and reproducible; timeouts can kill the whole group. A `capture` flag to pass one block's stdout to later blocks is deferred until a runbook needs it. |
| Output | Every execution writes to a log file; the page polls | One spawn path for `run` and the future `background`; a ten-minute `--wait` shows its output as it arrives instead of looking hung. |
| Interpreters | `interpreters:` in runbook.md front matter maps a language to a command | xyzzy's Ruby snippets need `bin/rails runner -`; the same mechanism will route `sql` through `psql` when needed. |
| Browser security | Per-process token in a meta tag, required on every non-GET request, plus loopback-only Host authorization | A page on another origin can neither read the token nor send the custom header without a preflight the app never answers; the Host check defeats DNS rebinding. |
| Destructive confirmation | Server issues a random four-character code per block (HTTP 428), runs the block only when it comes back, retires it once used | The review's point: a typed slug becomes muscle memory. Checking server-side means a script driving the API cannot skip it either. The record notes the execution was confirmed. |
| Redaction | Child output goes through a pipe and a reader thread that replaces secret values before writing the `.out` file, holding back a tail that could be a partial secret | Letting the child write the file directly made redaction impossible. Plain string replacement; encoded secrets are documented as out of scope. |
| Stopped is not failed | Operator stops and run-end stops record state `stopped`, distinct from `timed_out` | A background tunnel stopped on purpose must not mark the step failed. |
| Standalone verification | A run of kind `verify` that may execute only verify documents, with its own record | Keeps "every execution belongs to a record" true; the alternative (executing verify blocks with no run) would have been the one unrecorded path. |
| `last_verified` | Dropped 2026-10-09 (it was a front matter date stamped after a run that exercised the whole runbook) | It never said what "verified" meant: not that the prose was right, not that output was correct, and not tied to the runbook's content, so an edit the next day left the stamp standing. A runbook-wide date also fits sessions and pick-and-choose step execution badly. May come back as per-step dates computed from run history. |
| Live reload | The session re-reads the runbook on a GET when a source file's mtime is newer than the load | Drift must compare against the file on disk, and editing a runbook with the server up is the natural authoring loop inherited from tdv.rb. |
| Lineage | Builds on `~/scripts/tdv.rb` | Sinatra + kramdown GFM + rouge, directory index, breadcrumbs, search, sidebar outline. Reuse the layout and rendering; add execution and recording. |
| Scripting language | Ruby, standard library plus the few gems tdv.rb already uses | Matches the author's tooling. |

## Document structure

A runbook is a directory. Its name is the runbook's slug.

```text
runbooks/
  staging-teardown/
    runbook.md              # front matter + preamble (required)
    steps/
      010-confirm-nothing-to-preserve.md
      020-stop-the-pipeline.md
      030-drain-ecs-services.md
      ...
    verify.md               # whole-procedure verification (optional)
    rollback.md             # what to do when it fails partway (optional)
    assets/                 # images, SVG diagrams referenced by the markdown
```

### `runbook.md`

Front matter carries what the authoring guidance says every runbook needs before the
first step, so the tool can show it on the landing page and refuse to start when
prerequisites are unmet.

```yaml
---
title: Staging Infrastructure Teardown and Rebuild
when_to_use: >
  The deployed stacks cannot be updated in place and an in-place deploy
  fails deterministically.
prerequisites:
  - AWSAdministratorAccess in account 123456789012
  - The staging branch is ready to fast-forward
blast_radius: >
  Destroys the staging database, container images, and DNS. Irreversible
  once Step 5 starts.
escalation: Stop and contact the platform owner if any stack delete fails twice.
tags: [aws, staging, destructive]
inputs:
  - name: AWS_PROFILE
    prompt: AWS profile with admin access
    default: xyzzy-sandbox-admin
  - name: SNAPSHOT_ID
    prompt: Identifier for the pre-teardown snapshot
    default: xyzzy-staging-final-preteardown
---
```

Everything below the front matter is the preamble and renders as-is.

### Step files

Steps are the markdown files in `steps/`, ordered by filename. A numeric prefix with
gaps (`010`, `020`) leaves room to insert. Each step has front matter and a body.

```yaml
---
title: Drain the ECS services
kind: automated          # automated | manual | verify
destructive: false
timeout: 600             # seconds, for run blocks in this step
---
```

- `automated`: the body contains at least one executable block. The step is complete
  when the operator has run them and marks it done.
- `manual`: no executable blocks are expected. The body is an instruction. The step is
  complete when the operator ticks it, optionally with a note.
- `verify`: a read-only check. Runs during the procedure and also standalone from the
  landing page at any time.

The body is ordinary markdown: the instruction, the command, and the "how to tell it
worked" line that every good step carries.

### `verify.md` and `rollback.md`

Optional. `verify.md` holds whole-procedure checks, run after the last step or on
demand. `rollback.md` renders in a sidebar panel on every step page so it is one click
away when something goes wrong, and never needs scrolling to find.

## Fenced block convention

The info string's first word is the language. Any following words are flags. A block
with no flag is display only, whatever its language.

| Info string | Behaviour |
| --- | --- |
| ```` ```bash ```` | Display only. Rendered with highlighting, no Run button. |
| ```` ```bash run ```` | Run button. Executed with the runbook's inputs in the environment, stdout and stderr captured, exit status recorded. |
| ```` ```bash background ```` | Start and Stop buttons. For long-running processes such as a tunnel. Output streams to the page and the process is tracked until stopped or the run ends. |
| ```` ```bash destructive ```` | Run button behind a typed confirmation (the runbook slug). Implies `run`. The step page is marked with the blast-radius banner. |
| ```` ```bash terminal ```` | No Run button. "Run this in your own terminal, then confirm." For anything interactive: `read -s`, an SSO login that needs a browser, an interactive `psql` session. Confirmation is recorded like a manual step. |
| ```` ```ruby run ```` | Same as `bash run`, executed with `ruby`. |
| ```` ```text expect ```` | Not executed. Shown beside the preceding executable block as the expected output. Used only as a visual hint; it does not gate pass or fail. |

Rules:

- Only `bash` and `ruby` execute in the first version. `sql`, `python` and others stay
  display only until there is a real need and a safe way to route them.
- Flags are additive where it makes sense (`bash run destructive` and `bash destructive`
  are the same thing).
- An unknown flag is an authoring error and renders with a visible warning rather than
  being silently ignored.

## Inputs and secrets

`inputs` in `runbook.md` front matter become a form on the landing page. Values are
exported as environment variables to every executed block in that run, so blocks
reference them as `$NAME`, which keeps the markdown copy-pasteable into a terminal.

- `default` pre-fills the form.
- `secret: true` masks the field, excludes the value from the run record, and redacts
  any occurrence of it in captured output before the output is stored.
- Inputs can also be seeded from the environment `runsheets` was started in, so a
  devcontainer with `AWS_PROFILE` already set needs no typing.

The tool never stores credentials. A runbook that needs one asks for it through a
`secret` input or hands the step to the operator's terminal.

## Execution model

- One run at a time per runbook. Starting a run creates a run record and a working
  directory for captured output.
- `run` blocks execute synchronously from the page's point of view: the button
  disables, output appears when the process exits, the exit status is shown as
  pass or fail. A `timeout` in the step front matter bounds it.
- `background` blocks are spawned, their output tailed into the page by polling, and
  listed in a "running processes" panel. Ending the run stops anything still running.
- Executed blocks run with the runbook directory as the working directory unless the
  step front matter sets `cwd`.
- Steps are visited in order but the operator can jump. The run record keeps the real
  sequence, so skipping is visible in the log rather than hidden.
- Nothing re-runs on page reload. A block that was run shows its last result; the
  operator can run it again, and both executions are recorded.

## The run record

Each run writes to a directory outside the runbook:

```text
~/.local/share/rb/runs/<runbook-slug>/<ISO-8601 start>/
  run.json          # machine-readable: steps, blocks, timestamps, exit codes, acks
  run.md            # human-readable transcript of the same, rendered in the UI
  blocks/
    020-1.out       # stdout + stderr of each executed block, in execution order
    020-1.cmd       # the exact command text that ran
```

Why outside the runbook: captured output may contain account-scoped data that does not
belong in a repository next to the docs. The runbook directory stays clean and
committable.

The tool never writes inside the runbook directory.

The landing page lists previous runs for the runbook with start time, duration, steps
completed, and whether any block failed, so the history is browsable without opening
files.

## Architecture

Start where `tdv.rb` is: a single Ruby file, Sinatra, kramdown with the GFM parser,
rouge for highlighting, bound to `127.0.0.1`. Keep its index, breadcrumb, search and
outline layout. Add:

- a `Runbook` model built from a directory (front matter, ordered steps, verify,
  rollback)
- a block parser that reads info strings and tags each fenced block with its
  behaviour before kramdown renders it, so the rendered HTML carries the data
  attributes the buttons need
- an `Execution` layer using `Open3` for `run` blocks and `Process.spawn` with a log
  file for `background`
- a `RunRecord` that appends events and writes `run.json` and `run.md`
- routes: landing page, step page, run start and end, execute block, stop background
  process, run history, verify-only

Keep the first version small enough to stay one file. Graduate to a gem with a
`bin/` entry point once the block convention has survived contact with two or three
real runbooks.

Tests: minitest, with the execution layer behind an interface so block parsing, run
recording and rendering are tested without spawning processes.

## Security posture

- Binds to loopback only. There is no multi-user story and there should not be one.
- Executes only blocks whose info string opts in. Everything else is inert text.
- Destructive blocks require typed confirmation and show the blast radius first.
- Secrets never reach the run record. Redaction runs over captured output before it is
  written.
- The tool never modifies anything in the runbook directory.
- No remote execution, no agent, no daemon. It is a script an operator starts and
  stops.

## Sessions (milestone 5 design)

Proposed 2026-10-09, not built. Using runsheets on a library showed that one run per
runbook, started and finished by hand, is the wrong unit. An engineer sits down for a
reason (a shift, an incident, a change window), works through parts of several
runbooks, and stops. The record should look like that.

### The model

- **Session.** Everything that happens between the `runsheets` process starting and
  terminating. It belongs to one engineer, and opens with a note saying why. It is the
  engineer's notebook.
- **Run.** One runbook's part of a session. Selecting a runbook establishes its run;
  selecting it again later in the same session returns to the same run. Within it
  the engineer works through the steps in sequence, or picks only the steps they
  need, in any order.
- **Switching.** Selecting a different runbook keeps the session going and leaves the
  earlier run open. Nothing has to be finished first.
- **Ending.** Runs are not finished one by one. Every run open in a session ends when
  the session ends, and the session ends when the process terminates.

### Flow

1. `runsheets` starts. Before anything else the session needs **who** and **why**.
   The browser opens on a Start session page with two fields: engineer (prefilled,
   see below) and why (free text, required). The why is not a separate field of the
   session: it is the first timestamped entry in the session notes. `--engineer` and `--why` on the
   command line (or `RUNSHEETS_ENGINEER`, `RUNSHEETS_WHY`, config `engineer:`)
   fill them in and skip the page. Engineer prefill: config, then `git config
   user.name`, then `$USER`. The engineer is self-asserted, not authenticated; it
   says who claimed to be at the keyboard.
2. The engineer selects a runbook from the library (or the only runbook, when started
   on one). The runbook's inputs form appears; submitting it establishes the run and
   lands on the runbook page.
3. On the runbook page: **Work through the steps** goes to step 1 with prev/next as
   today; any step in the list can be opened and run directly. Run buttons are live
   on every step page of a runbook that has a run in this session.
4. Switching: the library is always reachable. Selecting another runbook establishes
   (or returns to) its run. The header shows the session (engineer, the opening note, elapsed)
   and the runbooks with runs in it.
5. Ending: Ctrl-C in the terminal, or an **End session** button that ends the session
   and stops the server. Either way every background process is stopped and every run
   and the session are closed and written.

### What changes

- **Run end status** is derived when the session ends, not chosen: `completed` when
  every step is done or skipped, `partial` when anything was executed or marked but not
  every step, `opened` when the runbook was selected and nothing was done. A session
  (and its runs) still marked running at startup (the process was killed) is closed as
  `interrupted` by the next start.
- **No Start run / Finish / Abandon buttons.** Selecting a runbook starts its run; the
  session's end finishes it.
- **Verification is not a separate run kind.** The Checks page and **Run all** work
  inside the runbook's run.
- **Inputs** belong to a run. A value given for a same-named input earlier in the
  session is offered as the default. Secrets are never carried between runs.
  Changing an input mid-run is an `inputs` event in the record.
- **Background processes** keep running when the engineer switches runbooks. The
  Running panel lists every one in the session with its runbook.
- **One session per process.** Two engineers, or two sessions, means two processes on
  two ports, as today.

### Session notes

Decided 2026-10-09. The session page has a free-text notes box; every entry is
timestamped and goes into the session timeline. The why given at the start is the
first note, nothing more. A session is a session whatever is being done in it: when
maintenance turns into an incident, the engineer writes a note; there is no reason
field to amend.

### Session log

Proposed 2026-10-10. Every session writes a `session.log`: a plain text file, appended
as things happen, in the spirit of a Rails log. Every engineering action is a
timestamped line, and the output an action produces is written into the log as it
arrives. It is the session's notebook in its most durable and most readable form:
`tail -f` it during the session, `grep` it afterwards, read it without runsheets.

```text
2026-10-10 14:02:05.120 INFO  [session] started engineer="Dewayne VanHoozer" host=darmok pid=1472 runsheets=0.0.1
2026-10-10 14:02:05.121 INFO  [session] note: Monthly maintenance on the app database
2026-10-10 14:02:30.010 INFO  [db-maintenance] run opened inputs PGHOST=localhost PGUSER=app_owner PGPASSWORD=[secret]
2026-10-10 14:02:41.200 INFO  [db-maintenance 010-check-the-connection #1a2b] execute sql via psql -X -v ON_ERROR_STOP=1 --pset footer=off -f …
2026-10-10 14:02:41.200 INFO  [#1a2b] $ select current_database() as database, current_user as role, version();
2026-10-10 14:02:41.540 INFO  [#1a2b] >  database |   role    | version
2026-10-10 14:02:41.540 INFO  [#1a2b] > ----------+-----------+------------------------------
2026-10-10 14:02:41.541 INFO  [#1a2b] finished exit 0 in 0.34s
2026-10-10 14:03:10.002 INFO  [db-maintenance 010-check-the-connection] marked done: connection fine
2026-10-10 14:20:44.900 INFO  [session] ended (Ctrl-C) runs: db-maintenance partial
```

- **One event per line.** Timestamp to the millisecond, then tags in brackets naming
  where it happened (`session`, the runbook, the step, the execution), then the event.
  Multi-line text (a note, the code that ran) is one line per source line, each with the
  same prefix, so every line of the file stands alone under `grep`.
- **Code and output are marked.** `$` lines are the code that ran, `>` lines its output.
  Output is written line by line as it arrives, each line tagged with its execution id,
  so output from a background block and a foreground block running together stays
  attributable: `grep '#1a2b'` extracts one execution.
- **What is logged.** Every state change: session start and end (and how it ended),
  notes, runbook selected, inputs (secret values as `[secret]`), execute (the
  interpreter command and the code), destructive confirmation, stop, exit status and
  duration, timeouts, terminal acknowledgements with their notes, step marks with their
  notes. Page views and searches only with `--verbose`.
- **Redaction.** The log goes through the same redactor as captured output; secret
  values never reach it.
- **Durability.** Opened in append mode and flushed after every line, so a crash or a
  `kill -9` leaves everything up to that moment on disk. The next start notes the
  interrupted session in its own log.
- **Terminal echo.** The terminal that started `runsheets` shows the log live, the way
  `rails server` shows the development log. On by default (decided 2026-10-10);
  `--quiet` turns it off.
- **Where.** `<runs-dir>/sessions/<session-id>/session.log`, one file per session, so
  there is nothing to rotate.

**Levels** (decided 2026-10-10): the Rails log levels, which are Ruby `Logger`'s.
Each line carries its level after the timestamp (`INFO`, `WARN`, ...).

| Level | What |
| --- | --- |
| `debug` | Page views, searches, polling, reloads of a changed runbook, the full environment handed to an execution (secrets as `[secret]`) |
| `info` | Every engineering action and its output: session start and end, notes, runbook selected, inputs, execute and the code, output lines, exit 0, stop, step marks, acknowledgements |
| `warn` | A block that exits non-zero or times out, a refused action (no active run, wrong confirmation code), authoring warnings when a runbook loads, an interrupted earlier session found at startup |
| `error` | An execution that cannot start, a runbook that no longer loads, an exception inside the server |
| `fatal` | The server cannot start or is going down on an error |

`log_level` sets the file's level (default `info`; `--log-level`, `RUNSHEETS_LOG_LEVEL`,
`--verbose` for `debug`). The terminal echo has its own level, default `info`, so a
`debug` file does not flood the terminal. The level is a floor: the file at `info` holds
every action and every line of output, which is the point of the log.

**Logger** (decided 2026-10-10): Ruby's standard `Logger`, behind a small
`Runsheets::SessionLog` with the same interface. `SessionLog` adds the bracketed tags
(session, runbook, step, execution) through a formatter and fans each entry out to two
`Logger`s, the file and the terminal, each with its own level. No new dependency.
Considered:

- **lumberjack** (2.1.0): an extension of `Logger` with structured attributes per
  entry, per-thread context, formatters and several devices, depending only on
  `logger`. The natural upgrade if each line should also carry structured fields (to
  feed the activity database, milestone 6) or write through a host's logger in the
  Rails engine (`lumberjack_rails`, milestone 7). Because `SessionLog` keeps the
  `Logger` interface, swapping it in touches one class.
- **lograge**: not a fit. It turns a Rails application's request logging into one
  line per request and depends on `actionpack`, `railties` and `activesupport`;
  runsheets is not a Rails app, and the session log is about actions, not requests.

How it relates to the other records:

- It replaces the planned `session.md` and, in time, `run.md`: the log is the
  human-readable transcript, written as it happens rather than generated afterwards.
- The per-execution `.out` files stay (decided 2026-10-10). They hold each execution's
  output on its own, which is what the step page shows and drift compares; the log
  holds the same output in the session's order.
- With the activity database (milestone 6), the database holds the structure for
  queries and the log holds the narrative. A row can carry the log's byte offset where
  its event starts, so the session page can jump into the log.

### Records

```text
<runs-dir>/
  sessions/<session-id>/
    session.log       every action and its output, appended as it happens
    session.json      engineer, host, started_at, ended_at, status,
                      runs (runbook slug + run dir, in the order first selected),
                      notes, and a merged timeline of every event
  <runbook-slug>/<session-id>/
    run.json          as today, plus "session": "<session-id>"; no "kind"
    run.md
    blocks/
```

If the activity database (milestone 6) is built first, this layout shrinks to the
output files; sessions, runs and notes live in the database.

The run directory is named by the session id, so a runbook's history stays under its
slug (the landing page's previous runs and drift need no other index) and
each run points back to its session. Records written before sessions (no `session`
field, a `kind` field) stay readable.

### HTTP

- `GET /session/new`, `POST /session`: the start page and form. Every other page
  redirects to it until the session exists.
- `POST /session/end`: closes everything and stops the server.
- `POST /runs` with a runbook slug and inputs: establishes or returns to that
  runbook's run. Replaces `POST /run` and `POST /library/open`.
- `POST /run/finish` and the `kind=verify` start go away.
- `GET /session`: the session page (the notebook so far), linked from the header.

### Open questions

- **Idle sessions.** A server left running for days is one long session. Warn on the
  session page after some hours, or leave it to the engineer?

## Activity database (milestone 6 design)

Proposed 2026-10-10, not built. Today every run is a directory of files under the runs
directory, and each runbook's history is found by listing its folder. That works for one
runbook at a time. Sessions (milestone 5) make the record cross-cutting: a session
spans runbooks, a run belongs to a session, notes and executions interleave on one
timeline. The questions an engineer or a reviewer asks next are cross-cutting too:

- What did this engineer do last Tuesday, across every runbook?
- Every time step `030-drain-ecs-services` ran: when, by whom, with what result, and on
  which version of the step?
- Which sessions touched the staging teardown runbook during the incident window?
- Which blocks fail most often? Which steps are never run at all?
- Search the session notes for "rollback".

Answering those from directories of JSON means reading every file every time. A
SQLite database answers them with a query, and ties sessions, runs, runbooks, steps and
executions together by key instead of by folder name.

### What goes where

| Kept in | What | Why |
| --- | --- | --- |
| SQLite | Sessions, notes, runs, step marks, acknowledgements, executions (command, state, exit status, timing, paths), the runbooks and step versions they ran against, the event timeline | Small, structured, relational; the cross-cutting queries need it; one transaction per event keeps the timeline consistent |
| Files | `session.log`, and each execution's `.cmd` and `.out` | Output can be large and is streamed as it arrives; it is already redacted before it is written; files stay greppable; the log is the narrative a person reads (see Session log under milestone 5) |
| Generated | `run.md`, `session.md` transcripts and `run.json` exports | Written from the database on demand and once more when the session ends, as the human-readable archive |

Recommendation: the database is the system of record for structure, and the output files
stay files. The alternative, keeping today's files as the record and the database as an
index rebuilt from them, avoids a second source of truth but means two writes per event
and a rebuild step whenever they disagree. Run records written before the database are
brought in once by `runsheets --import`.

### Schema sketch

```text
sessions        id, engineer, host, pid, started_at, ended_at, status
notes           id, session_id, at, text                  -- the first note is the why
runbooks        id, root, slug, path, title                -- unique (root, slug)
runbook_versions id, runbook_id, digest, seen_at           -- digest of the source files
steps           id, runbook_version_id, slug, position, title, kind, digest
runs            id, session_id, runbook_id, runbook_version_id, started_at, ended_at,
                status, inputs_json                        -- non-secret inputs only
step_marks      id, run_id, step_slug, status, note, at
acks            id, run_id, block_id, note, at
executions      id, run_id, step_id, block_id, command, cmd_path, out_path, state,
                exit_status, started_at, finished_at, duration, confirmed
events          id, session_id, run_id, at, type, ref_id   -- the merged timeline
runbook_fts     FTS5 over runbook titles, front matter prose and document bodies
notes_fts       FTS5 over session notes
```

Step and runbook versions are content digests, so a record always says which text ran.
That also gives drift for free and is what per-step "last worked" dates would be built on
if they come back (see the `last_verified` decision).

### Details

- **Location.** `~/.local/share/runsheets/runsheets.db`, beside the runs directory, and a
  `database` setting (`--database`, `RUNSHEETS_DATABASE`) to move it. One database per
  user across every library; a runbook is identified by the library root plus its slug.
- **Library.** The `sqlite3` gem, plain SQL behind a small `Runsheets::Store` class; no ORM.
  Schema versions through `PRAGMA user_version` and numbered migrations in the gem.
- **Store interface.** Everything above `Store` asks it questions (`record_execution`,
  `history_for(runbook)`, `step_history(step)`, `session_timeline(id)`); nothing else
  writes SQL. A Rails engine (milestone 7) supplies an ActiveRecord-backed store with the
  same methods.
- **Concurrency.** WAL mode and a busy timeout, so two `runsheets` processes (two
  engineers, two ports) can share one database. Not for a network file system.
- **Secrets.** Secret input values are never stored, as today. Captured output is
  already redacted before it reaches disk. The database file is created `0600`.
- **Search.** The in-memory search stays; FTS5 is the upgrade path when libraries grow
  large, and it is what makes session notes searchable.
- **Retention.** Records accumulate forever unless pruned. A `runsheets --prune DAYS`
  that deletes old sessions with their output files, and nothing automatic.

### Order

Build the database before or together with sessions. Sessions designed on top of files
(the Records section of milestone 5) would be written once for files and again for the
database. With the database first, the session page, the timeline and notes are queries.

### Open questions

- **Source of truth.** Database for structure and files for output (recommended), or
  files as the record with a rebuildable index?
- **Shared database.** One per user (proposed), or a team database on a shared host? A
  shared one changes the security model: other people's records and notes become visible.
- **Dependency.** `sqlite3` is a native gem. Precompiled builds cover macOS arm64 and
  Linux; acceptable for a tool that today needs only pure-Ruby gems?

## Rails engine (milestone 7 design)

Proposed 2026-10-10, not built. Package runsheets as a Rails engine that a larger
Rails application mounts in its admin panel, so operators find the runbooks, their
history and their sessions where they already work.

### The tension with the original decision

The Decisions table says runsheets is detached, a process on the operator's own
machine, because "executing markdown blocks in a web app is a security hole" and because
the blocks need the operator's environment (SSO sessions, tunnels, local tools). Mounted
in a deployed app, both are true again:

- A Run button would execute shell on an application server, as the application's user,
  with the application's credentials and network reach, for anyone the admin panel
  admits.
- The operator's terminal environment is not there: no `aws sso login`, no VPN, no
  tunnel.

So the engine cannot simply be today's app behind a mount point. It needs an explicit
execution policy.

### Execution policy

Three modes, chosen by the host application, most restrictive by default:

1. **Read and record (default).** Every executable block renders as a `terminal`
   block: the operator copies the command, runs it where it belongs, and confirms with
   a note. Nothing executes on the server. Library, search, sessions, notes, step marks,
   history and drift all work. This alone covers the admin-panel use: the procedure,
   the record of who did what, and the audit trail, next to the app they operate.
2. **In-app execution, allowlisted.** The host names the languages that may run on its
   servers, typically `ruby` through `bin/rails runner` or in-process, and maybe `sql`
   against a read replica. Runs go through ActiveJob, never in the web request, with the
   same timeouts, redaction, destructive confirmation and records. Shell stays off unless
   the host turns it on explicitly.
3. **Remote runner (later).** A small `runsheets runner` process on the operator's
   machine connects out to the app, picks up executions the operator started in the
   admin panel, runs them in the operator's environment, and streams output back. The
   page lives in the app; the shell stays on the laptop. This is the only mode that
   brings back what detached runsheets has, and it is a project of its own.

### Shape

- **A separate gem, `runsheets-rails`**, depending on `runsheets`. The core gem keeps the
  runbook model, rendering, search, block convention, records and the CLI; it gains no
  Rails dependency.
- **Mounting.** `mount Runsheets::Engine => "/admin/runsheets"`, inside whatever
  constraint the host already uses for its admin area. A `Runsheets.configure` block
  names the runbooks root (for example `Rails.root.join("docs/runbooks")`), the
  execution mode, and a hook that authorizes each request.
- **Identity.** The engineer is the host's `current_user`, not a name typed at the start
  of a session. Notes and actions are attributed to a real account.
- **Storage.** ActiveRecord models in the host's database behind the same `Store`
  interface as milestone 6, with migrations installed by `bin/rails runsheets:install`.
  Output stays on disk or moves to Active Storage.
- **Security pieces Rails already has.** Its CSRF token replaces the per-process
  session token; its content security policy nonce replaces ours; the Host check and
  loopback binding do not apply and come out of the engine's path.
- **Views.** The pages are built by plain Ruby functions returning HTML today. The engine
  renders them inside the host's admin layout, or the host overrides views. An
  admin-framework adapter (Avo, ActiveAdmin, Administrate) is optional and later; mounting
  under the admin namespace with a menu link is enough to start.
- **Runbooks in the app's repository.** The runbooks ship with the app and are read
  from its deploy directory. runsheets never writes to them, so a read-only deploy is
  fine. The original motivation (xyzzy's `docs/runbooks/` and the `bin/rails runbook`
  idea in XYZZY-180) fits this shape.

### What has to come first

- Milestone 6's `Store` interface, so records are not tied to files.
- The session model (milestone 5), which maps onto "a user working in the admin panel".
- Separating the Sinatra web layer from the pieces the engine reuses: `Pages` should not
  need a `Session` object that owns a process-wide token, and the executor needs a seam
  for ActiveJob and, later, a remote runner.

### Open questions

- **Which mode first.** Read and record only (recommended for the first engine release),
  or allowlisted in-app execution from the start?
- **Who may do what.** One authorization hook, or roles: who may read, run, run
  destructive blocks, see other people's sessions?
- **Multi-user.** Several admins at once, each with their own session; does a runbook's
  run belong to one user, or can two people work one run together?
- **Admin framework.** Is there a specific host app and admin framework in mind? That
  decides how much layout integration is worth building.

## Milestones

1. **Render and run.** Done 2026-10-07. Load a runbook directory, render landing and step pages with
   tdv.rb's layout, execute `bash run` blocks, show output and exit status, write the
   run record. One real runbook converted as the fixture.
2. **The full block set.** Done 2026-10-08. `manual` steps with acknowledgement, `terminal`
   with recorded confirmation, `destructive` with server-checked typed confirmation,
   `background` with start, stop and streaming, `expect` panels beside the real output.
   Inputs form with secrets and redaction of captured output.
3. **Verification and history.** Done 2026-10-08. `verify` steps and `verify.md` runnable
   standalone as a verification run with a Checks page, `last_verified` write-back offered
   after a verified run (removed 2026-10-09), richer run history with verdicts and the step a run stopped at,
   drift diffs on the run record page, rollback sidebar (from milestone 1).
4. **Packaging.** Done 2026-10-08. Gem with an `exe/` entry point, README with the
   document structure and block convention, minitest suite, two realistic sample
   runbooks (a directory and a single file), single-file runbooks, SQL through the
   interpreters map, `runsheets --init`, vocabulary settled. The name was picked on
   2026-10-07.
5. **Sessions.** Designed 2026-10-09, not started; part of the 0.0.1 release. A session per process with an
   engineer and an opening why note; selecting a runbook establishes its run; runs end with the
   session. See [Sessions](#sessions-milestone-5-design).
6. **Activity database.** Designed 2026-10-10, not started. SQLite as the record of
   sessions, runs, steps and executions, with output kept in files, behind a `Store`
   interface. Best built before or with sessions. See
   [Activity database](#activity-database-milestone-6-design).
7. **Rails engine.** Designed 2026-10-10, not started. A `runsheets-rails` gem that a
   Rails application mounts in its admin panel; read-and-record by default, execution
   only by explicit policy. See [Rails engine](#rails-engine-milestone-7-design).

## Open questions

- **Vocabulary.** Settled in milestone 4: the document is the runbook, the recorded run
  is the runsheet (see Decisions).
- **Single-file runbooks.** Settled in milestone 4: supported, with attributes in an HTML
  comment after each `##` heading. The directory layout stays the primary shape.
- **SQL blocks.** Settled in milestone 4: a language mapped under `interpreters` executes;
  `examples/db-maintenance.md` routes `sql run` through `psql` with `PG*` inputs.
- **Output size.** Settled: everything streams to disk; the page shows the last 256 KB
  with a marker, the transcript the last 64 KB.
- **`capture`.** A flag that stores a block's stdout as a named input for later blocks.
  Needs a syntax for the name (`capture=NAME`? a second word?) and a runbook that needs
  it. Left out of milestone 2 on purpose.
- **Whether xyzzy adopts it.** xyzzy's XYZZY-180 currently describes a `bin/rails runbook`
  CLI. If `runsheets` works, that ticket shrinks to restructuring `docs/runbooks/` into the
  directory shape and adding a launcher. Not decided; the ticket is left as written
  until runsheets exists.

## Discussion log

### 2026-10-07

**Origin.** The idea came out of the xyzzy project (the xyzzy repository). Its eight runbooks
under `docs/runbooks/` are prose with copy-paste commands: four Ruby scripts and four
SQL queries in one of them alone. Jira XYZZY-180 was opened for a `bin/rails runbook`
CLI with a step model (automated, manual, verify), per-runbook step classes, and a
single PR to `main`. Dewayne had already prototyped the executable parts outside the
repo as asgard tasks (`staging.loki`, `slims.loki`, `runbook.loki`).

**Shift to a GUI.** Dewayne commented on XYZZY-180 that a GUI makes more sense because
rendering markdown as HTML is far easier than rendering it in a terminal, and raised two
options: a detached stand-alone app for an admin, or an attached admin-only page inside
the Rails app.

**Detached, decided.** The attached option was ruled out rather than weighed. The blocks
are shell against the operator's environment (SSO sessions, SSM tunnels, `gh`, local
databases); none of that exists in a deployed app process; executing markdown blocks
inside a web app is a security problem; and one of the runbooks destroys the app that
would host the page. The operator context is a local shell with the browser alongside,
which is how `tdv.rb` already works.

**The record is the win.** Agreed that the strongest argument for the GUI is not the
rendering but the run record: command, output, exit status, timestamps, and operator
acknowledgements in one place.

**Opt-in execution.** Real runbooks mix runnable shell, interactive commands, SQL for
another client, expected-output samples, config to copy, and destructive commands.
Blocks must opt in to execution through the info string; the default is display only.

**Generic and open source.** Dewayne's direction: `rb.rb` is a generic tool driven by a
directory and sub-directories of markdown files describing the steps of a task, and it
is his own open-source project rather than a xyzzy deliverable. xyzzy's runbooks are
inspiration, but the document structure should be designed for `rb.rb`'s needs rather
than inherited. This file records the plan.

**Review of the plan.** Gaps raised, none yet folded into the sections above:

- *Cross-origin execution.* A loopback Sinatra server with POST routes that spawn
  shell is reachable from any page open in the same browser; same-origin policy
  does not stop a plain form POST. Proposed: random token generated at startup,
  printed in the launch URL, required on every execute route, plus reject requests
  whose `Origin` or `Host` is not the bound address.
- *Per-block process isolation.* Fresh process per block means `cd`, `export` and
  shell variables do not carry between blocks. Proposed: fresh process per block
  (keeps blocks copy-pasteable), with a `capture` flag that stores a block's stdout
  as a named input for later blocks. The alternative is a persistent shell per run.
  Not decided; this choice shapes the most code.
- *Streaming for `run` blocks.* A ten-minute `--wait` with no output looks hung.
  Proposed: every execution writes to a log file and the page tails it, so `run`
  and `background` share one spawn path and differ only in Stop button and whether
  run end kills the process.
- *Interpreter mapping.* xyzzy's Ruby snippets need `bin/rails runner`, not bare
  `ruby`. Proposed: `runbook.md` front matter maps a language to a command
  (`ruby: bin/rails runner -`, `sql: psql "$DATABASE_URL"`). Also answers the SQL
  open question.
- *Unset inputs.* A block referencing `$SNAPSHOT_ID` with a blank value runs with
  an empty string. Proposed: scan block text for `$NAME` / `${NAME}` against
  declared inputs and refuse to run if any referenced input is blank.
- *Timeouts.* Spawn with `pgroup: true` and kill the group, or the timeout kills
  bash and leaves the child CLI running.
- *Smaller.* Redaction by string replacement misses encoded secrets, say so in the
  README. Typed slug for destructive confirmation becomes muscle memory; use a short
  random token shown with the blast radius. Update `last_verified` by line
  replacement, not a YAML dump. Use basic ISO-8601 (`20261007T153000`) for run
  directory names, colons are awkward on macOS and in zips.
- *Single-file runbooks.* Argued for supporting them from milestone 1, since every
  existing runbook (including the xyzzy fixtures) is one file with H2 steps. Make the
  `Runbook` model independent of source shape. Directory layout stays primary.

**Named.** `runsheets` chosen after `rb`, `runbook`, `myrb`, `mrb` and `livedoc`
were checked and rejected (see Decisions). Gem skeleton generated with
`bundle gem runsheets` (minitest, MIT) at `~/sandbox/git_repos/madbomber/runsheets`.
This plan copied in as `PLAN.md`.

**Milestone 1 built.** Gemspec filled in (Ruby 3.4+, sinatra, rackup, puma,
kramdown, kramdown-parser-gfm, rouge). Library layout:

- `front_matter.rb`, `fences.rb`, `block.rb`, `renderer.rb`: markdown to HTML with
  executable blocks wrapped for the page. kramdown's GFM parser only accepts a
  single word as a fence info string, so `Fences` rewrites `bash run` to
  `bash?rs=N` before parsing and a converter subclass wraps block N.
- `step.rb`, `runbook.rb`: the document model, with authoring warnings.
- `execution.rb`, `executor.rb`: spawn with `pgroup: true`, log to a file, reap in a
  thread, TERM then KILL the group on timeout.
- `run_record.rb`: `run.json`, `run.md`, `blocks/<id>.<n>.{cmd,out}`; `list` and
  `load` for history.
- `session.rb`: the active run, in-memory inputs (secrets included), live
  executions; refuses to execute a block that references a blank declared input.
- `web.rb`, `pages.rb`, `assets.rb`, `cli.rb`, `exe/runsheets`.
- `examples/hello`: a safe runbook exercising every block kind, also the test
  fixture. 78 minitest tests, including a rack-test drive of the whole flow.

Decisions taken while building are in the Decisions table (process model, output,
interpreters, browser security). Still open from the review: redaction of secrets
in captured output (milestone 2), typed-token confirmation for destructive blocks
is done client-side only, `last_verified` write-back (milestone 3), single-file
runbooks.

### 2026-10-08

**Milestone 2 built.** The full block set is live; 108 minitest tests.

- `background` blocks execute with no timeout. `Executor#stop` asks the reaper thread
  to TERM then KILL the process group, and the execution ends in a new state
  `stopped`, which `RunRecord.failure?` does not count as a failure. The sidebar has
  a Running panel on every page with Stop buttons; `Session#finish_run` stops
  everything still running and waits up to three seconds before closing the record.
- Output capture moved from a file handle handed to the child to a pipe pumped by a
  thread in the server. That is what makes redaction possible: `Redactor` replaces
  each secret value with `[redacted NAME]`, longest first, and `feed`/`flush` hold
  back a tail that could be the start of a secret so a value split across two
  writes is still caught. The reaper waits up to a second for the pump to drain
  after the child exits, so a grandchild that keeps the pipe open does not stall the
  page.
- Destructive confirmation moved server-side. `Session#execute(id, confirm:)` raises
  `ConfirmationRequired` with a per-block random code; the web layer turns that into
  HTTP 428 and the page prompts for the code. The `execute` event records
  `confirmed: true`.
- `terminal` blocks get an "I ran this" button. `Session#acknowledge` writes an `ack`
  event and `run.json` gains an `acks` map; the transcript shows the confirmation
  inline with executions and step marks.
- `expect` blocks are linked by `Renderer.link_expectations` to the nearest executable
  block above them (`Block#expect_for`). The page shows the expected text beside the
  real output and says whether they match, trailing whitespace ignored. The expect
  block stays where the author put it.
- Smaller: `output_truncated` in execution JSON with a marker in the page; manual
  steps get acknowledgement wording; the active run panel shows secrets as `NAME=•••`;
  `examples/hello` gains step 035 (a background clock) and a redaction check in
  `verify.md`.

Left out on purpose: `capture` (see open questions). Open for milestone 3: `verify`
standalone, `last_verified` write-back, richer history, the vocabulary split.

**Milestone 3 built** (same day). Verification and history; 128 minitest tests.

- `RunRecord` gains `kind` ("run" or "verify"; verify runs get a `-verify` id suffix),
  `verified?(steps:)`, `latest_executions`, `unresolved_failures`, `last_step`,
  `stamp!` (a `stamp` event appended after finish) and `drift(runbook)`, which
  compares each block's recorded `.cmd` with the runbook now via the new
  stdlib-only `Diff` (LCS line diff).
- `Session#start_run(kind:)`; a verification run refuses blocks outside
  `Runbook#verify_documents` (verify-kind steps, then verify.md). `stamp_candidate`
  decides the offer; `stamp!` calls `Runbook.stamp_last_verified`, which replaces (or
  inserts) that one front-matter line, then notes the event and reloads the runbook.
  `refresh_runbook!` reloads when a source file is newer than the load; the web layer
  calls it on every GET, so drift compares against the disk and editing a runbook with
  the server up just works.
- Pages: a Checks page (`/verify`) gathering the verify documents with a "Run all"
  button (the page's `poll` and `execute` now return promises so checks run one at a
  time), a "Verify only" submit on the start form, a stamp offer panel, a history list
  with kind badge, verdict, start time, duration, counts and "stopped at", and a drift
  panel on the run record page.
- `examples/hello` gains step 045, a verify step.

Open for milestone 4: packaging, single-file runbooks, SQL through the interpreters
map, a real converted runbook, `capture`, the vocabulary split.

**Milestone 4 built** (same day). Packaging; 145 minitest tests.

- `Runbook.load` takes a directory or a single markdown file. `SingleFile.split`
  turns the body into a preamble and `##` sections, ignoring headings inside fences,
  decoding an attribute comment (`<!-- kind: verify, timeout: 30 -->`, a YAML flow
  mapping) on the line after a heading, and recognising Verify and Rollback sections
  (or `role:`) as the extras. Steps get `010-slug` style slugs from their position so
  block ids and record files look the same as a directory runbook's. `Step.new`
  takes `data:` to merge over front matter.
- Bug found while proving SQL: `Block#executable?` and `Block.classify` consulted the
  built-in `INTERPRETERS` only, so a front-matter mapping for `sql` was honoured at
  spawn time but the block never got a Run button. `Block.new`, `Renderer.render` and
  `Step.new` now take `interpreters:` and the runbook passes its merged map down.
- `runsheets --init PATH` writes a starter runbook (directory, or single file when the
  path ends in `.md`) that passes `--check`; the CLI option became `:runbook`.
- `examples/staging-teardown` (directory: manual, automated with expect, terminal,
  background SSM tunnel, verify, destructive with a blast radius, rollback) and
  `examples/db-maintenance.md` (single file, `sql run` through `psql`, a secret
  `PGPASSWORD`). Both check clean and are loader fixtures; neither runs here.
- Vocabulary settled: runbook = document, runsheet = record. Page wording updated.

Not done: `capture` (still no runbook needs it). The gemspec lists files via
`git ls-files`, so everything added since the last commit is outside the gem until it
is committed. Next: use it against a real runbook and let the convention take the hits.
