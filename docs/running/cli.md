# Command Line

```text
Usage: runsheets [options] [RUNBOOK]
```

`RUNBOOK` is one of three things: a runbook directory (it must contain
`runbook.md`), a single all-in-one markdown file whose `##` headings are the
steps (see [Single-file runbooks](../runbooks/structure.md#single-file-runbooks)),
or a directory holding several of either, in folders nested to any depth
(see [Choosing a runbook](web-ui.md#choosing-a-runbook)). Given such a
directory of runbooks, the page opens on a folder tree and the operator picks
one; `runsheets examples` shows the three bundled examples that way. It is
the only positional argument. Leave it out and the bundled `examples/hello`
is served, which is the quickest way to see the tool;
`--init` is the one mode that always needs a path. `dir:` in the config file
or `RUNSHEETS_DIR` can supply it instead; see [Settings](#settings).

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `-c`, `--config FILE` | `./config/runsheets.yml` | Config file to read in place of the project config; see [Settings](#settings). A file named here must exist. |
| `-p`, `--port PORT` | `4567` | Port to listen on, from 1 to 65535. |
| `-b`, `--bind HOST` | `127.0.0.1` | Address to bind to. See the note below before changing it. |
| `--runs-dir DIR` | `~/.local/share/runsheets/runs` | Where session records, logs and run records are written. |
| `-o`, `--open` | off | Open the default browser once the server is listening. `--no-open` turns it off. |
| `--check` | off | Load the runbook, print authoring warnings, and exit without serving. On a directory of runbooks, every runbook is checked, one line each. See [Checking runbooks](#checking-runbooks). `--no-check` turns it off. |
| `--init` | off | Create a starter runbook at `RUNBOOK` and exit: a directory with `runbook.md`, two steps, `verify.md` and `rollback.md`, or a single file when the path ends in `.md`. Refuses to touch an existing file or a non-empty directory. `--no-init` turns it off. |
| `--dump` | off | Print the settings in force as a config file to stdout and exit. `--no-dump` turns it off. See [Saving settings](#saving-settings). |
| `-e`, `--engineer NAME` | ask | Who is starting the session. Without it the start page asks, pre-filled from `git config user.name`, else `$USER`. See [The session](#the-session). |
| `-w`, `--why TEXT` | ask | Why the session is being started: its first note. With `--engineer` too, the session starts at once and the start page is skipped. |
| `--log-level LEVEL` | `info` | The session log's level: `debug`, `info`, `warn`, `error` or `fatal`, in any case. See [The session log](#the-session-log). |
| `--verbose` | | The same as `--log-level debug`. |
| `-q`, `--quiet` | off | Do not echo the session log to the terminal. `--no-quiet` turns it off. |
| `-v`, `--version` | | Print the version and exit. |
| `-h`, `--help` | | Print usage and exit. |

## Examples

Start a new runbook, then serve it:

```bash
runsheets --init ops/runbooks/db-refresh        # a directory
runsheets --init ops/runbooks/db-refresh.md     # or a single file
runsheets --open ops/runbooks/db-refresh
```

Serve a runbook and open it, as a directory or as one all-in-one file:

```bash
runsheets --open ops/runbooks/staging-teardown       # a directory
runsheets --open ops/runbooks/db-maintenance.md      # a single file
runsheets --open ops/runbooks                        # choose among them
```

Serve on another port because something else has 4567:

```bash
runsheets -p 4580 ops/runbooks/staging-teardown
```

Start the session from the command line, skipping the start page:

```bash
runsheets -e "Pat Doe" -w "rotate the staging database password" ops/runbooks
```

Keep run records inside a project (but outside the runbook):

```bash
runsheets --runs-dir ./tmp/runs ops/runbooks/staging-teardown
```

Validate every runbook in a repository (a directory of runbooks is checked
as a whole):

```bash
runsheets --check ops/runbooks
```

## Checking runbooks

`--check` loads the runbook, prints its authoring warnings to stderr
prefixed `runsheets: warning:`, and prints one line to stdout:

```text
Hello, runsheets: 6 steps, 0 warnings
```

On a directory of runbooks every runbook gets that line with its slug in
brackets, and each warning is prefixed with the slug:

```text
runsheets: warning: platform/deploy: 020-roll-out: automated step has no executable block
Deploy [platform/deploy]: 4 steps, 1 warnings
Backup [platform/database/backup]: 3 steps, 0 warnings
```

A runbook in the directory that cannot be read (an unreadable file, front
matter that is not valid YAML, a clash of names) is never dropped from
the check. It is reported as an error with its slug and no summary line:

```text
runsheets: error: platform/restore: front matter may not use YAML aliases (& and *)
```

The exit status is `1` if any runbook warned or could not be read, else
`0`.

## What it prints

```text
runsheets 0.0.1
Runbook: Staging Infrastructure Teardown and Rebuild (/Users/you/ops/runbooks/staging-teardown)
Runs:    /Users/you/.local/share/runsheets/runs
Config:  /Users/you/.config/runsheets/runsheets.yml
Session: starts in the browser (who and why)
Open http://127.0.0.1:4567/ in your browser
Press Ctrl-C to end the session and stop
```

Started on a directory of runbooks, the second line is `Library:` with the
number of runbooks and folders. When `--engineer` and `--why` are both set
the session has already started, and the `Session:` line gives its id and
the path of its log:

```text
Session: 20261010T141502, log /Users/you/.local/share/runsheets/runs/sessions/20261010T141502/session.log
```

Served on one runbook, its authoring warnings are printed to stderr
before the banner, prefixed `runsheets: warning:`. The server still
starts; warnings mark blocks and steps in the page but do not block
serving. In a library, each runbook's warnings are on its pages and in
`--check`.

Puma then prints its own startup lines. From then on, unless `--quiet` is
given, the session log is echoed to the terminal as it is written. Press
++ctrl+c++ to end the session and stop; see [Stopping](#stopping).

## Exit status

| Status | When |
| --- | --- |
| `0` | Normal exit, or `--check` found no warnings. |
| `1` | Bad arguments or settings, the runbook could not be loaded, the port is in use, or `--check` found warnings or a runbook it could not read. |

## Settings

Every option is a setting with the same name (`port`, `bind`, `runs_dir`,
`open`, `check`, `init`, `dump`, `engineer`, `why`, `log_level`, `quiet`),
and the `RUNBOOK` argument is the setting `dir`. `--verbose` sets
`log_level` to `debug`.
Settings are layered with [myway_config](https://github.com/madbomber/myway_config);
each layer overrides the one below it, and anything a layer leaves out
comes from further down:

1. **Command line.** Whatever is given wins outright.
2. **Environment variables**, `RUNSHEETS_` plus the setting name in upper
   case: `RUNSHEETS_PORT`, `RUNSHEETS_BIND`, `RUNSHEETS_RUNS_DIR`,
   `RUNSHEETS_OPEN`, `RUNSHEETS_CHECK`, `RUNSHEETS_INIT`, `RUNSHEETS_DUMP`, `RUNSHEETS_DIR`,
   `RUNSHEETS_ENGINEER`, `RUNSHEETS_WHY`, `RUNSHEETS_LOG_LEVEL`, `RUNSHEETS_QUIET`.
3. **The project config**, `./config/runsheets.yml` in the current directory,
   or the file `--config FILE` or `RUNSHEETS_CONFIG` names in its place. The
   project file may be absent; a file named explicitly must exist.
4. **The user config**, `~/.config/runsheets/runsheets.yml` (or under
   `$XDG_CONFIG_HOME`), which myway_config reads for every application. This
   is where personal settings belong.
5. **Bundled defaults**, `lib/runsheets/config/defaults.yml` inside the gem. That file is
   the list of settings and documents each one.

Config files are flat YAML, one key per setting. Paths may start with
`~` and relative paths are taken from the current directory. Flags are on
for `1`, `true`, `yes` or `on` (any case) and off for any other value, so
`RUNSHEETS_OPEN=off` switches off an `open: true` in the file, and
`--no-open` switches off either. A blank value (`RUNSHEETS_PORT=`) counts as
unset. A port that is not a whole number from 1 to 65535, a log level
that is not one of the five (in any case: `WARN` is `warn`), a named
config file that does not exist, a config file that is not valid YAML, a
`--bind` host that does not resolve, or a runbook directory that cannot
be read is reported in one line and the command exits `1`:

```text
runsheets: port must be between 1 and 65535, got 70000
```

```yaml
# ~/.config/runsheets/runsheets.yml
dir: ~/ops/runbooks/db-refresh
port: 4580
runs_dir: ~/ops/runs
open: true
```

With that file, plain `runsheets` serves the db-refresh runbook on port 4580
and opens the browser; `runsheets --check` checks it instead; and
`RUNSHEETS_PORT=4581 runsheets` or `runsheets -p 4581` moves it for one run. A
repository can carry its own `config/runsheets.yml` (say `dir:` and
`runs_dir:`) that applies whenever `runsheets` is run from its root.

| Variable | Effect |
| --- | --- |
| `RUNSHEETS_CONFIG` | The file read in place of `./config/runsheets.yml`, when `--config` is not given. |
| `RUNSHEETS_<SETTING>` | The setting of that name, as above. |
| `RACK_ENV` | Selects an environment section (`development`, `test`, `production`) in `defaults.yml`; none is required. |
| `PORT` | Not used. Set `RUNSHEETS_PORT` or pass `--port`. |
| anything else | Inherited by every executed block, and used to pre-fill inputs of the same name. See [Inputs and Secrets](../runbooks/inputs.md). |

## Saving settings

`--dump` prints the settings in force, after every layer has been applied,
in the shape of a config file, and exits. Redirect it to save them. Run it
with the options you want to keep and they become the defaults for later
runs:

```bash
runsheets --dump -p 4580 ~/ops/runbooks/db-refresh        # look first
runsheets --dump -p 4580 ~/ops/runbooks/db-refresh > ~/.config/runsheets/runsheets.yml
runsheets                                                  # now serves db-refresh on 4580
```

Redirect to `config/runsheets.yml` instead for a project config to commit
with a repository. `dump` itself is never in the output, so a saved file
cannot make every later run print and exit, and neither are `check` and
`init`, for the same reason. Nor is `why`: the reason for a session
belongs to that session, not to every later one. `engineer` is saved.

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

## The session

Everything from start to stop is one session, belonging to one engineer
and opened with a note saying why (see
[Sessions, Runs and Runsheets](../concepts/runs.md)). The engineer and the
reason come from `--engineer` and `--why`, `RUNSHEETS_ENGINEER` and
`RUNSHEETS_WHY`, or `engineer:` and `why:` in a config file. With both
set, the session starts as the server does. Otherwise the browser opens on
a start page that asks for them, with the name pre-filled from the
configured engineer, else `git config user.name`, else `$USER`. The name
is taken as given; nothing authenticates it.

At start, any earlier session in the same runs directory that is still
marked running but whose process is gone is closed as `interrupted`,
along with its runs.

## The session log

Every session writes `session.log` in its directory under
`<runs-dir>/sessions/` (see
[The Run Record](run-record.md#the-session-log)). `log_level` sets what goes
into it:

| Level | What is logged |
| --- | --- |
| `debug` | Everything in the rows below, plus page views and other requests, searches, polling, runbook reloads, and the environment handed to each execution, secrets shown as `[secret]`. |
| `info` | Every action and its output: the session starting and ending, notes, a run opened with its inputs, inputs changed, each execution with its code and output, exit 0, stop requested, stopped, step marks and terminal confirmations with their notes. The default. |
| `warn` | Non-zero exits, timeouts, refused actions (a destructive block without its code or with the wrong one, any other action refused with 409), authoring warnings when a run opens, and an earlier session found interrupted. |
| `error` | An execution that cannot start, a runbook that no longer loads, an exception in the server. |

`fatal` is accepted too; runsheets writes nothing at that level, so it
leaves the file empty.

The log is echoed to the terminal that started `runsheets`, at `info`
whatever the file's level, unless `--quiet`, `RUNSHEETS_QUIET` or
`quiet: true` turns the echo off. Secret values never reach the log.

## Stopping

Ctrl-C ends the session and stops the server, exactly like **End session**
on the session page. Every run is closed with a status worked out from what
was done (`completed`, `partial` or `opened`), anything still running in
any runbook (a `background` block, a block that was still going) is
stopped, and the records are written, so nothing outlives the tool and no
record is left saying `running`. If the process is killed instead, the
next start closes its session as `interrupted`.

## Running from a checkout

```bash
bundle exec bin/runsheets --open examples/hello
```
