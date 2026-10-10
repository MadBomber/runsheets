# Concepts

runsheets is built on four nouns.

- A **runbook** is documentation for one operational task. It explains what
  to do, why it is necessary, and how to do it. The how is the code in its
  fenced blocks, which runsheets can execute.
- A **session** is everything one engineer does between starting and
  stopping `runsheets`. It works like an engineer's notebook: everything
  done is written down as it happens, along with what came of it, starting
  with a note saying why.
- A **run** is one runbook's part of a session: the inputs it was given,
  what was executed, and the steps marked.
- The **runsheet** is the record a run leaves behind: its pages of the
  notebook.

The runbook says what should happen. The runsheet says what did happen.

<div class="grid cards" markdown>

- **[Runbooks and Documents](runbooks.md)**

    What a runbook holds, its two shapes, the front matter that makes a
    markdown file a runbook, and plain documents a runbook links to.

- **[Sessions, Runs and Runsheets](runs.md)**

    The engineer's notebook: why nothing executes without a run, why a run
    does not make you follow the steps in order, and how ending the session
    closes every run.

</div>
