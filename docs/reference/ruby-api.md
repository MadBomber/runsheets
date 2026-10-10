# Ruby API

The gem can be used without the web page: to validate runbooks in CI, to
run a runbook from a script, or to read run records. Everything below is
covered by the test suite.

```ruby
require "runsheets"
```

`require "runsheets"` loads the model. `Runsheets::Web`, `Pages`, `Assets`
and `CLI` are autoloaded on first use so a script that only reads records
never loads Sinatra.

## Loading a runbook

```ruby
runbook = Runsheets::Runbook.load("ops/runbooks/staging-teardown")      # a directory
runbook = Runsheets::Runbook.load("ops/runbooks/db-maintenance.md")     # or a single file

runbook.single_file?    # true for the second form
runbook.main_path       # runbook.md, or the single file
runbook.slug            # => "staging-teardown"
runbook.title           # => "Staging Infrastructure Teardown and Rebuild"
runbook.when_to_use     # String or nil
runbook.prerequisites   # Array of String
runbook.blast_radius    # String or nil
runbook.escalation      # String or nil
runbook.tags            # Array of String
runbook.destructive?    # true if a blast radius is declared or any step is destructive
runbook.inputs          # Array of Runbook::Input (name, prompt, default, secret?)
runbook.interpreters    # { "bash" => ["bash"], "ruby" => ["bin/rails", "runner", "-"], ... }
runbook.warnings        # Array of String, empty for a clean runbook

runbook.steps           # numbered steps, in order
runbook.verify          # Step or nil
runbook.rollback        # Step or nil
runbook.landing         # the runbook.md preamble as a Step with slug "runbook"
runbook.documents       # every document keyed by slug
runbook.step("020-stop-the-pipeline")
runbook.find_block("020-stop-the-pipeline-1")   # => [step, block] or nil
runbook.neighbors(step)                          # => [previous, next]
```

`Runbook.load` raises `Runsheets::RunbookError` when the path does not
exist, a directory has no `runbook.md`, or front matter is invalid.
Authoring problems that do not prevent loading are collected in
`warnings`. `Runsheets::SingleFile.split(markdown)` is the parser behind
the single-file shape, returning the preamble and the sections with their
attribute comments decoded.

### Steps

```ruby
step = runbook.steps.first
step.slug          # "010-confirm-nothing-to-preserve"
step.position      # 1
step.number        # "010"
step.title
step.kind          # "automated", "manual" or "verify"
step.destructive?
step.timeout       # seconds, Integer
step.cwd           # String or nil
step.data          # the raw front matter Hash
step.body          # markdown after the front matter
step.html          # rendered body
step.blocks        # Array of Block
step.executable_blocks
step.block("010-confirm-nothing-to-preserve-1")
step.warnings
```

### Blocks

```ruby
block = step.blocks.first
block.id           # "010-confirm-nothing-to-preserve-1"
block.lang         # "bash"
block.flags        # ["run"]
block.kind         # :display, :run, :destructive, :terminal, :expect, :background
block.executable?  # true for :run, :destructive and :background in a language the runbook's interpreters map
block.interpreters # that map: the defaults plus the front matter's entries
block.destructive?
block.background?
block.terminal?
block.acknowledgeable?  # true for :terminal
block.expect?
block.expect_for   # for an :expect block, the id of the executable block above it, or nil
block.code         # the fence contents, dedented
block.line         # line number of the opening fence
block.warnings
block.referenced_variables   # ["AWS_PROFILE", "CLUSTER"]
block.to_h
```

### Verification and reloading

```ruby
runbook.verify_documents   # verify-kind steps, then verify.md
runbook.verify_blocks      # their executable blocks
runbook.stale?             # a source file changed since load
```

## Validating in CI

```ruby
#!/usr/bin/env ruby
require "runsheets"

failed = false
Dir.glob("ops/runbooks/*/runbook.md").each do |path|
  runbook = Runsheets::Runbook.load(File.dirname(path))
  runbook.warnings.each { |w| warn "#{runbook.slug}: #{w}"; failed = true }
rescue Runsheets::RunbookError => e
  warn "#{path}: #{e.message}"
  failed = true
end
exit(failed ? 1 : 0)
```

Or simply `runsheets --check DIR` per runbook.

## Running a runbook from a script

`Session` is the same object the web page drives. A session needs an
engineer and a reason, like the start page; it creates its directory and
log under `runs_root` as soon as it is built.

