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
runbook = Runsheets::Runbook.load("ops/runbooks/staging-teardown")

runbook.slug            # => "staging-teardown"
runbook.title           # => "Staging Infrastructure Teardown and Rebuild"
runbook.when_to_use     # String or nil
runbook.prerequisites   # Array of String
runbook.blast_radius    # String or nil
runbook.escalation      # String or nil
runbook.last_verified   # Date or nil
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

`Runbook.load` raises `Runsheets::RunbookError` when the directory or
`runbook.md` is missing or front matter is invalid. Authoring problems that
do not prevent loading are collected in `warnings`.

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
block.executable?  # true for :run, :destructive and :background in a language with an interpreter
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

Or simply `runsheet --check DIR` per runbook.

## Running a runbook from a script

`Session` is the same object the web page drives.

```ruby
runbook = Runsheets::Runbook.load("examples/hello")
session = Runsheets::Session.new(runbook:, runs_root: "/tmp/runs")

session.start_run(inputs: { "NAME" => "script" })

runbook.steps.each do |step|
  step.executable_blocks.each do |block|
    execution = session.execute(block.id).wait
    puts "#{block.id}: #{execution.state} #{execution.exit_status}"
    puts execution.output
    abort "stopping at #{block.id}" unless execution.success?
  end
  session.mark_step(step.slug, status: "done", note: "run by script")
end

session.finish_run(status: "completed")
puts session.run.dir
```

`execute` returns immediately with a running `Execution`; `wait` blocks
until it is reaped. It raises `Runsheets::RunError` when there is no active
run, the block is unknown or not executable, or a referenced declared input
is blank.

Other session methods:

```ruby
session.active?
session.run                     # the RunRecord, or nil
session.resolve_inputs(given)   # what the inputs would be, without starting a run
session.execution(id)           # a live Execution by id
session.executions
session.running_executions      # Executions whose process is still alive
session.stop(execution_id)      # TERM then KILL its process group; state becomes :stopped
session.challenge_for(block_id) # the confirmation code a destructive block currently expects
session.execute(block_id, confirm: code)   # run a destructive block
session.acknowledge(block_id, note: "...")  # record that a terminal block was run by hand
session.ack(block_id)           # the latest acknowledgement Hash, or nil
session.secret_inputs_set       # names of secret inputs that have a value
session.step_status(slug)       # "done", "skipped" or nil
session.history                 # previous RunRecords, newest first
session.token                   # the session token the web layer requires
```

Executing a destructive block without the right `confirm` raises
`Runsheets::Session::ConfirmationRequired`, a `RunError` whose `challenge`
is the code to pass back. `finish_run` stops anything still running before
it closes the record.

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

`Redactor.for(inputs, runbook)` builds the one a session uses: every
`secret` input that has a value. `feed(chunk)` and `flush` are the
streaming form, which holds back a tail that could be the start of a
secret until the next chunk settles it.

## Reading run records

```ruby
runs = Runsheets::RunRecord.list(Runsheets.runs_dir, "staging-teardown")
run  = runs.first

run.id
run.dir
run.status          # "running", "completed", "abandoned"
run.active?
run.started_at
run.finished_at
run.duration
run.inputs          # non-secret inputs
run.events          # Array of Hash with symbol keys
run.executions      # Array of Hash with symbol keys
run.step_status     # { "010-..." => "done" }
run.acks            # { "020-...-3" => { at:, step:, note: } } terminal confirmations
run.steps_done
run.failed_executions
run.summary         # { id:, started_at:, finished_at:, status:, duration:, executions:, failures:, steps_done: }
run.transcript      # the run.md text
run.to_h            # the run.json data
```

`RunRecord.load(dir)` reads one directory. Records that cannot be parsed are
skipped by `list`.

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
require "runsheets/web"

session = Runsheets::Session.new(runbook:)
Runsheets::Web.configure_for(session, bind: "127.0.0.1", port: 4567)
Runsheets::Web.run!
```

`configure_for` wires the session in and restricts permitted hosts to
loopback plus the bind address. This is what `runsheet` does.

## Configuration

```ruby
Runsheets.runs_dir          # ENV["RUNSHEETS_RUNS_DIR"] or ~/.local/share/runsheets/runs
Runsheets.runs_dir = "/srv/runs"
Runsheets::VERSION
```

## Errors

| Class | Raised when |
| --- | --- |
| `Runsheets::Error` | Base class. |
| `Runsheets::RunbookError` | A runbook cannot be loaded. |
| `Runsheets::RunError` | A run operation is not allowed in the current state. |
