# runsheets — Executable Runbook Viewer

Plan and discussion log for `runsheets`, an open-source tool that turns a directory of
markdown files into an executable, recorded runbook served in the browser.

Status: milestones 1 and 2 built and passing (see the 2026-10-07 and 2026-10-08 log). Milestones 3 and 4 open.
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
- finishing a run can stamp the runbook with the date it was last exercised

The rendering is the vehicle. The run record is the point.

## Decisions so far

| Decision | Choice | Why |
| --- | --- | --- |
| Name | `runsheets` gem, `runsheet` command | `runbook` and `rb` are taken on RubyGems; `myrb` and `mrb` are taken and `mrb` is the mruby ecosystem's own abbreviation; `livedoc` already means living documentation in BDD circles and is taken on npm and PyPI. `runsheets` was free on RubyGems, npm, PyPI, Homebrew and PATH on 2026-10-07. A runsheet is the theatre and broadcast term for the timed, ordered list of what happens, which matches "the run record is the point". |
| Project home | Standalone open-source project, not part of xyzzy | Generic tool; xyzzy's gates (95% per-file coverage, Trunk) would be a tax on a shell-heavy tool. xyzzy's runbooks are inspiration only. |
| GUI or CLI | Browser GUI served from a local Sinatra process | Markdown renders properly; the page is a natural home for the run log. Terminal markdown is possible but not pleasant. |
| Attached or detached | Detached (runs on the operator's machine or devcontainer) | The blocks are shell against the operator's environment: SSO sessions, tunnels, local DBs, `gh`. None of that exists inside a deployed app process, and executing markdown blocks in a web app is a security hole. |
| Executability | Opt-in per block via the info string | Real runbooks mix runnable shell, expected-output samples, config to copy, SQL for a separate client, and destructive commands. Default must be "display only". |
| Document shape | A directory per runbook with one file per step | Better suited to runsheets than xyzzy's single-file H2 layout. Single-file runbooks may be supported later as a convenience. |
| Process model | Fresh process per block, own process group | Blocks stay copy-pasteable and reproducible; timeouts can kill the whole group. A `capture` flag to pass one block's stdout to later blocks is deferred until a runbook needs it. |
| Output | Every execution writes to a log file; the page polls | One spawn path for `run` and the future `background`; a ten-minute `--wait` shows its output as it arrives instead of looking hung. |
| Interpreters | `interpreters:` in runbook.md front matter maps a language to a command | xyzzy's Ruby snippets need `bin/rails runner -`; the same mechanism will route `sql` through `psql` when needed. |
| Browser security | Per-process token in a meta tag, required on every non-GET request, plus loopback-only Host authorization | A page on another origin can neither read the token nor send the custom header without a preflight the app never answers; the Host check defeats DNS rebinding. |
| Destructive confirmation | Server issues a random four-character code per block (HTTP 428), runs the block only when it comes back, retires it once used | The review's point: a typed slug becomes muscle memory. Checking server-side means a script driving the API cannot skip it either. The record notes the execution was confirmed. |
| Redaction | Child output goes through a pipe and a reader thread that replaces secret values before writing the `.out` file, holding back a tail that could be a partial secret | Letting the child write the file directly made redaction impossible. Plain string replacement; encoded secrets are documented as out of scope. |
| Stopped is not failed | Operator stops and run-end stops record state `stopped`, distinct from `timed_out` | A background tunnel stopped on purpose must not mark the step failed. |
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
last_verified: 2026-09-12
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

One deliberate write-back into the runbook: finishing a run with every step done
offers to update `last_verified` in `runbook.md`. That is the only file the tool ever
modifies, and only on request.

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
- The tool modifies exactly one file in the runbook directory, `runbook.md`, and only
  to update `last_verified`, and only when asked.
- No remote execution, no agent, no daemon. It is a script an operator starts and
  stops.

## Milestones

1. **Render and run.** Done 2026-10-07. Load a runbook directory, render landing and step pages with
   tdv.rb's layout, execute `bash run` blocks, show output and exit status, write the
   run record. One real runbook converted as the fixture.
2. **The full block set.** Done 2026-10-08. `manual` steps with acknowledgement, `terminal`
   with recorded confirmation, `destructive` with server-checked typed confirmation,
   `background` with start, stop and streaming, `expect` panels beside the real output.
   Inputs form with secrets and redaction of captured output.
3. **Verification and history.** `verify` steps and `verify.md` runnable standalone,
   `last_verified` write-back, run history on the landing page, rollback sidebar.
4. **Packaging.** Gem with a `bin/` entry point, README with the document structure and
   block convention, a sample runbook, minitest suite. Pick the name (see open
   questions).

## Open questions

- **Vocabulary.** Whether the document is called a "runbook" and only the recorded
  run is the "runsheet" (closer to the theatre meaning, and keeps the run record in
  the name), or whether "runsheet" is used throughout. Leaning toward the split.
- **Single-file runbooks.** Support a one-file runbook whose H2 headings are the steps,
  so existing docs can be used without restructuring? Deferred until milestone 4;
  the directory layout is the primary shape.
- **SQL blocks.** Routing `sql run` through a configured client (`psql` with a
  connection string from inputs) would cover a common case. Deferred until a runbook
  actually needs it.
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
- `web.rb`, `pages.rb`, `assets.rb`, `cli.rb`, `exe/runsheet`.
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
