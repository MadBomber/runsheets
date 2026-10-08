# runsheets

Executable runbooks. A directory of markdown files becomes a local web page
where the steps read like a doc site, the commands the author marked as
runnable get a Run button, and everything that happens during a run is
recorded: the exact command, its output, exit status, timing, and the
operator's acknowledgements of the manual steps.

The rendering is the vehicle. The run record, the *runsheet*, is the point.

Status: early. Milestone 1 of the [plan](PLAN.md) works end to end; the
block convention may still change.

## Install

```bash
gem install runsheets
```

Requires Ruby 3.4 or newer.

## Run

```bash
runsheet path/to/runbook        # serve on http://127.0.0.1:4567/
runsheet --open path/to/runbook # and open the browser
runsheet --check path/to/runbook # load it, print authoring warnings, exit
```

Try the bundled example:

```bash
runsheet --open examples/hello
```

Options: `--port`, `--bind` (default loopback), `--runs-dir` (where run
records go; default `~/.local/share/runsheets/runs`, also settable with
`RUNSHEETS_RUNS_DIR`).

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
`ruby` to `bin/rails runner -`.

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
| ```` ```bash destructive ```` | Run button behind a typed confirmation. Implies `run`. |
| ```` ```ruby run ```` | Same, executed with `ruby` (or the runbook's `interpreters.ruby`). |
| ```` ```bash terminal ```` | No Run button. "Run this in your own terminal." For anything interactive. |
| ```` ```text expect ```` | Not executed. Shown as the expected output. |
| ```` ```bash background ```` | Reserved for long-running processes with Start and Stop buttons. Not executable yet. |

An unknown flag, or `run` on a language that cannot execute, renders with a
visible warning instead of being ignored. `runsheet --check` lists them.

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

- Binds to loopback only. There is no multi-user story.
- Executes only blocks whose info string opts in. Everything else is inert.
- Every state-changing request needs a per-process token that only a page
  served by this process knows, and the `Host` header must be a loopback
  name. Together these stop a page on another origin from driving the tool.
- Destructive blocks ask for a typed confirmation and show the blast radius.
- Secret inputs reach the child process but never the run record.
- The tool writes nothing inside the runbook directory.

## Development

```bash
bundle install
bundle exec rake test
bundle exec exe/runsheet --open examples/hello
```

The model (`Runbook`, `Step`, `Block`, `Renderer`, `Executor`,
`RunRecord`, `Session`) has no dependency on Sinatra and is tested in
isolation; `Web` and `Pages` are tested with rack-test.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
