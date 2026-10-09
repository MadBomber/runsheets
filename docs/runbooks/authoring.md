# Authoring Guide

The mechanics are in the other pages of this section. This page is about
writing steps an operator can follow at two in the morning.

## What every step carries

1. **The instruction.** One or two sentences saying what this step does and
   why it is here.
2. **The command.** One executable block, or one `terminal` block, or
   nothing for a manual step. If a step needs three commands that must all
   succeed, consider three steps, or one block with `set -e` at the top.
3. **How to tell it worked.** A sentence, or an `expect` block, describing
   the output of a successful run. The operator compares; runsheets records.

````markdown
---
title: Drain the ECS services
timeout: 600
---

Scale the web service to zero and wait for the running tasks to stop. The
load balancer will start returning 503s as soon as the last task exits.

```bash run
set -euo pipefail
aws ecs update-service --cluster "$CLUSTER" --service web --desired-count 0 > /dev/null
aws ecs wait services-stable --cluster "$CLUSTER" --services web
aws ecs describe-services --cluster "$CLUSTER" --services web \
  --query 'services[0].runningCount'
```

It worked when the last line prints `0`.

```text expect
0
```
````

## Choosing the block kind

| The command... | Use |
| --- | --- |
| is safe to re-run and non-interactive | `run` |
| destroys or changes something irreversible | `destructive` |
| needs a TTY, a browser, or a prompt answered | `terminal` |
| is an example of output, a config file to copy, or SQL for another client | no flag |
| is a tunnel or watcher that must stay up across steps | `background` |

If you are unsure whether something is destructive, it is. The confirmation
costs the operator three seconds; a missed confirmation costs a lot more.

## Marking the whole runbook

Fill in `blast_radius` and `escalation` in `runbook.md` whenever any step is
destructive. The blast radius appears in a red banner on every destructive
step, right above the Run button, so it is read at the moment it matters,
not only on the landing page.

## Timeouts

The default is ten minutes per execution. Set `timeout` on steps that wait
on cloud operations (`--wait` flags, stack deletes) to something generous,
and on quick checks to something short, so a hung command is noticed. A
timed-out execution is recorded as such, and the whole process group is
killed, so no `aws` child is left behind.

## Manual steps

A manual step is a `kind: manual` file with instructions and no executable
block. Write the instruction as a checklist the operator ticks mentally, and
suggest what to put in the note:

```markdown
---
title: Confirm nothing needs preserving
kind: manual
---

Before destroying the staging database, confirm with the team channel that
no one has test data they need. Record who confirmed in the note.
```

The note goes into the run record next to the timestamp. That is the audit
trail the "date the last verification by hand" instruction never produced.

## Converting an existing runbook

Most existing runbooks are one markdown file with `## Step` headings.

1. Create a directory named for the runbook. Move the file in as
   `runbook.md`.
2. Add front matter with at least a `title`. Move the "before you start"
   prose into `when_to_use`, `prerequisites`, `blast_radius` and
   `escalation`.
3. Cut each `## Step` section into `steps/NNN-slug.md`. Use the heading as
   `title`. Leave gaps in the numbers.
4. Add `run` to the fences the operator is meant to execute. Leave the rest
   alone; they are display only by default and nothing is lost.
5. Replace hard-coded account ids, profiles and names with inputs.
6. Move any "if it goes wrong" section into `rollback.md` and any "check it
   worked" section into `verify.md`.
7. Run `runsheets --check .` and fix the warnings.
8. Run it once for real, from a clean shell, and finish the run. Now the
   runbook has a record of its last verification that nobody had to date by
   hand.

Single-file runbooks with headings as steps may be supported directly in a
later milestone; see the [roadmap](../roadmap.md).

## Checking your work

```bash
runsheets --check path/to/runbook
```

Reports, with the file and block they belong to:

- unknown or conflicting block flags
- `run` on a language with no interpreter
- `automated` steps with nothing executable, and unknown `kind` values
- non-positive timeouts
- missing `title`, invalid input names, duplicate step slugs
- no steps at all

It exits 1 when there are warnings, so it can gate a pull request in a
repository of runbooks.

## Things that look like they should work but do not

- **`cd` in one block, then a relative path in the next.** Every block starts
  in the runbook directory (or the step's `cwd`). Put the `cd` in each block
  that needs it, or set `cwd` on the step.
- **`export FOO=...` for a later block.** Same reason. Use an input, or
  compute the value again. A `capture` flag that stores a block's output as
  an input is on the roadmap.
- **A fence inside a blockquote.** It renders, but runsheets does not parse
  flags there. Keep executable blocks at the top level or inside list items.
- **Interactive prompts.** A `run` block has no stdin; `read` returns
  immediately with nothing. Use `terminal`.
