# Runs and Runsheets

## The engineer's notebook

An engineer working through a procedure keeps a notebook: what they did,
when, what they saw, and what they made of it. When something goes wrong
later, the notebook says what happened instead of what someone remembers.

A run is that notebook, kept for you. While it is active, runsheets writes
down:

- the inputs the run started with (secret values are never written);
- every block executed: the exact command, its full output, exit status,
  start time and duration;
- every terminal block you confirmed you ran yourself, with your note;
- every step you marked done or skipped, with your note;
- how the run ended: `completed` or `abandoned`.

The pages it writes are the **runsheet**: `run.json` for tools and `run.md`
for people, in a directory of their own under the runs directory. A run
never changes the runbook. See
[The Run Record](../running/run-record.md) for the layout.

## A run is a record, not a sequence

Nothing executes without an active run. Until one is started, **Run**,
**Start** and **I ran this** are greyed out; hover one to see why. Every
execution has to be written somewhere, and starting a run opens the
notebook to write it in.

A run does not make you do the steps in order, or do all of them. With a
run active you can:

- open any step, in any order, and run just the block you want;
- run a block as many times as you like. Each execution is recorded;
- leave the other steps alone. Marking steps done or skipped is optional;
- click **Abandon** when you are done with a partial run. The record keeps
  exactly what was run, under the status `abandoned`.

So, to run a single step, start a run from the landing page, go to that
step, and click **Run**. If the step is a `verify` step, **Verify only**
starts a verification run that is limited to the checks.

## One notebook open at a time

A `runsheets` process holds at most one active run. Starting a second run
while one is active is refused; finish or abandon the first. See
[One run at a time](../running/index.md#one-run-at-a-time).
