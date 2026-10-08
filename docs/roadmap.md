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

- **`background` blocks**: Start and Stop buttons for long-running
  processes such as a tunnel, output streamed, a "running processes" panel,
  everything stopped when the run ends. The executor already writes every
  execution to a log file the page tails, so this is mostly lifecycle.
- **Redaction**: occurrences of secret input values are replaced in captured
  output before it is written. String replacement only; encoded forms are
  out of scope and the docs will say so.
- **Output size**: a cap or a tail-with-marker for very large outputs in
  the page. The file keeps everything.
- **`capture`**: a flag that stores a block's stdout as a named input for
  later blocks, the one escape hatch from "nothing carries over".

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
