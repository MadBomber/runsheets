# runsheets

Executable runbooks. A directory of markdown files becomes a local web page
where the steps read like a doc site, the commands the author marked as
runnable get a Run button, and everything that happens during a run is
recorded: the exact command, its output, exit status, timing, and the
operator's acknowledgements of the manual steps.

The rendering is the vehicle. The run record, the *runsheet*, is the point.

Status: all four milestones of the [plan](PLAN.md) are built. Every block
kind in the convention below is live, verify steps run on their own, a
verified run can stamp `last_verified` into the runbook, and a runbook can
be a directory or a single markdown file. Vocabulary: the document is the
*runbook*; the record of one run is the *runsheet*.

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
you like. Started on such a library, the browser opens on a folder tree in
the left pane; selecting a runbook shows its description, prerequisites,
inputs, steps and previous runs in the main pane, with an **Open** button.
A `README.md` in a folder is shown as that folder's description. Try the
bundled examples:

```bash
runsheets --open examples                      # all three, pick one in the browser
runsheets --open examples/hello                # safe to run: every block kind
runsheets --check examples/staging-teardown    # a realistic AWS teardown
runsheets --open examples/db-maintenance.md    # a single all-in-one file, sql blocks via psql
```

Options: `--port`, `--bind` (default loopback), `--runs-dir` (where run
records go; default `~/.local/share/runsheets/runs`), `--open`, `--check`,
`--init`, `--config FILE`, and `--dump` to print the settings in force as a
config file (redirect it to save them). Settings are layered: the command line beats
`RUNSHEETS_*` environment variables (`RUNSHEETS_PORT`, `RUNSHEETS_DIR` for
the runbook, ...), which beat `./config/runsheets.yml` (or the file `--config` or
`RUNSHEETS_CONFIG` names), which beats `~/.config/runsheets/runsheets.yml`,
which beats the defaults bundled in `lib/runsheets/config/defaults.yml`. See
[docs/running/cli.md](docs/running/cli.md#settings).

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
last_verified: 2026-09-12
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
~/.local/share/runsheets/runs/<runbook-slug>/<yyyymmddThhmmss>/
  run.json          steps, blocks, timestamps, exit codes, acknowledgements
  run.md            the same as a readable transcript
  blocks/
    020-stop-the-pipeline-1.1.cmd   the exact code that ran
    020-stop-the-pipeline-1.1.out   its stdout + stderr
```

Runs live outside the runbook so captured output never lands next to the
docs in a repository. The landing page lists previous runs.

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
- The tool writes nothing inside the runbook directory, except the
  `last_verified` line of `runbook.md`, offered after a run that verified
  the runbook and written only when asked.
- Stopping the server ends an active run as abandoned and stops whatever it
  left running.

## Development

```bash
bundle install
bundle exec rake test
bundle exec bin/runsheets --open examples/hello
```

The model (`Runbook`, `Step`, `Block`, `Renderer`, `Executor`,
`RunRecord`, `Session`) has no dependency on Sinatra and is tested in
isolation; `Web` and `Pages` are tested with rack-test.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