```ruby
runbook = Runsheets::Runbook.load("examples/hello")
session = Runsheets::Session.new(engineer: "ci", why: "nightly check of the hello runbook",
                                 runs_root: "/tmp/runs", runbook:)

session.open(runbook, inputs: { "NAME" => "script" })

runbook.steps.first(2).each do |step|
  step.executable_blocks.each do |block|
    execution = session.execute(block.id).wait
    puts "#{block.id}: #{execution.state} #{execution.exit_status}"
    puts execution.output
    abort "stopping at #{block.id}" unless execution.success?
  end
  session.mark_step(step.slug, status: "done", note: "run by script")
end

session.note!("first two steps pass")
session.end!("script finished")
puts session.run.dir      # /tmp/runs/hello/20261010T012715
puts session.run.status   # "partial": two of six steps marked
```

`Session.new` takes `engineer:` and `why:` (both required; a blank one
raises `Runsheets::RunError`), `runs_root:` (default `Runsheets.runs_dir`),
`library:` or `runbook:` (the one runbook served, put on screen),
`token:`, `executor:` (default `Executor.new`), `log_level:` (default
`"info"`), `echo:` (an IO the log is echoed to, or `nil` for none) and
`now:`. Building it also closes any earlier session in `runs_root` left
running by a process that is gone.

`open(runbook, inputs:)` puts the runbook on screen and establishes its
run, or returns the run it already has (the inputs are then ignored). The
methods that act on "this runbook" (`execute`, `acknowledge`,
`mark_step`, `change_inputs`, `run`) go to the run of the runbook on
screen. `execute` returns immediately with a running `Execution`; `wait`
blocks until it is reaped. It raises `Runsheets::RunError` when the
runbook on screen has no run, the block is unknown or not executable, or
a referenced declared input is blank.

`end!(how)` closes every run with its derived status (`completed`,
`partial` or `opened`), stopping anything still running first, writes the
records, and logs `how` as the reason. Ending twice does nothing.

Other session methods:

```ruby
session.id                      # "20261010T012715", the directory name
session.dir                     # <runs_root>/sessions/<id>
session.engineer
session.why                     # the first note's text
session.notes                   # [{ at:, text: }, ...]
session.host
session.started_at
session.ended_at                # nil until end!
session.elapsed
session.status                  # "running" or "ended"
session.ended?
session.log                     # the SessionLog
session.token                   # the token the web layer requires

session.show(runbook)           # put a runbook on screen without opening a run
session.runbook                 # the runbook on screen
session.runs                    # every Run, in the order their runbooks were selected
session.run_for(slug)           # the Run of a runbook, or nil
session.current                 # the Run of the runbook on screen, or nil
session.run                     # current's RunRecord, or nil
session.active?                 # the runbook on screen has an open run
session.carried_inputs          # non-secret inputs given earlier in the session, by name
session.resolve_inputs(given)   # what the inputs would be for the runbook on screen
session.change_inputs(given)    # change the current run's inputs; a blank secret keeps its value
session.acknowledge(block_id, note: "...")  # record that a terminal block was run by hand
session.ack(block_id)           # the latest acknowledgement Hash, or nil
session.step_status(slug)       # "done", "skipped" or nil
session.secret_inputs_set       # names of secret inputs that have a value
session.history                 # previous RunRecords of the runbook on screen, newest first
session.refresh_runbook!        # reload the runbook on screen if a source file changed

session.execution(id)           # a live Execution by id, in any run
session.executions              # every Execution in the session
session.running_executions      # those whose process is still alive
session.running                 # [[run, execution], ...] for each one still running
session.stop(execution_id)      # TERM then KILL its process group, whichever runbook started it

session.write!                  # rewrite session.json
session.to_h                    # the session.json data

Runsheets::Session.close_interrupted(runs_root)   # close sessions left running by a dead process; returns their ids
```

Executing a destructive block without the right `confirm` raises
`Runsheets::Run::ConfirmationRequired` (also reachable as
`Runsheets::Session::ConfirmationRequired`), a `RunError` whose
`challenge` is the code to pass back:

```ruby
begin
  session.execute("040-exercise-failure-1")
rescue Runsheets::Run::ConfirmationRequired => e
  session.execute("040-exercise-failure-1", confirm: e.challenge)
end
```

### Runs

`Runsheets::Run` is one runbook's part of a session. `Session#open`
builds them; scripts usually reach them through `session.current` or
`session.run_for(slug)`.

