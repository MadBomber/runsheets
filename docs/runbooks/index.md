# Writing Runbooks

A runbook is a directory of markdown files, or a single markdown file
whose `##` headings are the steps. runsheets adds three things to ordinary
markdown:

1. **Front matter** on `runbook.md` and on each step, carrying the metadata
   an operator needs before touching anything.
2. **A fenced block convention**: the info string's first word is the
   language, any following words are flags, and a block with no flag is
   display only.
3. **Inputs**, declared once and exported as environment variables to every
   executed block.

Everything else is markdown you already know how to write, and the files
remain readable on GitHub or in any editor.

<div class="grid cards" markdown>

- **[Directory Structure](structure.md)**

    `runbook.md`, `steps/`, `verify.md`, `rollback.md`, `assets/`, and how
    steps are ordered and named.

- **[Front Matter Reference](front-matter.md)**

    Every key on the runbook and on a step, with defaults and validation.

- **[Executable Blocks](blocks.md)**

    `run`, `destructive`, `terminal`, `expect`, `background`, which languages
    execute, and the `interpreters` map.

- **[Inputs and Secrets](inputs.md)**

    Declaring inputs, where values come from, secrets, and the variables
    runsheets sets for every block.

- **[Authoring Guide](authoring.md)**

    What makes a good step, converting an existing runbook, and checking
    your work.

</div>

## The smallest runbook

```text
hello/
  runbook.md
  steps/
    010-say-hello.md
```

`runbook.md`:

```markdown
---
title: Hello
---
A one-step runbook.
```

`steps/010-say-hello.md`:

````markdown
---
title: Say hello
---
```bash run
echo "hello from $(hostname)"
```
````

Serve it with `runsheets hello`.
