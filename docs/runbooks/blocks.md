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
| ```` ```bash destructive ```` | <span class="kind destructive">destructive</span> | Run button behind a typed confirmation. Implies `run`. The step shows the blast-radius banner. |
| ```` ```ruby run ```` | <span class="kind run">run</span> | Same as `bash run`, executed with `ruby` or the runbook's `interpreters.ruby`. |
| ```` ```bash terminal ```` | <span class="kind terminal">terminal</span> | No Run button. Labelled "run this in your own terminal". For anything interactive: `read -s`, an SSO login that opens a browser, an interactive `psql` session. |
| ```` ```text expect ```` | <span class="kind expect">expect</span> | Never executed. Labelled "expected output". A visual hint for the operator; it does not gate pass or fail. |
| ```` ```bash background ```` | <span class="kind background">background</span> | Reserved for long-running processes such as a tunnel, with Start and Stop buttons. Recognised but not executable yet. |

Flags are additive where it makes sense: `bash run destructive` and
`bash destructive` are the same thing.

## Which languages execute

Only languages with an interpreter can execute. The defaults are `bash`,
`sh`, `zsh` and `ruby`. A block in any other language that asks for `run`
renders with the warning "sql blocks cannot execute; displayed only" and no
Run button, so a mistake is visible rather than silent.

### Interpreters

The runbook's front matter can add or override entries:

```yaml
interpreters:
  ruby: bin/rails runner -
  sql: psql "$DATABASE_URL" -f
  python: python3
```

When a block executes, its code is written to a temporary file in the run
directory and the interpreter command is run with that path appended. With
the map above a `ruby run` block becomes:

```text
bin/rails runner - <run-dir>/blocks/020-x-1.1.cmd
```

The command is split with `Shellwords`, so quoting works as it would in a
shell, but there is no shell: `$DATABASE_URL` in the example above is passed
literally to `psql`, which is fine because `psql` reads it from the
environment itself. If you need shell expansion in the interpreter command,
go through `bash -c`.

Because every block is a fresh process, a mapping like `bin/rails runner -`
boots Rails for every Ruby block. That is the right trade for correctness in
a runbook; keep Ruby blocks few and meaningful.

## Rules

- **Unknown flags are an authoring error.** They render with a visible
  warning in the block's toolbar and are listed by `runsheet --check`. They
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
