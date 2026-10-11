---
title: Runbook tasks from local .loki files
when_to_use: >
  An example of a runbook whose blocks call asgard tasks defined in .loki
  files kept beside it, so a long or reusable script lives in a task file
  and the runbook block stays one line.
prerequisites:
  - The `asgard` command on PATH (`gem install asgard`)
escalation: Nobody; this runbook only reads.
tags: [asgard, loki, scripts, safe, example]
inputs:
  - name: NAME
    prompt: Who to greet
    default: operator
  - name: TARGET_DIR
    prompt: Directory whose file system disk_check measures
    default: /tmp
  - name: MAX_USE
    prompt: Highest acceptable disk use, in percent
    default: "95"
---

# Runbook tasks from local .loki files

This runbook is one markdown file, and its scripts are
[asgard](https://github.com/MadBomber/asgard) tasks in `.loki` files in
the same directory:

```text
runbooks_with_scripts/
  asgard-tasks.md   this runbook
  .loki             asgard's entry point: imports the other .loki files
  greet.loki        greet NAME
  checks.loki       ruby_check, disk_check [DIR], and health, which runs both
```

Two facts make it work:

- runsheets runs a single-file runbook's blocks in the directory holding
  the runbook (a step's `cwd` can change that).
- asgard looks for a `.loki` file in its working directory first, then in
  each directory above. The `.loki` here is found before any other, such as
  the one at the root of the runsheets repository.

The `.loki` file marks the directory as asgard's project root and loads
the task files beside it:

```ruby
import "*.loki"
```

Each task file reopens `class Tasks`, as in `greet.loki`:

```ruby
class Tasks
  desc "greet NAME", "Say hello to NAME"
  def greet(name = "World") = puts "Hello, #{name}, from a task beside the runbook!"
end
```

A block then calls the task by name, with runbook inputs as arguments or
in the environment. Every block in this runbook only reads.

## Find the local task file
<!-- kind: verify, timeout: 30 -->

`asgard --doctor` reports which `.loki` file it is using. It should be the
one beside this runbook. The doctor's full report also lists every
imported file and the tasks each defines; the block prints only the line
that names the file in use.

```bash run
asgard --doctor | grep -o 'using .loki marker: [^[:cntrl:]]*'
```

```text expect
using .loki marker: {{any}}/runbooks_with_scripts/.loki
```

## List the tasks

The task list comes from the local `.loki` files, together with asgard's
built-in commands (`help`, `schedule`, `tree`).

```bash run
asgard tree
```

## Run a task with an argument
<!-- timeout: 30 -->

`greet` is defined in `greet.loki`. The `NAME` input is passed as its
argument.

```bash run
asgard greet "$NAME"
```

```text expect
Hello, {{any}}, from a task beside the runbook!
```

## Run a task with dependencies
<!-- timeout: 60 -->

`health` in `checks.loki` declares `depends_on [:ruby_check, :disk_check]`,
so asgard runs both checks in parallel before it. A dependency gets no
arguments, so `disk_check` reads its directory from `TARGET_DIR` and its
limit from `MAX_USE`, both runbook inputs in the environment. If either
check fails, `health` does not run and the block fails.

```bash run
asgard health
```

The two checks run in parallel and may print in either order.

```text expect
{{any}}_check: {{any}}
{{any}}_check: {{any}}
health: all checks passed
```

## Verify

Disk use under `TARGET_DIR` is at or below `MAX_USE`, checked by the same
task the health check runs, this time called directly with an argument.

```bash run
asgard disk_check "$TARGET_DIR"
```

## Rollback

Nothing to undo: no task in this directory changes anything.
