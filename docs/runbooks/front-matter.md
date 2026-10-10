# Front Matter Reference

Front matter is a YAML mapping between `---` lines at the very top of a
file. It is parsed with `YAML.safe_load`, so only plain scalars, lists,
mappings, dates and times are allowed. A document that is not a mapping, or
that is not valid YAML, stops the runbook from loading with a clear error.

## `runbook.md`

```yaml
---
title: Staging Infrastructure Teardown and Rebuild
when_to_use: >
  The deployed stacks cannot be updated in place and an in-place deploy
  fails deterministically.
prerequisites:
  - AWSAdministratorAccess in the staging account
  - The staging branch is ready to fast-forward
blast_radius: >
  Destroys the staging database, container images, and DNS. Irreversible
  once step 050 starts.
escalation: Stop and contact the platform owner if any stack delete fails twice.
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
```

| Key | Type | Default | Used for |
| --- | --- | --- | --- |
| `title` | string | required | Page titles, the header, the run record. A `runbook.md`, or a single-file runbook, without one is not a runbook: it does not load, and in a library it is a plain document. |
| `when_to_use` | string | none | Landing page metadata table. |
| `prerequisites` | list of strings | `[]` | Landing page metadata table. |
| `blast_radius` | string | none | Landing page table, and the red banner on every destructive step. Its presence marks the whole runbook destructive. |
| `escalation` | string | none | Landing page table and the destructive banner. |
| `tags` | list of strings | `[]` | Badges on the landing page. |
| `inputs` | list of mappings | `[]` | The start-run form. See [Inputs and Secrets](inputs.md). |
| `interpreters` | mapping of language to command | see below | How executable blocks of each language are run. See [Executable Blocks](blocks.md#interpreters). |

### `inputs` entries

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `name` | string | required | Must be a valid environment variable name (`/\A[A-Za-z_][A-Za-z0-9_]*\z/`); anything else is an authoring warning. |
| `prompt` | string | the name | Label on the form. |
| `default` | string | none | Pre-fills the form, after the process environment. |
| `secret` | boolean | `false` | Masks the field and keeps the value out of the run record. |

### `interpreters` entries

Keys are language names as they appear in fence info strings. Values are
shell-style command strings, split with `Shellwords`, to which the path of a
temporary file holding the block's code is appended.

```yaml
interpreters:
  ruby: bin/rails runner -
  sql: psql "$DATABASE_URL" -f
```

The defaults are:

```yaml
bash: bash
sh: sh
zsh: zsh
ruby: ruby
```

A language that is not in the map, default or declared, cannot execute even
if a block asks for `run`; the block renders with a warning instead.

## Step files

```yaml
---
title: Drain the ECS services
kind: automated          # automated | manual | verify
destructive: false
timeout: 600             # seconds, for executable blocks in this step
cwd: .                   # working directory, relative to the runbook
---
```

| Key | Type | Default | Used for |
| --- | --- | --- | --- |
| `title` | string | first `# Heading`, else the slug | Page title, sidebar, step list, breadcrumb. |
| `kind` | `automated`, `manual` or `verify` | `automated` if the body has an executable block, else `manual` | Badge on the step. Anything else is a warning. An `automated` step with no executable block is a warning. |
| `destructive` | boolean | `false` | Marks the step destructive even if no block is. A step is also destructive when any of its blocks carries the `destructive` flag. Destructive steps show the blast-radius banner. |
| `timeout` | number of seconds | `600` | Bounds every execution of a block in this step. Must be positive. |
| `cwd` | path | the runbook directory | Working directory for executed blocks, resolved relative to the runbook directory. |

### What `kind` means

- **`automated`**: the body contains at least one executable block. The
  step is complete when the operator has run what needs running and marks
  it done.
- **`manual`**: no executable blocks are expected. The body is an
  instruction. The step is complete when the operator marks it done,
  optionally with a note.
- **`verify`**: a read-only check. Runs in its place during the procedure
  and also standalone: a verification run started from the landing page
  executes only verify steps and `verify.md`, and the **Checks** page shows
  them all together with a **Run all** button.

`verify.md` and `rollback.md` take the same keys. `verify.md` is usually
`kind: verify`.

## Dates and times

YAML parses unquoted `2026-09-12` as a date and `2026-09-12 10:00:00` as a
time. Both are permitted. Quote the value if you want it kept as text.
