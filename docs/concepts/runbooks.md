# Runbooks and Documents

## What a runbook is

A runbook is documentation for one specific operational task: rotating a
certificate, tearing down a staging stack, the monthly database
maintenance. It answers three questions.

- **What** to do: the steps, in order, each small enough to do and check
  before moving on.
- **Why** it is necessary: when to use the runbook, what it touches, what
  can go wrong, and who to call when it does. This lives in the front
  matter (`when_to_use`, `prerequisites`, `blast_radius`, `escalation`) and
  in the prose around the steps.
- **How** to do it: the commands. In a runbook these are fenced code
  blocks, and the words after the language mark which ones runsheets may
  execute:

    ````markdown
    ```bash run
    aws ecs update-service --cluster "$CLUSTER" --service web --desired-count 0
    ```
    ````

    A block with no flag is shown for reading and copying, and never runs.
    See [Executable Blocks](../runbooks/blocks.md) for every flag.

Everything else is ordinary markdown. A runbook reads correctly on GitHub
or in any editor; runsheets adds the Run buttons and the record.

## Two shapes

A runbook is either a directory or a single file. Both load into the same
thing, and runsheets treats them alike.

### A directory

```text
staging-teardown/
  runbook.md          front matter (with a title) + preamble
  steps/
    010-confirm-nothing-to-preserve.md
    020-stop-the-pipeline.md
  verify.md           optional
  rollback.md         optional
```

`runbook.md` holds the runbook's YAML front matter and a preamble. Each file
in `steps/` is one step, ordered by its number, with its own optional YAML
front matter (`title`, `kind`, `timeout`, `destructive`, `cwd`). Use this
shape when steps are long, or when several people edit them.

### A single file

```markdown
---
title: Monthly PostgreSQL maintenance
---

Preamble.

## Check the connection
<!-- kind: verify, timeout: 30 -->

...
```

One markdown file: the front matter, a preamble, then one `##` heading per
step. A step's attributes go in an HTML comment on the line after its
heading, since a single file can have only one front matter block. Use
this shape for short runbooks, or to adopt an existing runbook as it is.

[Directory Structure](../runbooks/structure.md) has the details of both.

## What makes a file a runbook

A markdown file is a runbook when it starts with YAML front matter that has
a `title`:

```yaml
---
title: Monthly PostgreSQL maintenance
---
```

That applies to `runbook.md` in a runbook directory and to a single-file
runbook. Every other key is optional; see the
[Front Matter Reference](../runbooks/front-matter.md).

A `runbook.md` without a title, or a file passed to `runsheets` without
one, does not load:

```text
runsheets: runbook.md is not a runbook: it needs YAML front matter with a title
```

## Plain documents

A markdown file without that front matter is a plain document, not a
runbook. A document is for background a runbook leans on without being a
step itself: a glossary, an architecture note, the reason a procedure is
the way it is.

- **In a library**, plain documents are left out of the tree, wherever
  they sit in the directory `runsheets` was started on. Only runbooks are
  listed. `README.md` remains the description of its folder.
- **Linked from a runbook**, a plain document opens as a page in a new
  tab, so the runbook stays where you were. Write an ordinary relative
  link:

    ```markdown
    Why we vacuum this table first: see [the bloat notes](docs/bloat.md).
    ```

    The link goes to `/docs/docs/bloat.md`, which renders the file. Every
    block in it is display only and nothing on the page executes; its own
    relative links and images resolve from its folder. A link to one of the
    runbook's own files, such as `steps/020-stop-the-pipeline.md`, opens
    that step's page instead, and a link to another runbook in the library
    opens it in the library; both stay in the same tab. Inside a document
    tab, links to other documents stay in that tab.

Links resolve within the directory `runsheets` was started on, so a
runbook can link to a document anywhere in it. A link that climbs out of
that directory is left as written and does not resolve.

A document becomes a runbook as soon as it gets a front matter `title`. In
a library it joins the tree on the next visit.
