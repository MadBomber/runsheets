# Command Line

```text
Usage: runsheets [options] [RUNBOOK]
```

`RUNBOOK` is one of three things: a runbook directory (it must contain
`runbook.md`), a single all-in-one markdown file whose `##` headings are the
steps (see [Single-file runbooks](../runbooks/structure.md#single-file-runbooks)),
or a directory holding several of either side by side. Given such a directory of
runbooks, the page opens on a chooser listing them and the operator picks
one; `runsheets examples` shows the three bundled examples that way. It is
the only positional argument. Leave it out and the bundled `examples/hello`
is served, which is the quickest way to see the tool;
`--init` is the one mode that always needs a path. `dir:` in the config file
or `RUNSHEETS_DIR` can supply it instead; see [Settings](#settings).

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `-c`, `--config FILE` | `./config/runsheets.yml` | Config file to read in place of the project config; see [Settings](#settings). A file named here must exist. |
| `-p`, `--port PORT` | `4567` | Port to listen on. |
| `-b`, `--bind HOST` | `127.0.0.1` | Address to bind to. See the note below before changing it. |
| `--runs-dir DIR` | `~/.local/share/runsheets/runs` | Where run records are written. |
| `-o`, `--open` | off | Open the default browser once the server is listening. `--no-open` turns it off. |
| `--check` | off | Load the runbook, print authoring warnings, and exit without serving. On a directory of runbooks, every runbook is checked, one line each. `--no-check` turns it off. |
| `--init` | off | Create a starter runbook at `RUNBOOK` and exit: a directory with `runbook.md`, two steps, `verify.md` and `rollback.md`, or a single file when the path ends in `.md`. Refuses to touch an existing file or a non-empty directory. `--no-init` turns it off. |
| `--dump` | off | Print the settings in force as a config file to stdout and exit. `--no-dump` turns it off. See [Saving settings](#saving-settings). |
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

Keep run records inside a project (but outside the runbook):

```bash
runsheets --runs-dir ./tmp/runs ops/runbooks/staging-teardown
```

Validate every runbook in a repository (a directory of runbooks is checked
as a whole):

```bash
runsheets --check ops/runbooks
```

## What it prints

```text
runsheets 0.1.0
Runbook: Staging Infrastructure Teardown and Rebuild (/Users/you/ops/runbooks/staging-teardown)
Runs:    /Users/you/.local/share/runsheets/runs
Config:  /Users/you/.config/runsheets/runsheets.yml
Open http://127.0.0.1:4567/ in your browser
Press Ctrl-C to stop
```

Authoring warnings are printed to stderr before the banner, prefixed
`runsheets: warning:`. The server still starts; warnings mark blocks and
steps in the page but do not block serving.

Puma then prints its own startup lines. Press ++ctrl+c++ to stop. Any block
still executing when the server stops is not killed by runsheets; its
process group outlives the server. Finish or abandon the run first if you
want a clean record.

## Exit status

| Status | When |
| --- | --- |
| `0` | Normal exit, or `--check` found no warnings. |
| `1` | Bad arguments or settings, the runbook could not be loaded, the port is in use, or `--check` found warnings. |

## Settings

Every option is a setting with the same name (`port`, `bind`, `runs_dir`,
`open`, `check`, `init`, `dump`), and the `RUNBOOK` argument is the setting `dir`.
Settings are layered with [myway_config](https://github.com/madbomber/myway_config);
each layer overrides the one below it, and anything a layer leaves out
comes from further down:

1. **Command line.** Whatever is given wins outright.
2. **Environment variables**, `RUNSHEETS_` plus the setting name in upper
   case: `RUNSHEETS_PORT`, `RUNSHEETS_BIND`, `RUNSHEETS_RUNS_DIR`,
   `RUNSHEETS_OPEN`, `RUNSHEETS_CHECK`, `RUNSHEETS_INIT`, `RUNSHEETS_DUMP`, `RUNSHEETS_DIR`.
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
unset. A port that is not a whole number, or a named config file that does
not exist, is reported and the command exits `1`.

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
cannot make every later run print and exit.

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
bundle exec bin/runsheets --open examples/hello
```
