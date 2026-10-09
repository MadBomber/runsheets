# Command Line

```text
Usage: runsheet [options] RUNBOOK
```

`RUNBOOK` is either a runbook directory (it must contain `runbook.md`) or
a single markdown file whose `##` headings are the steps (see
[Directory Structure](../runbooks/structure.md#single-file-runbooks)). It
is the only positional argument.

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `-p`, `--port PORT` | `4567` | Port to listen on. |
| `-b`, `--bind HOST` | `127.0.0.1` | Address to bind to. See the note below before changing it. |
| `--runs-dir DIR` | `~/.local/share/runsheets/runs` | Where run records are written. |
| `-o`, `--open` | off | Open the default browser once the server is listening. |
| `-c`, `--check` | off | Load the runbook, print authoring warnings, and exit without serving. |
| `--init` | off | Create a starter runbook at `RUNBOOK` and exit: a directory with `runbook.md`, two steps, `verify.md` and `rollback.md`, or a single file when the path ends in `.md`. Refuses to touch an existing file or a non-empty directory. |
| `-v`, `--version` | | Print the version and exit. |
| `-h`, `--help` | | Print usage and exit. |

## Examples

Start a new runbook, then serve it:

```bash
runsheet --init ops/runbooks/db-refresh        # a directory
runsheet --init ops/runbooks/db-refresh.md     # or a single file
runsheet --open ops/runbooks/db-refresh
```

Serve a runbook and open it:

```bash
runsheet --open ops/runbooks/staging-teardown
runsheet --open ops/runbooks/db-maintenance.md
```

Serve on another port because something else has 4567:

```bash
runsheet -p 4580 ops/runbooks/staging-teardown
```

Keep run records inside a project (but outside the runbook):

```bash
runsheet --runs-dir ./tmp/runs ops/runbooks/staging-teardown
```

Validate every runbook in a repository:

```bash
for dir in ops/runbooks/*/; do runsheet --check "$dir" || failed=1; done
exit "${failed:-0}"
```

## What it prints

```text
runsheet 0.1.0
Runbook: Staging Infrastructure Teardown and Rebuild (/Users/you/ops/runbooks/staging-teardown)
Runs:    /Users/you/.local/share/runsheets/runs
Open http://127.0.0.1:4567/ in your browser
Press Ctrl-C to stop
```

Authoring warnings are printed to stderr before the banner, prefixed
`runsheet: warning:`. The server still starts; warnings mark blocks and
steps in the page but do not block serving.

Puma then prints its own startup lines. Press ++ctrl+c++ to stop. Any block
still executing when the server stops is not killed by runsheets; its
process group outlives the server. Finish or abandon the run first if you
want a clean record.

## Exit status

| Status | When |
| --- | --- |
| `0` | Normal exit, or `--check` found no warnings. |
| `1` | Bad arguments, the runbook could not be loaded, the port is in use, or `--check` found warnings. |

## Environment

| Variable | Effect |
| --- | --- |
| `RUNSHEETS_RUNS_DIR` | Default for `--runs-dir`. |
| `PORT` | Not used. Pass `--port`. |
| anything else | Inherited by every executed block, and used to pre-fill inputs of the same name. See [Inputs and Secrets](../runbooks/inputs.md). |

## About `--bind`

The default binds to loopback and the server only accepts requests whose
`Host` header is `localhost`, `127.0.0.1`, `::1` or the bind address. That
is the whole multi-user story: there is none. Binding to another address
exposes shell execution on your machine to whoever can reach that address,
protected only by the session token embedded in the pages. Do not do it on
a network you do not control. The command prints a warning whenever the
bind address is not loopback. A wildcard address (`0.0.0.0` or `::`)
answers on every interface, so the `Host` check is turned off for it; a
specific address accepts requests for itself and the loopback names.

## Stopping

Ctrl-C stops the server. If a run is active it is ended as `abandoned`,
anything it left running (a `background` block, a block that was still
going) is stopped, and the run record is written, so nothing outlives the
tool and no record is left saying `running`.

## Running from a checkout

```bash
bundle exec exe/runsheet --open examples/hello
```
