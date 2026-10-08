# The Run Record

The run record is the reason the tool exists. Every run writes a directory
outside the runbook:

```text
~/.local/share/runsheets/runs/<runbook-slug>/<yyyymmddThhmmss>/
  run.json          machine-readable: steps, blocks, timestamps, exit codes, acks
  run.md            human-readable transcript of the same
  blocks/
    010-say-hello-1.1.cmd         the exact code that ran
    010-say-hello-1.1.out         its stdout + stderr, interleaved
    010-say-hello-1.2.cmd         the same block, run a second time
    010-say-hello-1.2.out
```

The directory name is the start time in basic ISO 8601 form, which sorts
correctly and contains no colons (awkward on macOS and in archives). Two
runs started in the same second get `-2`, `-3` suffixes.

## Location

Default: `~/.local/share/runsheets/runs`. Override with `--runs-dir` or
`RUNSHEETS_RUNS_DIR`.

Why outside the runbook: captured output may contain account ids,
hostnames, row counts, anything a command prints. That does not belong in a
repository next to the docs. The runbook directory stays clean, and
runsheets never writes inside it.

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
- Started: 2026-10-07T17:33:48-05:00
- Finished: 2026-10-07T17:33:58-05:00
- Status: completed
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

- 2026-10-07T17:33:58.448-05:00 step **010-say-hello** marked done — smoke ok
```

Events appear in the order they happened, executions and step marks
interleaved, so jumping around is visible rather than hidden. Output longer
than 64 KB is trimmed to its tail in the transcript with a marker; the
`.out` file is complete.

The verdict after the block id is one of `ok`, `exit N`, `timed out`,
`failed to start: <error>`, or the raw state if the run was abandoned while
the block was still running.

## `run.json`

```json
{
  "runbook": "hello",
  "title": "Hello, runsheets",
  "id": "20261007T173348",
  "status": "completed",
  "started_at": "2026-10-07T17:33:48.859-05:00",
  "finished_at": "2026-10-07T17:33:58.515-05:00",
  "duration": 9.656,
  "inputs": { "NAME": "smoke" },
  "steps": { "010-say-hello": "done" },
  "events": [
    { "type": "execute", "at": "2026-10-07T17:33:48.863-05:00",
      "step": "010-say-hello", "block": "010-say-hello-1", "execution": "1b6a8f0c2d3e" },
    { "type": "step", "at": "2026-10-07T17:33:58.448-05:00",
      "step": "010-say-hello", "status": "done", "note": "smoke ok" }
  ],
  "executions": [
    {
      "id": "1b6a8f0c2d3e",
      "block_id": "010-say-hello-1",
      "step": "010-say-hello",
      "command": ["bash"],
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
| `status` | `running`, `completed` or `abandoned`. |
| `started_at`, `finished_at` | ISO 8601 with milliseconds. `finished_at` is `null` while running. |
| `duration` | Seconds, to the millisecond. For a running run, time elapsed so far at the last write. |
| `inputs` | The non-secret inputs the run was started with. Secrets are never written. |
| `steps` | Step slug to the operator's last mark, `done` or `skipped`. Steps never marked are absent. |
| `events` | Everything that happened, in order. |
| `executions` | One entry per execution, in start order. |

### Events

Two types:

- `execute`: `at`, `step`, `block`, and the `execution` id to look up in
  `executions`.
- `step`: `at`, `step`, `status` (`done` or `skipped`), and `note` when one
  was given.

### Executions

| Field | Meaning |
| --- | --- |
| `id` | Twelve hex characters, unique within the process. |
| `block_id`, `step` | Which block ran, and the step it belongs to. |
| `command` | The interpreter command, before the `.cmd` path is appended. |
| `state` | `pending`, `running`, `finished`, `timed_out`, `failed`. See [Execution Model](execution.md). |
| `pid` | The child's process id, which is also its process group id. |
| `started_at`, `finished_at`, `duration` | As for the run. |
| `exit_status` | The exit code, or `128 + signal`, or `null`. |
| `signal` | The signal number that ended the process, if any. |
| `error` | Why it could not start, for `failed`. |
| `cmd`, `log` | File names inside `blocks/`. |

## When the record is written

- At run start, with no events.
- After every execution starts, every step mark, and the first time a
  finished execution is observed by the page's polling.
- At finish.

So a `run.json` read while a run is active is at most one poll interval
behind. If the `runsheet` process is killed mid-run, the record stays with
`status: running`; the block files are intact.

## Reading records programmatically

```ruby
require "runsheets"

Runsheets::RunRecord.list(Runsheets.runs_dir, "staging-teardown").each do |run|
  s = run.summary
  puts "#{s[:id]} #{s[:status]} #{s[:failures]} failed, #{s[:steps_done]} steps done"
end
```

See the [Ruby API](../reference/ruby-api.md).
