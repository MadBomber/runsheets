---
tags:
  - Getting started
  - Examples
---

# Example Runbooks

runsheets ships with five example runbooks. Reading them is the quickest way
to see what a good runbook looks like, and running the safe ones shows you
every button on the page.

```bash
runsheets --open examples
```

That serves the whole `examples/` directory as a library, so you can pick a
runbook from the folder tree. The examples are grouped by shape:

- `directory_based_runbooks/`: a `runbook.md` beside a `steps/` folder
  with one file per step.
- `single_md_file_runbooks/`: one markdown file per runbook, where each
  `##` heading is a step, plus the plain documents they link to.

| Example | Shape | Safe to run | Shows off |
| --- | --- | --- | --- |
| [Hello, runsheets](#hello-runsheets) | directory | :material-check: yes | every block kind |
| [Disk space triage](#disk-space-triage) | single file | :material-check: yes, only reads | expected output, links to plain documents |
| [Runbook tasks from local .loki files](#runbook-tasks-from-local-loki-files) | single file + `.loki` files | :material-check: yes, only reads; needs [asgard](asgard.md) | short blocks that call reusable tasks |
| [Monthly PostgreSQL maintenance](#monthly-postgresql-maintenance) | single file | :material-alert: needs a database | `sql` blocks through `psql` |
| [Staging infrastructure teardown](#staging-infrastructure-teardown) | directory | :material-close: no, read it | a realistic destructive procedure |

## Hello, runsheets

`examples/directory_based_runbooks/hello`. **Start here.**

A fixture that uses every block kind and touches nothing real: `run`
blocks in bash and ruby, a `terminal` step you do in your own shell, a
`background` clock with Start and Stop, a `destructive` block behind a typed
confirmation, a deliberate failure and a timeout, and `expect` blocks
checked against real output. It has verify and rollback documents too, so
the Checks page and the Rollback panel have something to show.

```bash
runsheets --open examples/directory_based_runbooks/hello
```

## Disk space triage

`examples/single_md_file_runbooks/disk-space-triage.md`

A host is nearly full. This single-file runbook finds out what is using the
space without deleting anything. It links to two plain documents, a
glossary beside it and a cleanup policy in a `policies/` folder. That shows
how runbooks can point at supporting docs that runsheets renders but leaves
out of the runbook tree.

## Runbook tasks from local .loki files

`examples/single_md_file_runbooks/runbooks_with_scripts/asgard-tasks.md`

Each block is a one-line call to an [asgard](asgard.md) task defined in
`.loki` files beside the runbook. Runbook inputs reach the tasks as
environment variables, and `expect` blocks with `{{any}}` wildcards check
output from tasks that run in parallel. Requires `gem install asgard`.

## Monthly PostgreSQL maintenance

`examples/single_md_file_runbooks/db-maintenance.md`

A monthly vacuum and reindex routine, written mostly in `sql` blocks run
through `psql` using the runbook's `interpreters` mapping. The database
password is a secret input: it reaches `psql` but never the run record. It
needs a
PostgreSQL database to run against, but it reads well as a model of a
routine maintenance runbook.

## Staging infrastructure teardown

`examples/directory_based_runbooks/staging-teardown`

A realistic AWS teardown with snapshots, pipeline stops, ECS drains and a
stack delete. It shows what front matter like `blast_radius` and
`escalation` is for, and how `expect` blocks and a `destructive` step guard
a procedure that can't be undone. **Don't run it.** Load it to see the warnings
and the structure:

```bash
runsheets --check examples/directory_based_runbooks/staging-teardown
```

## Where are they?

From a checkout, they're in `examples/`. From an installed gem:

```bash
cd "$(gem contents runsheets | grep 'examples/directory_based_runbooks/hello/runbook.md' | xargs dirname)/../.."
```

Next: [write your own](runbooks/index.md), or scaffold one with
`runsheets --init path/to/new-runbook`.
