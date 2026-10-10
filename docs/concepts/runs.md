# Sessions, Runs and Runsheets

## The engineer's notebook

An engineer working through a procedure keeps a notebook: what they did,
when, what they saw, and what they made of it. When something goes wrong
later, the notebook says what happened instead of what someone remembers.

A **session** is that notebook, kept for you. It is everything between
`runsheets` starting and stopping. It belongs to one engineer, and it
opens with a note saying why it was started. While it lasts, runsheets
writes down:

- who started it, on which host, and why;
- every note the engineer adds along the way, with its time;
- each runbook selected, and the inputs its run was given (secret values
  are never written), and every later change to them;
- every block executed: the exact command, its full output, exit status,
  start time and duration;
- every terminal block you confirmed you ran yourself, with your note;
- every step you marked done or skipped, with your note;
- how each run ended: `completed`, `partial` or `opened`.

The session keeps `session.json` and a `session.log` that is appended as
things happen. See [The Run Record](../running/run-record.md) for the
layout.

## A run is one runbook's part of the session

Selecting a runbook establishes that runbook's **run**: its inputs, its
executions, its step marks. The pages a run writes are the **runsheet**:
`run.json` for tools and `run.md` for people, in a directory of their own
under the runbook's slug, named by the session id. A run never changes the
runbook.

A session can hold many runs. Switching to another runbook finishes
nothing: every run stays open, background processes keep running, and
selecting a runbook again later returns to the run it already has. There
is one run per runbook per session.

## A run is a record, not a sequence

Nothing executes without a run. Until the runbook on screen has one,
**Run**, **Start** and **I ran this** are greyed out; hover one to see
why. Every execution has to be written somewhere, and selecting the
runbook opens its pages of the notebook.

A run does not make you do the steps in order, or do all of them. With a
run open you can:

- open any step, in any order, and run just the block you want;
- run a block as many times as you like. Each execution is recorded;
- leave the other steps alone. Marking steps done or skipped is optional;
- go to the **Checks** page and run only the verify steps and `verify.md`;
- switch to another runbook and come back.

So, to run a single step, select the runbook, go to that step, and click
**Run**.

There is no button that finishes or abandons a run. Ending the session
closes every run in it, with a status worked out from what was done:

| Status | When |
| --- | --- |
| `completed` | Every numbered step was marked done or skipped. |
| `partial` | Anything was executed, marked or acknowledged, but not every step was marked. |
| `opened` | The runbook was selected and nothing was done. |
| `interrupted` | The `runsheets` process was killed; the next start closes the run. |

The record keeps exactly what was run, whatever the status.

## One session per process

A `runsheets` process holds one session, from the start page to Ctrl-C or
**End session**. To keep two separate notebooks, start two processes on
different ports. See
[One session per process](../running/index.md#one-session-per-process).
