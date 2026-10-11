---
tags:
  - Authoring
  - asgard
  - Examples
---

# runsheets + asgard

> *"Loki writes the tricks. Asgard runs them."*

A runbook block should be short enough to read at a glance. Some work isn't:
a health check that runs four probes in parallel, a cleanup with a dozen
guard clauses, a script you want to use from three different runbooks.
[**asgard**](https://github.com/MadBomber/asgard) is a Ruby task runner
that gives that code a home, so the runbook block can stay one line:

```bash run
asgard health
```

## Meet asgard

asgard is a [Thor](https://github.com/rails/thor)-based task runner. Tasks
are plain Ruby methods in `.loki` files, and anything Thor can do is
available.

<div class="grid cards" markdown>

- :material-graph-outline: **Dependencies, in parallel**

    ---

    `depends_on :setup, [:lint, :build], :test` runs `setup`, then `lint`
    and `build` concurrently, then `test`. Each dependency runs at most
    once per invocation, and circular dependencies are caught at startup.

- :material-console: **Real CLI ergonomics**

    ---

    Positional arguments, typed options, `--help` for every task,
    subcommands, aliases and unambiguous-prefix matching, all from Thor.

- :material-script-text-outline: **Shell and polyglot helpers**

    ---

    `sh` runs a command or a heredoc and exits with its status. `shebang
    :python3` (or `:node`, `:perl`, `:bash` ...) runs a script in another
    language.

- :material-folder-search-outline: **Finds its tasks**

    ---

    asgard looks for a `.loki` file in the working directory, then in each
    directory above it. `import "*.loki"` splits tasks across files.

- :material-calendar-clock: **Scheduled tasks**

    ---

    `schedule :backup, at: "02:00"` plus `asgard schedule install` puts a
    task under launchd, systemd user timers or Windows Task Scheduler.

- :material-stethoscope: **Built-in diagnostics**

    ---

    `asgard --doctor` reports which `.loki` file is in use, every imported
    file, and the tasks each defines. `dotenv` and `env(:name, default)`
    handle configuration.

</div>

```bash
gem install asgard
```

## Why they fit together

The two tools split the work cleanly.

| runsheets | asgard |
| --- | --- |
| The *why*: prose, context, warnings, rollback | The *how*: the code itself |
| Decides **when** a step runs, and who confirmed it | Decides **how** a task runs, and in what order |
| Records the command, output, exit status and timing | Gives that command a short, stable name |
| Inputs reach blocks as environment variables | Tasks read them with `env(:target_dir, ".")` |

Two facts make the pairing work with no configuration:

1. **runsheets runs a single-file runbook's blocks in the runbook's own
   directory** (a step's `cwd` can change that).
2. **asgard finds the nearest `.loki` file**, starting in its working
   directory and walking up.

So a `.loki` file placed beside a runbook is the one its blocks use. The
runbook and its task files move, version and get reviewed together.

```text
runbooks_with_scripts/
  asgard-tasks.md   the runbook
  .loki             asgard's entry point: import "*.loki"
  greet.loki        greet NAME
  checks.loki       ruby_check, disk_check [DIR], and health, which runs both
```

Inputs flow straight through. The runbook declares `TARGET_DIR` and
`MAX_USE` as inputs; runsheets exports them; the task reads them:

```ruby
class Tasks
  desc "disk_check [DIR]", "Fail when the file system holding DIR is more than MAX_USE percent full"
  def disk_check(dir = env(:target_dir, "."))
    used  = disk_use(dir)
    limit = env(:max_use, "95").to_i
    puts "disk_check: #{dir} is #{used}% used, limit #{limit}%"
    exit 1 if used > limit
  end

  depends_on [:ruby_check, :disk_check]
  desc "Run every check, in parallel"
  def health = puts "health: all checks passed"
end
```

And runsheets still checks the result. An `expect` block with `{{any}}`
wildcards accepts the parallel checks finishing in either order:

````markdown
```bash run
asgard health
```

```text expect
{{any}}_check: {{any}}
{{any}}_check: {{any}}
health: all checks passed
```
````

If either check fails, `health` doesn't run, the block exits non-zero, and
the failure goes into the run record with its output.

## Try it

```bash
gem install asgard
runsheets --open examples/single_md_file_runbooks/runbooks_with_scripts/asgard-tasks.md
```

The example only reads. It finds the local `.loki`, lists its tasks, runs
one with an argument, and runs `health` with its parallel dependencies.

## When to reach for asgard

- A block is longer than about ten lines, or has its own control flow.
- The same logic appears in more than one runbook.
- You want to run the step from a terminal too, by name, with `--help`.
- A step needs ordered or parallel sub-steps.

Keep a command in the runbook when it is short and the reader needs to see
exactly what it does. A runbook full of one-word tasks hides what it does
from the person running it.

[asgard documentation :material-arrow-right:](https://madbomber.github.io/asgard){ .md-button }
[asgard on GitHub](https://github.com/MadBomber/asgard){ .md-button }
