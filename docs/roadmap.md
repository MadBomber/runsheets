# Roadmap

The plan that runsheets is built from lives in the repository as
`PLAN.md`, with a discussion log. This page is the short version.

## Milestone 1: render and run

Done. Load a runbook directory, render landing and step pages, execute
`bash` and `ruby` blocks with output, exit status and timing, write the run
record. Manual acknowledgements, destructive confirmation, `terminal` and
`expect` labelling, inputs with secrets, the rollback sidebar, run history,
`--check`, and the security controls all landed here too, because they were
cheap once the pieces existed.

## Milestone 2: the full block set

Done.

- **`background` blocks**: Start and Stop buttons, no timeout, output
  streamed, a **Running** panel in the sidebar on every page, everything
  still running stopped when the run ends and recorded as `stopped`.
- **`terminal` blocks**: an **I ran this** button records the operator's
  confirmation, with an optional note, as an `ack` event.
- **Destructive confirmation moved server-side**: the first execute request
  gets a four-character code back (HTTP 428); the block runs only when the
  code is typed back. The record notes that the execution was confirmed.
- **`expect` panels**: an expect block is linked to the executable block
  above it and shown beside that block's real output with a matches/differs
  hint.
- **Redaction**: secret input values are replaced in captured output before
  it reaches the `.out` file, even when a secret is split across two writes.
  String replacement only; encoded forms are not caught and
  [Inputs and Secrets](runbooks/inputs.md) says so.
- **Output size**: the page shows the last 256 KB with a marker when there
  is more. The file keeps everything.

Deferred from the original list: **`capture`**, a flag that stores a block's
stdout as a named input for later blocks. It needs a syntax for the name
and a real runbook to prove it; see the plan's open questions.

## Milestone 3: verification and history

- `verify` steps and `verify.md` runnable standalone from the landing page,
  outside a run.
- **`last_verified` write-back**: finishing a run with every step done
  offers to stamp the date into `runbook.md`. The only file the tool will
  ever modify in a runbook, by targeted line replacement, only on request.
- Richer run history on the landing page: duration, which step it stopped
  at, diffs of the `.cmd` files against the current runbook.

## Milestone 4: packaging

- A README-sized sample beyond `hello`, converted from a real runbook.
- Single-file runbooks: one markdown file whose `##` headings are the steps,
  so existing docs can be used without restructuring. The model is already
  independent of the source shape.
- SQL blocks through a configured client, which the `interpreters` map can
  already express; needs a real runbook to prove the convention.

## Open questions

- **Vocabulary.** Whether the document is a "runbook" and only the recorded
  run is the "runsheet" (closer to the theatre meaning, and it keeps the
  record in the name), or whether "runsheet" is used throughout. The split
  is leaning.
- **Persistent shell per run.** Rejected for milestone 1 in favour of a
  fresh process per block. If `capture` turns out not to be enough, this
  comes back.

## Not planned

- Multi-user or remote operation. See [Security Posture](reference/security.md).
- Running inside a deployed application. The blocks are shell against the
  operator's environment; none of it exists in an app process.
- Enforcing step order. The record makes skipping visible; that is enough.
