# The Run Record

The run record is the reason the tool exists. Every session writes a
directory of its own, and every runbook selected in it writes a run
directory, all outside the runbook:

```text
~/.local/share/runsheets/runs/
  sessions/<session-id>/
    session.json        who, where, when, why, the notes, and the runs
    session.log         every action and its output, appended as it happens
  <runbook-slug>/<session-id>/
    run.json            machine-readable: steps, blocks, timestamps, exit codes, acks
    run.md              human-readable transcript of the same
    blocks/
      010-say-hello-1.1.cmd         the exact code that ran
      010-say-hello-1.1.out         its stdout + stderr, interleaved, secrets redacted
      010-say-hello-1.2.cmd         the same block, run a second time
      010-say-hello-1.2.out
```

The session id is the session's start time in basic ISO 8601 form
(`20261010T141502`), which sorts correctly and contains no colons (awkward
on macOS and in archives). A run directory is named by the id of the
session it belongs to, so a runbook's history stays together under its
slug and each run points back to its session. When a name is already
taken, `-2`, `-3` suffixes are added. Records from before sessions are
named by their own start time, and a verification run from then has a
`-verify` suffix.

## Location

Default: `~/.local/share/runsheets/runs`. Override with `--runs-dir`,
`RUNSHEETS_RUNS_DIR`, or `runs_dir:` in the config file (see
[Command Line](cli.md#settings)).

Why outside the runbook: captured output may contain account ids,
hostnames, row counts, anything a command prints. That does not belong in a
repository next to the docs. The runbook directory stays clean, and
runsheets never writes inside it.

## `session.json`

```json
{
  "id": "20261010T141502",
  "engineer": "Pat Doe",
  "host": "build-07",
  "pid": 65462,
  "runsheets": "0.0.1",
  "status": "ended",
  "started_at": "2026-10-10T14:15:02.288-05:00",
  "ended_at": "2026-10-10T14:52:40.356-05:00",
  "library": "/Users/pat/ops/runbooks",
  "log": "/Users/pat/.local/share/runsheets/runs/sessions/20261010T141502/session.log",
  "notes": [
    { "at": "2026-10-10T14:15:02.288-05:00", "text": "monthly maintenance on the app database" },
    { "at": "2026-10-10T14:40:11.020-05:00", "text": "vacuum ran long; left the reindex for tomorrow" }
  ],
  "runs": [
    { "runbook": "db-maintenance", "title": "Database maintenance",
      "dir": "/Users/pat/.local/share/runsheets/runs/db-maintenance/20261010T141502", "status": "partial" },
    { "runbook": "disk-space-triage", "title": "Disk space triage",
      "dir": "/Users/pat/.local/share/runsheets/runs/disk-space-triage/20261010T141502", "status": "opened" }
  ]
}
```

| Field | Meaning |
| --- | --- |
| `id` | The session id, equal to the directory name. |
| `engineer` | Who started the session, as they gave it. Not authenticated. |
| `host`, `pid` | Where the session ran: the host name and the `runsheets` process id. |
| `runsheets` | The runsheets version. |
| `status` | `running`, `ended`, or `interrupted` for a session whose process was killed. |
| `started_at`, `ended_at` | ISO 8601 with milliseconds. `ended_at` is `null` while running. For an interrupted session it is the time of the last write to its log. |
| `library` | The directory of runbooks served, or `null` for one runbook. |
| `log` | The path of `session.log`. |
| `notes` | Every note with its time, the reason the session was started first. |
| `runs` | Each runbook selected, in order: its slug, title, run directory and status. |

The file is rewritten when the session starts, when a note is added, when
a runbook is first selected, and when the session ends.

### Interrupted sessions

A killed `runsheets` cannot close its session, so `session.json` is left
saying `running`. At the next start, runsheets looks through the
`sessions/` directory for sessions still marked `running` whose process is
gone (the pid is not alive on this host) and closes each one as
`interrupted`, together with any of its runs still open. A session whose
process is alive belongs to another `runsheets` and is left alone. The new
session's log gets a `WARN` line for each one closed.

## The session log

`session.log` is a plain text file, appended and flushed line by line as
things happen. The same lines are echoed to the terminal that started
`runsheets`, unless `--quiet` is given.

```text
2026-10-10 01:17:19.579 INFO  [disk-space-triage] run opened TARGET_DIR=/tmp THRESHOLD=99
2026-10-10 01:17:19.589 INFO  [disk-space-triage 010-check-free-space #acd50b22502a] execute bash via bash
2026-10-10 01:17:19.589 INFO  [#acd50b22502a] $ df -h "$TARGET_DIR"
2026-10-10 01:17:19.602 INFO  [#acd50b22502a] > Filesystem      Size    Used   Avail Capacity ...
2026-10-10 01:17:19.651 INFO  [#acd50b22502a] finished exit 0 in 0.06s
2026-10-10 01:17:20.832 INFO  [session] ended (runsheets stopped) after 2s; runs: disk-space-triage partial
```

Each line is a timestamp to the millisecond, a level, tags in brackets
saying where it happened (`session`, a runbook slug, a step slug, an
execution id after `#`, `web` for requests), and the event. Text of more
than one line becomes one log line per line, each with the same prefix, so
every line stands alone under `grep`.

An execution is logged as the code that ran, one line per line after `$`,
then its output after `>`, written line by line as it arrives (after
redaction), all tagged by the execution id, and finally how it ended. Two
blocks running at once interleave, and the tag keeps them apart.

The levels are the standard Ruby `Logger` levels, and `log_level` (default
`info`) sets which reach the file; see
[The session log](cli.md#the-session-log) for what is written at each.
Secret values never reach the log: inputs are shown as `NAME=[secret]`,
and output is redacted before it is logged. The per-execution `.cmd` and
`.out` files are still written; the log does not replace them.

## Block files

Each execution of block `<id>` gets a pair of files named
`<id>.<n>.cmd` and `<id>.<n>.out`, where `n` counts executions of that
block within the run, from 1. Both are written as the execution starts; the
`.out` file grows while the process runs.

The `.cmd` file is exactly the fence's contents, so a diff against the
runbook shows whether the markdown changed after the run.

## `run.md`

A transcript the operator can read or attach to a ticket:

```markdown
# Hello, runsheets — run 20261007T173348

- Runbook: `hello`
- Session: `20261007T173348`
- Started: 2026-10-07T17:33:48-05:00
- Finished: 2026-10-07T17:33:58-05:00
- Status: partial
- Inputs:
  - `NAME` = `smoke`

## Timeline

### 2026-10-07T17:33:48.863-05:00 `010-say-hello-1` (010-say-hello) — ok in 0.054s

```bash
echo "Hello, $NAME!"
```

Output:

```text
Hello, smoke!
```

### 2026-10-07T17:33:50.134-05:00 `040-exercise-failure-2` (040-exercise-failure) — timed out in 5.064s

...

### 2026-10-07T17:33:52.002-05:00 `035-keep-a-clock-running-1` (035-keep-a-clock-running) — stopped in 4.1s [background]

...

- 2026-10-07T17:33:55.120-05:00 `020-inspect-ruby-3` (020-inspect-ruby) confirmed run in the operator's terminal — pressed enter

- 2026-10-07T17:33:58.448-05:00 step `010-say-hello` marked done — smoke ok

- 2026-10-07T17:34:02.310-05:00 inputs changed: `NAME` = `again`
```

Events appear in the order they happened: executions, terminal
confirmations, step marks and input changes interleaved, so jumping around
is visible rather than hidden. Output longer than 64 KB is trimmed to its
tail in the transcript with a marker; the `.out` file is complete.

The transcript is rendered as markdown on the runsheet page, so nothing
recorded in it can become markup. Code and output sit in a fence longer
than any run of backticks inside them; input values and step slugs are
code spans; notes are kept on one line with their HTML and markdown
characters escaped.

The verdict after the block id is one of `ok`, `exit N`, `timed out`,
`stopped`, `failed to start: <error>`, or the raw state if the record was
last written while the block was still running. Tags in brackets after it mark a
`background` execution and a destructive one that was `confirmed`.

## `run.json`

```json
{
  "runbook": "hello",
  "title": "Hello, runsheets",
  "id": "20261007T173348",
  "session": "20261007T173348",
  "kind": "run",
  "status": "partial",
  "started_at": "2026-10-07T17:33:48.859-05:00",
  "finished_at": "2026-10-07T17:34:05.515-05:00",
  "duration": 16.656,
  "inputs": { "NAME": "again" },
  "steps": { "010-say-hello": "done" },
  "acks": {
    "020-inspect-ruby-3": { "at": "2026-10-07T17:33:55.120-05:00", "step": "020-inspect-ruby", "note": "pressed enter" }
  },
  "events": [
    { "type": "execute", "at": "2026-10-07T17:33:48.863-05:00",
      "step": "010-say-hello", "block": "010-say-hello-1", "execution": "1b6a8f0c2d3e" },
    { "type": "execute", "at": "2026-10-07T17:33:50.134-05:00",
      "step": "040-exercise-failure", "block": "040-exercise-failure-1", "execution": "9c1d2e3f4a5b", "confirmed": true },
    { "type": "ack", "block": "020-inspect-ruby-3", "at": "2026-10-07T17:33:55.120-05:00",
      "step": "020-inspect-ruby", "note": "pressed enter" },
    { "type": "step", "at": "2026-10-07T17:33:58.448-05:00",
      "step": "010-say-hello", "status": "done", "note": "smoke ok" },
    { "type": "inputs", "at": "2026-10-07T17:34:02.310-05:00",
      "inputs": { "NAME": "again" } }
  ],
  "executions": [
    {
      "id": "1b6a8f0c2d3e",
      "block_id": "010-say-hello-1",
      "step": "010-say-hello",
      "command": ["bash"],
      "background": false,
      "state": "finished",
      "pid": 83412,
      "started_at": "2026-10-07T17:33:48.871-05:00",
      "finished_at": "2026-10-07T17:33:48.925-05:00",
      "duration": 0.054,
      "exit_status": 0,
      "signal": null,
      "error": null,
      "cmd": "010-say-hello-1.1.cmd",
      "log": "010-say-hello-1.1.out"
    }
  ]
}
```

### Top level

| Field | Meaning |
| --- | --- |
| `runbook` | The runbook slug. |
| `title` | The runbook title at the time of the run. |
| `id` | The run id, equal to the directory name. |
| `session` | The id of the session the run belongs to. Absent in records from before sessions. |
| `kind` | `run`. Records from before sessions may say `verify`, for a verification run that executed only the verify documents. |
| `status` | `running` while the session lasts; then `completed`, `partial`, `opened` or `interrupted` (see below). Records from before sessions may say `abandoned`. |
| `started_at`, `finished_at` | ISO 8601 with milliseconds. `finished_at` is `null` while running. |
| `duration` | Seconds, to the millisecond. For a running run, time elapsed so far at the last write. |
| `inputs` | The non-secret inputs in force: those the run was opened with, or the latest change. Secrets are never written. |
| `steps` | Step slug to the operator's last mark, `done` or `skipped`. Steps never marked are absent. |
| `acks` | Terminal block id to the operator's latest confirmation: `at`, `step`, and `note` when one was given. |
| `events` | Everything that happened, in order. |
| `executions` | One entry per execution, in start order. |

### Run statuses

A run has no Finish button. It ends with its session, and its status is
worked out from what was done:

| Status | When |
| --- | --- |
| `running` | The session is still going. |
| `completed` | Every numbered step was marked done or skipped. |
| `partial` | Anything was executed, marked or acknowledged, but not every numbered step was marked. |
| `opened` | The runbook was selected and nothing was done. |
| `interrupted` | The `runsheets` process was killed; the next start closed the run. |
| `abandoned` | Only in records from before sessions. |

### Events

Four types:

- `execute`: `at`, `step`, `block`, and the `execution` id to look up in
  `executions`. `confirmed: true` when the block was destructive and the
  operator typed the confirmation code.
- `ack`: `at`, `step`, `block`, and `note` when one was given. The operator
  confirmed they ran a `terminal` block themselves.
- `step`: `at`, `step`, `status` (`done` or `skipped`), and `note` when one
  was given.
- `inputs`: `at`, and the non-secret `inputs` after the operator changed
  them partway through the run.

### Executions

| Field | Meaning |
| --- | --- |
| `id` | Twelve hex characters, unique within the process. |
| `block_id`, `step` | Which block ran, and the step it belongs to. |
| `command` | The interpreter command, before the `.cmd` path is appended. |
| `background` | `true` for a `background` block. |
| `state` | `pending`, `running`, `finished`, `timed_out`, `stopped`, `failed`. See [Execution Model](execution.md). |
| `pid` | The child's process id, which is also its process group id. |
| `started_at`, `finished_at`, `duration` | As for the run. |
| `exit_status` | The exit code, or `128 + signal`, or `null`. |
| `signal` | The signal number that ended the process, if any. |
| `error` | Why it could not start, for `failed`. |
| `cmd`, `log` | File names inside `blocks/`. |

## When the record is written

- When the runbook is selected and its run opened, with no events.
- After every execution starts and again when it ends, and after every
  step mark, terminal confirmation and change of inputs.
- When the session ends, after anything still running has been stopped.

If the `runsheets` process is killed, the record stays with
`status: running` until the next start closes it as `interrupted`; the
block files are intact.

## Reading records programmatically

```ruby
require "runsheets"

Runsheets::RunRecord.list(Runsheets.runs_dir, "staging-teardown").each do |run|
  s = run.summary
  puts "#{s[:id]} #{s[:status]} #{s[:failures]} failed, #{s[:steps_done]} steps done"
end
```

`session.json` is plain JSON; read it with `JSON.parse`. See the
[Ruby API](../reference/ruby-api.md).