```ruby
run = session.current
run.runbook
run.slug
run.record                      # its RunRecord
run.inputs                      # the inputs in force, secrets included (memory only)
run.open?                       # until the session ends
run.execute(block_id, confirm: nil)
run.challenge_for(block_id)     # the code a destructive block currently expects
run.stop(execution_id)
run.acknowledge(block_id, note: nil)
run.mark_step(step_slug, status: "done", note: nil)
run.change_inputs(given)        # recorded as an inputs event and logged
run.executions
run.running_executions
run.close!                      # stop what is running, close the record; returns the status

Runsheets::Run.resolve_inputs(runbook, given, carried: {})
# for each input: given, else carried (never a secret), else ENV, else the default
```

### The session log

```ruby
log = Runsheets::SessionLog.new("/tmp/session.log", level: "info", echo: $stdout, echo_level: "info")
log.info("deployed", tags: ["release", "step-3"])
# 2026-10-10 14:02:41.200 INFO  [release step-3] deployed
log.debug(text, tags: [])       # also warn, error, fatal
log.add("warn", text, tags: [])
log.output_stream(["#1a2b"])    # a sink for output chunks: each complete line becomes "> line"
log.path
log.level
log.close
```

Multi-line text becomes one log line per line, each with the same prefix.
An unknown level raises `Runsheets::ConfigError`.

## Executions

```ruby
execution.id
execution.block_id
execution.step_slug
execution.command        # ["bash"]
execution.background?    # true for a background block (no timeout)
execution.state          # :pending, :running, :finished, :timed_out, :stopped, :failed
execution.running?
execution.finished?      # true for finished, timed_out, stopped and failed
execution.success?       # finished with exit status 0
execution.failure?       # finished non-zero, timed_out or failed; never stopped
execution.stopped?
execution.timed_out?
execution.pid
execution.exit_status
execution.signal
execution.error          # why it could not start
execution.started_at
execution.finished_at
execution.duration
execution.output         # the whole .out file, UTF-8, scrubbed
execution.output(tail: 4096)
execution.output_size
execution.cmd_path
execution.log_path
execution.wait(limit = nil)
execution.to_h
```

## Running one block by hand

`Executor` is independent of runbooks and records.

```ruby
Dir.mktmpdir do |dir|
  execution = Runsheets::Execution.new(
    id: "x", block_id: "b", step_slug: "s", command: %w[bash],
    cmd_path: File.join(dir, "b.cmd"), log_path: File.join(dir, "b.out"),
    timeout: 10
  )
  Runsheets::Executor.new.run(execution, code: "echo $GREETING\n", env: { "GREETING" => "hi" }, cwd: dir)
  execution.output   # => "hi\n"
end
```

`run` is `start` followed by `wait`. `start` raises nothing; a spawn
failure leaves the execution in state `:failed` with `error` set.
`executor.stop(execution)` asks the reaper to end the process group.

`start` takes a `redactor:` that every chunk of output passes through
before it is written:

```ruby
redactor = Runsheets::Redactor.new("DB_PASSWORD" => "hunter2")
redactor.redact("password=hunter2")   # => "password=[redacted DB_PASSWORD]"
Runsheets::Executor.new.run(execution, code: "echo $DB_PASSWORD\n", env: { "DB_PASSWORD" => "hunter2" }, redactor:)
execution.output                       # => "[redacted DB_PASSWORD]\n"
```

`Redactor.for(inputs, runbook)` builds the one a run uses: every
`secret` input that has a value. `feed(chunk)` and `flush` are the
streaming form, which holds back a tail that could be the start of a
secret until the next chunk settles it.

## Reading run records

```ruby
runs = Runsheets::RunRecord.list(Runsheets.runs_dir, "staging-teardown")
run  = runs.first

run.id
run.dir
run.status          # "running", "completed", "partial", "opened", "interrupted" ("abandoned" in old records)
run.session_id      # the session it belongs to, or nil in old records
run.active?
run.started_at
run.finished_at
run.duration
run.inputs          # non-secret inputs
run.events          # Array of Hash with symbol keys
run.executions      # Array of Hash with symbol keys
run.step_status     # { "010-..." => "done" }
run.acks            # { "020-...-3" => { at:, step:, note: } } terminal confirmations
run.kind            # "run", or "verify" in records from before sessions
run.verify?
run.closing_status(step_slugs)   # the status it would close with now
run.latest_executions      # block id => its most recent execution Hash
run.unresolved_failures    # latest executions that are failures
run.last_step              # the step of the latest event, or nil
run.drift(runbook)         # [{ block_id:, status: :changed, diff: [Diff::Line...] }, { status: :missing, ... }]
run.steps_done
run.failed_executions
run.summary         # { id:, kind:, started_at:, finished_at:, status:, duration:, executions:, failures:, unresolved:, steps_done:, last_step: }
run.transcript      # the run.md text
run.to_h            # the run.json data
```

