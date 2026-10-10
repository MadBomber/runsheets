# runsheets

> **Note:** This is a proof-of-concept and a work in progress. Expect it to
> be unstable for a while: features, file formats, and the CLI may change
> without notice.
>
> See the [CHANGELOG.md](https://github.com/MadBomber/runsheets/blob/main/CHANGELOG.md)
> file to see latest changes.

Executable runbooks. A directory of markdown files becomes a local web page
where the steps read like a doc site, the commands the author marked as
runnable get a Run button, and everything that happens during a run is
recorded: the exact command, its output, exit status, timing, and the
operator's acknowledgements of the manual steps.

The rendering is the vehicle. The run record, the *runsheet*, is the point.

Status: milestones 1 to 5 of the [plan](PLAN.md) are built. Every block
kind in the convention below is live, a runbook can be a directory or a
single markdown file, and everything between starting runsheets and
stopping it is one *session* with its own log. Vocabulary: the document is
the *runbook*; the record of one runbook's run is the *runsheet*.

## Install

```bash
gem install runsheets
```

Requires Ruby 3.4 or newer.

## Run

```bash
runsheets                         # serve the bundled examples/hello on http://127.0.0.1:4567/
runsheets path/to/runbook         # serve a runbook directory (runbook.md + steps/)
runsheets path/to/runbook.md      # serve a single all-in-one markdown file
runsheets path/to/runbooks        # a directory of runbooks: choose one in the browser
runsheets --open path/to/runbook  # and open the browser
runsheets --check path/to/runbook # load it, print authoring warnings, exit
runsheets --init path/to/new      # scaffold a runbook (a .md path makes a single file)
```

The argument is one of three things: a runbook directory, a single
all-in-one markdown file whose `##` headings are the steps (see
[Single-file runbooks](docs/runbooks/structure.md#single-file-runbooks)),
or a directory holding several of either, in folders nested as deep as
you like. A markdown file is a runbook only when it starts with YAML front
matter that has a `title`; any other markdown file is a plain document that
a runbook can link to (see
[Runbooks and Documents](docs/concepts/runbooks.md)). Started on such a library, the browser opens on a folder tree in
the left pane; selecting a runbook shows its description, prerequisites,
inputs, steps and previous runs in the main pane, with the inputs form and
a **Start run** button.
A `README.md` in a folder is shown as that folder's description. The
search box in the header searches the full text of every runbook. Try the
bundled examples:

```bash
runsheets --open examples                      # all four, pick one in the browser
runsheets --open examples/hello                # safe to run: every block kind
runsheets --check examples/staging-teardown    # a realistic AWS teardown
runsheets --open examples/db-maintenance.md    # a single all-in-one file, sql blocks via psql
runsheets --open examples/disk-space-triage.md # links to plain documents, kept out of the tree
```

Options: `--port`, `--bind` (default loopback), `--runs-dir` (where run
records go; default `~/.local/share/runsheets/runs`), `--open`, `--check`,
`--init`, `--config FILE`, `--dump` to print the settings in force as a
config file (redirect it to save them), and for the session `--engineer`,
`--why`, `--log-level`, `--verbose` and `--quiet`. Settings are layered: the command line beats
`RUNSHEETS_*` environment variables (`RUNSHEETS_PORT`, `RUNSHEETS_DIR` for
the runbook, ...), which beat `./config/runsheets.yml` (or the file `--config` or
`RUNSHEETS_CONFIG` names), which beats `~/.config/runsheets/runsheets.yml`,
which beats the defaults bundled in `lib/runsheets/config/defaults.yml`. See
[docs/running/cli.md](docs/running/cli.md#settings).

## Sessions

Everything between starting `runsheets` and stopping it is one *session*.
It starts by asking who you are and why you are starting it (or take them
from `--engineer` and `--why`); the why is the session's first note. Then:

- **Select a runbook** and fill in its inputs: that starts its *run*. Run
  buttons are disabled until then.
- **Work through the steps**, or open any step, in any order, and run just
  that. A run is the record executions are written to, not an order you
  have to follow (see [docs/concepts/runs.md](docs/concepts/runs.md#a-run-is-a-record-not-a-sequence)).
- **Switch runbooks** whenever you like. Every run stays open, and
  selecting a runbook again returns to its run.
- **Write notes** on the session page as things happen.
- **End the session** with the button on the session page, or Ctrl-C.
  Every run closes with the status its work earns: `completed`,
  `partial`, or `opened`.

Everything you do, and every line of output, goes to a `session.log`
written as it happens and echoed to the terminal, like a Rails log:

```text
2026-10-10 01:17:19.589 INFO  [disk-space-triage 010-check-free-space #acd50b22502a] execute bash via bash
2026-10-10 01:17:19.589 INFO  [#acd50b22502a] $ df -h "$TARGET_DIR"
2026-10-10 01:17:19.602 INFO  [#acd50b22502a] > /dev/disk3s5   1.8Ti   1.4Ti   391Gi    79%   /System/Volumes/Data
2026-10-10 01:17:19.651 INFO  [#acd50b22502a] finished exit 0 in 0.06s
```

`--log-level`, `--verbose` and `--quiet` tune it; see
[docs/running/run-record.md](docs/running/run-record.md).

## A runbook is a directory

```text
staging-teardown/
  runbook.md              front matter + preamble (required)
  steps/
    010-confirm-nothing-to-preserve.md
    020-stop-the-pipeline.md
    030-drain-ecs-services.md
  verify.md               whole-procedure checks (optional)
  rollback.md             what to do when it fails partway (optional)
  assets/                 images referenced by the markdown
```

The directory name is the runbook's slug. Steps are ordered by filename;
numeric prefixes with gaps leave room to insert.

### runbook.md

```yaml
---
title: Staging Infrastructure Teardown and Rebuild
when_to_use: >
  The deployed stacks cannot be updated in place.
prerequisites:
  - AWSAdministratorAccess in the staging account
  - The staging branch is ready to fast-forward
blast_radius: >
  Destroys the staging database, container images, and DNS.
escalation: Stop and contact the platform owner if any stack delete fails twice.
tags: [aws, staging, destructive]
inputs:
  - name: AWS_PROFILE
    prompt: AWS profile with admin access
    default: staging-admin
  - name: DB_PASSWORD
    prompt: Database password
    secret: true
interpreters:
  ruby: bin/rails runner -
---
Everything below the front matter is the preamble and renders on the
landing page.
```

`inputs` become a form when a run starts. Values are exported as
environment variables to every executed block, so blocks refer to them as
`$NAME` and stay copy-pasteable into a terminal. Blank fields fall back to
the process environment, then to `default`. A `secret` input is masked in
the form and never written to the run record.

`interpreters` maps a language to the command that runs a file of it. The
defaults are `bash`, `sh`, `zsh` and `ruby`; a Rails project would map
`ruby` to `bin/rails runner -`, and `sql: psql -X -v ON_ERROR_STOP=1 -f`
makes `sql run` blocks execute through `psql`.

### Single-file runbooks

One markdown file works too: the front matter is the runbook's, every
`##` heading is a step, attributes go in an HTML comment after the
heading (`<!-- kind: verify, timeout: 30 -->`), and sections headed
**Verify** and **Rollback** stand in for the extra files. See
`examples/db-maintenance.md`.

### Step files

```yaml
---
title: Drain the ECS services
kind: automated          # automated | manual | verify
destructive: false
timeout: 600             # seconds, for executable blocks in this step
cwd: .                   # working directory, relative to the runbook
---
```

The body is ordinary markdown: the instruction, the command, and the "how to
tell it worked" line that every good step carries. `kind` defaults to
`automated` when the body has an executable block, otherwise `manual`.

## The fenced block convention

The info string's first word is the language. Any following words are
flags. A block with no flag is display only, whatever its language.

| Info string | Behaviour |
| --- | --- |
| ```` ```bash ```` | Display only. |
| ```` ```bash run ```` | Run button. Executed with the run's inputs in the environment; stdout, stderr and exit status recorded. |
| ```` ```bash destructive ```` | Run button behind a typed confirmation code issued by the server. Implies `run`. |
| ```` ```ruby run ```` | Same, executed with `ruby` (or the runbook's `interpreters.ruby`). |
| ```` ```bash background ```` | Start and Stop buttons. No timeout; output streams into the page; listed in the sidebar's Running panel; stopped when the run ends. |
| ```` ```bash terminal ```` | No Run button. "Run this in your own terminal, then confirm." An **I ran this** button records the confirmation, with an optional note. |
| ```` ```text expect ```` | Not executed. Shown beside the output of the executable block above it, with a matches/differs hint. |

An unknown flag, or `run` on a language that cannot execute, renders with a
visible warning instead of being ignored. `runsheets --check` lists them.

Each execution is a fresh process with the runbook directory as its working
directory. Nothing carries over between blocks except the environment.

## The run record

```text
~/.local/share/runsheets/runs/
  sessions/<session-id>/
    session.json    who, when, the notes, the runs, how it ended
    session.log     every action and its output, appended as it happens
  <runbook-slug>/<session-id>/
    run.json        steps, blocks, timestamps, exit codes, acknowledgements
    run.md          the same as a readable transcript
    blocks/
      020-stop-the-pipeline-1.1.cmd   the exact code that ran
      020-stop-the-pipeline-1.1.out   its stdout + stderr
```

Records live outside the runbook so captured output never lands next to
the docs in a repository. A runbook's landing page lists its previous
runs; each points back to its session. A session left running by a killed
process is closed as `interrupted` the next time runsheets starts.

## Security posture

- Binds to loopback by default. There is no multi-user story. `--bind` to
  another address is possible, warns, and is a bad idea off a network you
  control.
- Executes only blocks whose info string opts in. Everything else is inert.
- Every state-changing request needs a per-process token that only a page
  served by this process knows, and the `Host` header must be a loopback
  name. Together these stop a page on another origin from driving the tool.
- Every page sets a Content-Security-Policy that lets only the page's own
  script run. Raw HTML in a runbook renders; script in it does not, so a
  runbook cannot drive the tool either.
- Destructive blocks show the blast radius and need a confirmation code the
  server issues per block, checked server-side.
- Secret inputs reach the child process but never the run record. Captured
  output is redacted before it is written; plain string replacement, so an
  encoded secret is not caught.
- The tool writes nothing inside the runbook directory.
- Stopping the server ends the session: every run is closed and whatever it
  left running is stopped. Secret values never reach the session log.

## Development

```bash
bundle install
bundle exec rake test
bundle exec bin/runsheets --open examples/hello
```

The model (`Runbook`, `Step`, `Block`, `Renderer`, `Executor`,
`RunRecord`, `Run`, `Session`, `SessionLog`) has no dependency on Sinatra and is tested in
isolation; `Web` and `Pages` are tested with rack-test.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
