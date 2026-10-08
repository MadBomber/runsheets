# Execution Model

## One process per block

Every click on Run spawns a fresh process. The block's code is written to a
file in the run directory and the language's interpreter is started with
that file as its argument:

```text
bash /…/runs/hello/20261007T173348/blocks/010-say-hello-1.1.cmd
```

Nothing carries over between blocks except the environment runsheets
builds for each one. A `cd`, an `export`, a shell function defined in one
block does not exist in the next. This is a deliberate trade:

- Blocks stay copy-pasteable. What you see is exactly what ran.
- Executions are reproducible. The `.cmd` file plus the recorded inputs is
  the whole story.
- A hung or killed block cannot poison the next one.

Values that must flow between blocks go through inputs, or are recomputed.
A `capture` flag that stores a block's stdout as an input for later blocks
is on the [roadmap](../roadmap.md).

## Environment

The child process receives, in this order of precedence:

1. The `RUNSHEETS_*` variables identifying the run, step and block.
2. The run's inputs, secrets included.
3. The full environment of the `runsheet` process.

Standard input is `/dev/null`. A `read` returns immediately with nothing;
use a `terminal` block for anything interactive.

## Working directory

The runbook directory, unless the step's front matter sets `cwd`, which is
resolved relative to the runbook directory. Relative paths in a block
therefore mean the same thing on every operator's machine.

## Output

Standard output and standard error are both redirected to the execution's
`.out` file, interleaved in the order the process wrote them. The page polls
the tail of that file every half second while the process runs, so a
command that prints progress is seen printing it. Up to 256 KB of the tail
is shown in the page; the file holds everything.

Output is decoded as UTF-8 with invalid bytes replaced, both for the page
and for the transcript.

## Timeouts

Each step's `timeout` (default 600 seconds) bounds every execution of its
blocks. When it expires:

1. `SIGTERM` is sent to the process **group**, not just the interpreter, so
   a `sleep` or an `aws` command started by bash receives it too.
2. runsheets waits up to two seconds for the group leader to exit.
3. `SIGKILL` is sent to the group if it has not.

The execution is recorded with state `timed_out`. Its `exit_status` is
`128 + signal` (143 for TERM, 137 for KILL), matching what a shell would
report, and `signal` holds the raw number.

The process group is created with `pgroup: true` at spawn, so the killing
cannot reach anything the operator's shell started. Stopping the `runsheet`
server itself does not kill running blocks; finish the run first.

## States and verdicts

<div class="diagram" markdown>
![Execution states](../assets/images/run-lifecycle.svg)
</div>

| State | Meaning | `exit_status` |
| --- | --- | --- |
| `pending` | Created, not yet spawned. Visible only for an instant. | `null` |
| `running` | The process is alive. | `null` |
| `finished` | The process exited on its own. | its exit code, or `128 + signal` if a signal from elsewhere ended it |
| `timed_out` | runsheets killed it. | `128 + signal` |
| `failed` | It could not be spawned (interpreter not found, permission denied). `error` holds the message. | `null` |

An execution is a **success** only when its state is `finished` and its
exit status is `0`. The page colours the block, and the sidebar marks the
step, on that definition.

## Concurrency

Blocks can run concurrently: clicking Run on two blocks starts two
processes. Each has its own files and its own entry in the record, ordered
by start time. The server itself is a small Puma instance with a handful of
threads; the polling endpoints are cheap file reads.

## What is not sandboxed

Nothing. A block runs as you, with your environment, on your machine. That
is the point of the tool and also why it executes only what the author
opted in and the operator clicked. See [Security Posture](../reference/security.md).