`RunRecord.load(dir)` reads one directory. Records that cannot be parsed are
skipped by `list`. `RunRecord.start(runs_root, runbook, session_id:, inputs: {})`
creates a run directory named by the session id and writes the first
version; `Run` calls it. `change_inputs(inputs, runbook)` records an
`inputs` event, and `finish!(status:)` closes the record with one of the
final statuses.

## Searching

```ruby
library  = Runsheets::Library.load("ops/runbooks")
runbooks = library.entries.select(&:ok?).map { [it.slug, it.runbook] }

results = Runsheets::Search.run(runbooks, 'vacuum "worst table"')
results.each do |result|
  result.slug     # "database/maintenance"
  result.score    # higher is better; results come best first
  result.hits.each { puts "#{it.title}: #{it.snippet}" }
end

Runsheets::Search.terms('Stop "the pipeline"')   # => ["stop", "the pipeline"]
```

Every term must appear somewhere in a runbook for it to match.
`Search::Query.parse(string)` gives the parsed query, whose `count`,
`snippet` and `highlight` can be called on their own; `terms`, `text_of`
and `plain` are module functions.

## Rendering markdown

```ruby
result = Runsheets::Renderer.render(markdown, id_prefix: "doc")
result.html     # with executable blocks wrapped
result.blocks   # Array of Block
```

`Runsheets::Renderer.rewrite_relative_urls(html, base_dir)` points relative
`src` and `href` values at `/files/`, as the step pages do.

## Serving

```ruby
require "runsheets"

runbook = Runsheets::Runbook.load("examples/hello")
options = { runs_root: Runsheets.runs_dir, log_level: "info", echo: $stdout }

# With the engineer and the reason known, start the session now:
session = Runsheets::Session.new(engineer: "Pat", why: "monthly checks", runbook:, **options)
Runsheets::Web.configure_for(session, bind: "127.0.0.1", port: 4567, runbook:)

# Or leave it to the start page:
Runsheets::Web.configure_for(nil, bind: "127.0.0.1", port: 4567, runbook:)
              .prepare_start(session_options: options, engineer: "Pat")

Runsheets::Web.run!
Runsheets::Web.session&.end!("server stopped")
```

`configure_for(session, bind:, port:, library:, runbook:)` wires in a
library of runbooks or one runbook, and the session if it has started, and
restricts permitted hosts to loopback plus the bind address.
`prepare_start(session_options:, engineer:)` says what a session started
from the start page is built with and who the page suggests.
`Web.start_session(engineer:, why:)` is what the start page calls;
`Web.session` is the session once it has started. This is what `runsheets`
does, ending the session when the server stops.

## Configuration

```ruby
Runsheets.config            # Runsheets::Config: the layered settings (see the CLI page)
Runsheets.config.port       # 4567 unless the config file, RUNSHEETS_PORT or the CLI say otherwise
Runsheets.config.files      # the config files that exist and were read
Runsheets.config.to_config_yaml   # the settings in force as config-file text (what --dump prints)
Runsheets.configure({ port: 4580 }, path: "/etc/runsheets.yml")  # install your own
Runsheets.runs_dir          # Runsheets.config.runs_dir unless assigned
Runsheets.runs_dir = "/srv/runs"
Runsheets.reset_config!     # rebuild from the layers on next use
Runsheets::VERSION
```

`Runsheets::Config` is a [myway_config](https://github.com/madbomber/myway_config)
class. Its layers, lowest to highest: `lib/runsheets/config/defaults.yml` in the gem,
`~/.config/runsheets/runsheets.yml`, the project config (`./config/runsheets.yml`,
or the file `path:` or `RUNSHEETS_CONFIG` names), `RUNSHEETS_*`
variables, then the overrides hash. A `Runsheets::ConfigError` is raised
for a port that is not a whole number, an unknown log level, or a named
config file that is missing. `engineer`, `why`, `log_level` and `quiet`
are settings like the rest.

## Errors

| Class | Raised when |
| --- | --- |
| `Runsheets::Error` | Base class. |
| `Runsheets::RunbookError` | A runbook cannot be loaded. |
| `Runsheets::RunError` | A session or run operation is not allowed in the current state, or a session is started without an engineer or a reason. |
| `Runsheets::Run::ConfirmationRequired` | A destructive block was executed without its code; a `RunError` carrying `challenge`. |
| `Runsheets::ConfigError` | A setting is invalid: a port, a log level, a missing config file. |
