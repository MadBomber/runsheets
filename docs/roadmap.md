# Roadmap

The plan that runsheets is built from lives in the repository as
`PLAN.md`, with a discussion log. This page is the short version.

## Milestone 1: render and run

Done. Load a runbook directory, render landing and step pages, execute
`bash` and `ruby` blocks with output, exit status and timing, write the run
record. Manual acknowledgements, destructive confirmation, `terminal` and
`expect` labelling, inputs with secrets, the rollback sidebar, run history,
`--check`, and the security controls all landed here too, because they were
cheap once the pieces existed.

## Milestone 2: the full block set

Done.

- **`background` blocks**: Start and Stop buttons, no timeout, output
  streamed, a **Running** panel in the sidebar on every page, everything
  still running stopped when the run ends and recorded as `stopped`.
- **`terminal` blocks**: an **I ran this** button records the operator's
  confirmation, with an optional note, as an `ack` event.
- **Destructive confirmation moved server-side**: the first execute request
  gets a four-character code back (HTTP 428); the block runs only when the
  code is typed back. The record notes that the execution was confirmed.
- **`expect` panels**: an expect block is linked to the executable block
  above it and shown beside that block's real output with a matches/differs
  hint.
- **Redaction**: secret input values are replaced in captured output before
  it reaches the `.out` file, even when a secret is split across two writes.
  String replacement only; encoded forms are not caught and
  [Inputs and Secrets](runbooks/inputs.md) says so.
- **Output size**: the page shows the last 256 KB with a marker when there
  is more. The file keeps everything.

Deferred from the original list: **`capture`**, a flag that stores a block's
stdout as a named input for later blocks. It needs a syntax for the name
and a real runbook to prove it; see the plan's open questions.

## Milestone 3: verification and history

Done.

- **Verification runs**: the landing page's **Verify only** button starts a
  run of kind `verify` that may execute only verify-kind steps and
  `verify.md`. A **Checks** page gathers those documents with a **Run all**
  button that runs every check in order. The record is written like any
  other run and listed in history with a `verify` badge.
- **Richer history**: each previous run shows its kind, status
  (`completed`, `abandoned`, `running`), start time, duration, executions
  and failures, steps done or checks run, and which step it stopped at.
- **Drift**: a run record page shows, for every block that ran, whether
  its code in the runbook has changed since, with a line diff, or whether
  the block is gone.

This milestone also wrote a `last_verified` date back into `runbook.md`
after a verifying run. That was later removed; runsheets now never writes
inside a runbook directory. Verification runs themselves went in
milestone 5: the Checks page and **Run all** now work inside the
runbook's ordinary run, and old records of kind `verify` still load and
keep their badge in history.

## Milestone 4: packaging

Done.

- **Single-file runbooks**: `runsheets path/to/runbook.md` reads one file
  whose `##` headings are the steps, with step attributes in an HTML
  comment after the heading and Verify and Rollback sections standing in
  for the extra files. Everything downstream sees the same `Runbook`.
- **SQL through the interpreters map**: a language the front matter maps
  now executes. Before this, `sql run` warned and stayed inert even with a
  mapping, because block classification only knew the built-in languages.
- **Two realistic samples**: `examples/staging-teardown`, a directory
  runbook with the shape of a real AWS teardown (manual, automated,
  terminal, background, destructive and verify steps, blast radius,
  rollback), and `examples/db-maintenance.md`, a single-file PostgreSQL
  runbook whose blocks are `sql run` through `psql`. Neither can run
  against this machine; both load clean under `--check` and are test
  fixtures for the loader.
- **`runsheets --init`** scaffolds a starter runbook, directory or single
  file, that passes `--check`.
- **Vocabulary settled**: the document is the *runbook*; the record of a
  run is the *runsheet*. The page, sidebar and buttons now say so.

## Milestone 5: sessions

Done.

- **The session**: everything from `runsheets` starting to stopping is one
  session, belonging to one engineer and opened with a note saying why. A
  start page asks for both, pre-filled from `git config user.name` or
  `$USER`; `--engineer` and `--why` (or their settings) skip it. The
  session page shows the notes, with an **Add note** form, each
  runbook's run and its status so far, and the tail of the log.
- **Many runbooks, one run each**: selecting a runbook establishes its run;
  selecting it again returns to the same run. Switching finishes nothing,
  background processes keep running, and the sidebar's Running panel can
  stop any of them. Non-secret inputs given earlier in the session pre-fill
  later runs. Inputs can be changed partway, recorded as an `inputs`
  event.
- **Ending**: **End session** or Ctrl-C closes every run with a status
  worked out from what was done: `completed`, `partial` or `opened`. A
  session left running by a killed process is closed as `interrupted` at
  the next start. The Finish and Abandon buttons, and verification
  runs, are gone.
- **The session log**: `session.log` records every action and its output
  as it happens, with Ruby `Logger` levels (`--log-level`, `--verbose`),
  echoed to the terminal unless `--quiet`. Secrets never reach it.
- **Records**: `sessions/<id>/session.json` and `session.log`; each run
  directory is named by the session id and its `run.json` names the
  session. Blocks see `RUNSHEETS_SESSION_ID`.

## Open questions

- **`capture`.** A flag that stores a block's stdout as a named input for
  later blocks, the one escape hatch from "nothing carries over". Still
  waiting for a runbook that needs it and a syntax for the name.
- **Persistent shell per run.** Rejected for milestone 1 in favour of a
  fresh process per block. If `capture` turns out not to be enough, this
  comes back.

## Not planned

- Multi-user or remote operation. See [Security Posture](reference/security.md).
- Running inside a deployed application. The blocks are shell against the
  operator's environment; none of it exists in an app process.
- Enforcing step order. The record makes skipping visible; that is enough.
