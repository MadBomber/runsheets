# Directory Structure

A runbook is a directory, or a [single file](#single-file-runbooks). The
directory is the primary shape. Its name is the runbook's **slug**, which
names the run record directory and appears in the page header.

```text
staging-teardown/
  runbook.md              front matter + preamble (required)
  steps/
    010-confirm-nothing-to-preserve.md
    020-stop-the-pipeline.md
    030-drain-ecs-services.md
  verify.md               whole-procedure verification (optional)
  rollback.md             what to do when it fails partway (optional)
  assets/                 images, SVG diagrams referenced by the markdown
```

## `runbook.md`

Required. Its front matter carries what the operator needs before the first
step; the body is the **preamble**, rendered on the landing page below the
step list. See [Front Matter Reference](front-matter.md) for every key.

Fenced blocks in the preamble follow the same convention as everywhere else,
so a preamble can carry an executable block. Their ids are prefixed
`runbook-`.

## `steps/`

Each markdown file is one step. Steps are ordered by filename using a
numeric-aware sort: the leading digits are compared as numbers, then the
rest of the name as text. `010-`, `020-`, `030-` with gaps leaves room to
insert a step later without renumbering. A file without a numeric prefix
sorts before the numbered ones (it compares as zero), so give every step a
number.

The **step slug** is the filename without its extension, for example
`020-stop-the-pipeline`. It is used in URLs (`/steps/020-stop-the-pipeline`),
in block ids (`020-stop-the-pipeline-1`), and in the run record. Slugs must
be unique; a duplicate is reported as an authoring warning.

The **step number** shown in the page is the leading digits of the slug, or
the step's position when there are none.

Each step has optional front matter and a body. The body is ordinary
markdown: the instruction, the command, and the "how to tell it worked" line
that every good step carries.

```markdown
---
title: Drain the ECS services
kind: automated
timeout: 600
---

Scale every service in the cluster to zero and wait for the tasks to stop.

```bash run
aws ecs update-service --cluster "$CLUSTER" --service web --desired-count 0
aws ecs wait services-stable --cluster "$CLUSTER" --services web
```

It worked when the wait returns without error and the console shows 0
running tasks.
```

A step's title comes from its front matter, else from the first `# Heading`
in the body, else from the slug with its number stripped and dashes turned
into spaces.

## `verify.md` and `rollback.md`

Both optional, both ordinary step documents with front matter and a body.
They are not numbered steps and never appear in the prev/next sequence, but
they are listed in the sidebar under **Also** and are served at
`/steps/verify` and `/steps/rollback`.

`verify.md` holds whole-procedure checks. Its executable blocks run like any
other during a run, and a **verification run** started from the landing
page executes only `verify.md` and verify-kind steps, all gathered on the
**Checks** page.

`rollback.md` additionally renders inside a collapsible **Rollback** panel in
the sidebar of every step page, so it is one click away when something goes
wrong and never needs scrolling to find.

## `assets/`

Not special to runsheets, just the conventional place for images. Any file
in the runbook directory can be referenced with a relative link and is
served through `/files/`:

```markdown
![Topology](../assets/topology.svg)
```

Relative `src` and `href` values are resolved against the markdown file's
own directory, so from `steps/020-x.md` the path above resolves to
`<runbook>/assets/topology.svg`. A path that climbs above the runbook
directory is left untouched and will 404. Hidden entries (names starting
with `.`) are never served, which keeps `.git` and `.env` out of reach.

## Single-file runbooks

An existing runbook is usually one markdown file with a heading per step.
runsheets reads that shape directly: pass the file instead of a directory.

````markdown
---
title: Monthly PostgreSQL maintenance
inputs:
  - name: PGDATABASE
    default: app
interpreters:
  sql: psql -X -v ON_ERROR_STOP=1 -f
---

# Monthly PostgreSQL maintenance

Everything above the first `##` heading is the preamble.

## Check the connection
<!-- kind: verify, timeout: 30 -->

```sql run
select current_database(), current_user;
```

## Vacuum the worst table
<!-- kind: automated, timeout: 1800 -->

```sql run
vacuum (verbose, analyze) events;
```

## Verify

Whole-procedure checks, as verify.md would hold.

## Rollback

What to do when it fails partway, as rollback.md would hold.
````

The rules:

- The front matter is the runbook's, with the same keys as `runbook.md`.
- Every `##` heading starts a step, in document order. Headings inside
  fenced code blocks are ignored. Deeper headings (`###`) belong to the
  step they sit under.
- A step's attributes (`kind`, `timeout`, `destructive`, `cwd`) go in an
  HTML comment on the line after the heading, written as a YAML flow
  mapping: `<!-- kind: verify, timeout: 30 -->`. GitHub and every other
  renderer hide it. A comment that does not start with `key:` is ordinary
  prose and is left alone.
- A section headed **Verify** or **Rollback** (any case) plays the part of
  `verify.md` or `rollback.md`. A section with any other heading can take
  the role with `<!-- role: verify -->`.
- Step slugs are generated from the position and the heading,
  `010-check-the-connection`, `020-vacuum-the-worst-table`, so block ids
  and run record files look exactly as they do for a directory runbook.
  Inserting a heading renumbers the ones after it; the run record keeps
  the slugs that were current when it ran, and the drift view shows the
  difference.
- The slug is the file name without `.md`, or the directory name when the
  file is called `runbook.md`. The working directory for blocks, and the
  root for `/files/`, is the file's directory.

`runsheets --init name.md` writes a starter file in this shape. The bundled
`examples/db-maintenance.md` is a complete one.

## What runsheets does not read

Anything else in the directory is ignored: a `README.md`, a `Gemfile`, a
`scripts/` folder. Steps live only in `steps/`, and only `.md` files there
count.

## Run records live elsewhere

Executing a runbook never writes inside its directory. Run records go to
`~/.local/share/runsheets/runs/<slug>/<timestamp>/` by default; see
[The Run Record](../running/run-record.md). This keeps the runbook directory
clean and committable, and keeps captured output, which may contain
account-scoped data, out of the docs repository.

The one exception is the `last_verified` stamp: after a run that verified
the runbook, the landing page offers to rewrite that single line of
`runbook.md`'s front matter, and does so only when asked.

runsheets re-reads the runbook whenever one of its markdown files changes,
so you can edit steps with the server up and see them on the next page
load.
