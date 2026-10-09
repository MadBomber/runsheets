# Executable Blocks

Real runbooks mix runnable shell, interactive commands, SQL for another
client, expected-output samples, configuration to copy, and destructive
commands. runsheets therefore executes nothing unless a block opts in.

## The convention

The fence's info string is split on whitespace. The first word is the
**language**. Every following word is a **flag**.

````markdown
```bash run
aws sts get-caller-identity
```
````

| Info string | Kind | Behaviour |
| --- | --- | --- |
| ```` ```bash ```` | display | Rendered with syntax highlighting and a Copy button. No Run button. |
| ```` ```bash run ```` | <span class="kind run">run</span> | Run button. Executed with the run's inputs in the environment; stdout, stderr, exit status and timing recorded. |
| ```` ```bash destructive ```` | <span class="kind destructive">destructive</span> | Run button behind a typed confirmation code that the server issues per block. Implies `run`. The step shows the blast-radius banner. |
| ```` ```ruby run ```` | <span class="kind run">run</span> | Same as `bash run`, executed with `ruby` or the runbook's `interpreters.ruby`. |
| ```` ```bash background ```` | <span class="kind background">background</span> | Start and Stop buttons for long-running processes such as a tunnel or a log tail. No timeout. Output streams into the page; the process is listed in the sidebar's **Running** panel on every page; anything still running is stopped when the run ends and recorded as `stopped`, not as a failure. |
| ```` ```bash terminal ```` | <span class="kind terminal">terminal</span> | No Run button. Labelled "run this in your own terminal, then confirm". For anything interactive: `read -s`, an SSO login that opens a browser, an interactive `psql` session. An **I ran this** button records the operator's confirmation, with an optional note. |
| ```` ```text expect ```` | <span class="kind expect">expect</span> | Never executed. Linked to the nearest executable block above it and shown beside that block's real output with a "matches expected" or "differs from expected" hint. A hint for the operator; it does not gate pass or fail. |

Flags are additive where it makes sense: `bash run destructive` and
`bash destructive` are the same thing.

### Expect blocks

An `expect` block illustrates the executable block nearest above it in the
same document, whatever prose sits between them. Its toolbar says which
block it belongs to and links to it. When that block has run, the page
shows the expected text in a pane beside the actual output and compares
them with trailing whitespace ignored. An expect block with no executable
block above it is just displayed.

### Background blocks

A background block is for something that must stay up while later steps
run. It has no timeout, so the step's `timeout` does not apply to it. Stop
it from its own Stop button, from the Running panel on any page, or by
finishing the run. The process group gets `TERM`, then `KILL` two seconds
later if needed, and the execution is recorded with state `stopped`. A
background process that exits on its own is recorded like a `run` block:
`finished` with its exit status, which counts as a failure if non-zero.

## Which languages execute

Only languages with an interpreter can execute. The defaults are `bash`,
`sh`, `zsh` and `ruby`. A block in any other language that asks for `run`
renders with the warning "sql blocks cannot execute; displayed only (map it
under interpreters in the runbook front matter)" and no Run button, so a
mistake is visible rather than silent.

### Interpreters

The runbook's front matter can add or override entries, and a language it
maps executes like any other:

```yaml
interpreters:
  ruby: bin/rails runner -
  sql: psql -X -v ON_ERROR_STOP=1 -f
  python: python3
```

When a block executes, its code is written to a file in the run directory
and the interpreter command is run with that path appended. With the map
above a `ruby run` block becomes:

```text
bin/rails runner - <run-dir>/blocks/020-x-1.1.cmd
```

and a `sql run` block becomes `psql -X -v ON_ERROR_STOP=1 -f <path>`, with
`psql` taking its connection from the `PGHOST`, `PGUSER`, `PGPASSWORD` and
`PGDATABASE` inputs in the environment. `examples/db-maintenance.md` is a
complete runbook built this way.

The command is split with `Shellwords`, so quoting works as it would in a
shell, but there is no shell: a `$VARIABLE` in the interpreter command is
passed literally. If you need expansion there, go through `bash -c` and
take the file as `$0`:

```yaml
interpreters:
  sql: bash -c 'psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -f "$0"'
```

Because every block is a fresh process, a mapping like `bin/rails runner -`
boots Rails for every Ruby block. That is the right trade for correctness in
a runbook; keep Ruby blocks few and meaningful.

## Rules

- **Unknown flags are an authoring error.** They render with a visible
  warning in the block's toolbar and are listed by `runsheets --check`. They
  are never silently ignored.
- **Conflicting flags warn.** `bash background terminal` picks the first and
  warns. `destructive` always wins because it is the safer reading.
- **The block's code is exactly the fence's contents.** Leading indentation
  inside a list item is removed, as GitHub does. Nothing is prepended: no
  `set -e`, no shebang. If you want bash to stop at the first failure, say
  so in the block.
- **Nothing carries over between blocks.** Each execution is a fresh process.
  See [Execution Model](../running/execution.md).

## Block identity

Every fenced block with an info string gets an id of the form
`<step-slug>-<n>`, numbered from 1 in document order, including blocks
nested in lists. Display-only blocks are numbered too, so adding a flag to
an existing block does not renumber its neighbours. Bare fences with no
language at all have no identity.

Ids appear in the page (`data-block`), in the run record, and in the names
of the `.cmd` and `.out` files.

## Blocks in the preamble, verify and rollback

The convention applies to every markdown file runsheets renders. The
preamble in `runbook.md` uses the id prefix `runbook`; `verify.md` and
`rollback.md` use `verify` and `rollback`. A `bash run` block in
`rollback.md` is executable from its page and from the sidebar panel's
link, which is often exactly what you want.

## Why the info string, not a comment or attribute

GitHub, editors and other renderers display `bash run` as `bash`, so a
runbook written for runsheets degrades to a perfectly ordinary markdown
file everywhere else. The flags live in the one place every markdown tool
already preserves.

!!! note "A parser detail you will never see"
    kramdown's GFM parser only accepts a single word as a fence info string;
    "```bash run" is not even a code block to it. runsheets rewrites the info
    string to kramdown's `lang?opts` form before parsing and wraps the block
    afterwards. The markdown on disk is never changed.
