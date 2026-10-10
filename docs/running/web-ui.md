# The Web Page

Every page has the same frame: a sticky header, a sidebar, the content, and
a footer with the keyboard shortcuts. The start page and the page shown
after the session ends are the exceptions; they stand alone.

## Starting the session

Everything from `runsheets` starting to it stopping is one session (see
[Sessions, Runs and Runsheets](../concepts/runs.md)). Unless the engineer
and the reason were given on the command line, the browser opens on the
**Start a session** page at `/session/new`, which asks:

- **Who are you?** Pre-filled from the configured engineer, else
  `git config user.name`, else `$USER`. The name is the engineer's own
  statement; nothing authenticates it.
- **Why are you starting this session?** The session's first note,
  timestamped like every later one. It is nothing more than that.

Both are required; submitting either blank shows the page again with a
message. Until the session has started, every page redirects here. Once it
has, this page redirects to the session page: a process holds one session.

With both given by `--engineer` and `--why` (or `RUNSHEETS_ENGINEER` and
`RUNSHEETS_WHY`, or `engineer:` and `why:` in a config file), the session
starts when the server does and this page is never shown. See
[Command Line](cli.md#the-session).

## Header

- **Brand and slug** on the left link home.
- **Breadcrumb**: runbook title, then the current step, or **Session** on
  the session page.
- **Prev / Next** move through the numbered steps. Disabled at the ends and
  on pages that are not steps.
- **Session pill**: the engineer, how long the session has been open, and
  how many runbooks have a run in it, as in `Pat · 12m 05s · 2 runbooks`.
  It links to the [session page](#session-page).
- **Runbooks** appears when the server was started on a directory of
  runbooks, and leads back to the library.
- **Search runbooks**, a search box on every page; see [Search](#search).

## Sidebar

- **Running**: every process still running anywhere in the session, with
  the block id (linking to its step), the runbook's slug when it is not
  the runbook on screen (linking to it in the library), the pid, and a
  **Stop** button that works for any of them. The panel appears only while
  something is running and keeps itself current.
- **Steps**: every numbered step with its number, title and status mark.
  The current step is highlighted.
- **Also**: **Checks**, `rollback` and any other extra documents, and,
  once the runbook on screen has a run, its runsheet.
- **Rollback**: on step pages, a collapsible panel containing the whole
  rendered `rollback.md`.
- **On this page**: an outline of the current page's headings.

The sidebar toggles with the menu button or ++s++; the choice is remembered
in the browser.

### Status marks

| Mark | Meaning |
| --- | --- |
| `·` | Nothing has happened on this step in this runbook's run. |
| `•` | At least one block ran or was confirmed, and none failed. A stopped background block counts as ran. |
| `✗` | A block in this step failed, timed out, or could not start, and the step has not been marked. |
| `✓` | Marked done by the operator. |
| `↷` | Marked skipped by the operator. |

A manual mark always wins over the execution-derived mark, so a step whose
block failed but was then marked done shows `✓`. The failure is still in
the record.

## Choosing a runbook

Started on a directory of runbooks (`runsheets ops/runbooks`), the session
opens on the library at `/library`. A markdown file whose front matter
has a `title` is a single-file runbook, every directory holding `runbook.md`
is a runbook directory, and every other directory is a folder, searched the
same way to any depth. Markdown files without that front matter are plain
documents: they stay out of the tree, and a runbook can link to them.
Folders that hold no runbooks are left out, as are hidden entries. Until a
runbook is selected, the library, the session page, search, and the
documents and files runbooks link to work; every other page redirects to
the library.

The page has two panes:

- **The tree**, on the left. Folders fold and unfold; runbooks show their
  title and step count. A runbook that does not load is struck through
  with a red `!`; the runbook on screen carries a green dot. The filter box
  at the top (++slash++ focuses it) narrows the tree to runbooks whose
  title, file name, path or tags contain the text, opening every folder
  that still has a match. The tree never descends into a runbook: its
  `steps/` and other files are not part of the library.
- **The main pane**, on the right, shows what is selected in the tree.
  A folder shows its `README.md` (rendered, if it has one) and a card for
  each folder and runbook it holds directly; the root folder is what
  `/library` shows. A runbook shows its `when_to_use` text beside its
  action, then its prerequisites, blast radius and escalation, its inputs
  with their defaults, its steps with kind badges, its previous runs, and
  its preamble. The URL is the runbook's path in the library
  (`/library/platform/database/backup`), so it can be bookmarked. Before
  any runbook is selected, the session page sits in the main pane beside
  the tree.

What a runbook offers depends on where it stands in the session:

| State | Badge | Runbook pane | Card |
| --- | --- | --- | --- |
| No run yet | | The inputs form and **Start run** | **Start run** for a runbook without inputs; **Open**, leading to the pane, for one with inputs |
| Run open in this session | `run open` | **Return to its run** | **Return to its run** |
| On screen now | `open now` | **Continue** | **Continue** |
| Does not load | `does not load` | The load error | nothing |

**Start run** establishes the runbook's run with the inputs in the form and
goes to its landing page. **Return to its run** goes back to the run it
already has; inputs are not asked for again. Selecting a runbook never
finishes the run of the one you were on: every run in the session stays
open, and every background process keeps running. In the runbook pane,
++o++ presses its button.

From a runbook's pages, the header breadcrumbs lead back through the
folders to the library, and the **Runbooks** button (++r++) goes straight
to it. A runbook's slug is its path inside the library
(`platform/database/backup`), so two runbooks named alike in different
folders keep separate run records. Runbooks added, removed or edited while
the server is up appear on the next visit to the library.

## Landing page

In order:

1. **Title, step count, tags.** A red `destructive` badge appears when the
   runbook declares a blast radius or any step is destructive.
2. **Authoring warnings**, if any, in an amber banner. Fix them in the
   markdown; the page updates on reload.
3. **Metadata table**: when to use, prerequisites, blast radius,
   escalation.
4. The **Start a run** panel, or the **Run open** panel.
5. **Step list** with kind badges, destructive badges, the number of
   executable blocks, and status marks.
6. **Previous runs**, newest first. Each row shows the run id (linking to
   the transcript), the status (`running`, `completed`, `partial`,
   `opened`, `interrupted`, or `abandoned` in records from before
   sessions), start time and duration, execution and failure counts, and
   steps done with the step it stopped at. A record of a verification run,
   from before sessions, carries a `verify` badge and shows checks run and
   how many are still failing.
7. The **preamble** from `runbook.md`.

### Starting a run

On a server started on one runbook, the landing page carries the **Start a
run** panel until the runbook has a run. (In a library the same form is in
the runbook pane.) It has one field per declared input; secret inputs are
password fields. Each field is pre-filled with what the run would get if
left alone: a non-secret value given for the same name earlier in the
session, else the environment, else the default (see
[Inputs and Secrets](../runbooks/inputs.md#where-values-come-from)).
Submitting it creates the run directory and returns to the landing page,
now showing the Run open panel.

No block executes until the runbook on screen has a run, not even one on a
step page opened directly: until then its Run button is disabled, and
hovering it says "Start a run to execute blocks". Starting a run does not
fix the order: any step can be opened and run on its own, and the rest
left untouched. See
[A run is a record, not a sequence](../concepts/runs.md#a-run-is-a-record-not-a-sequence).

### The Run open panel

Shows the run id, when it was opened, its progress (executions, and steps
done out of the total), a link to the runsheet, and the inputs (values for
plain inputs, `NAME=•••` for a secret that is set). Then:

- **Work through the steps**, to step 1.
- **Go to checks (N)**, when the runbook has verify steps or a
  `verify.md`.
- **Change inputs**, a folded form for a runbook with inputs. Plain fields
  hold the current values. Secret fields are always empty, and a secret
  left empty keeps its current value, so a secret never comes back to the
  page. Blocks run after the change see the new values; the change is
  recorded in the run as an `inputs` event and written to the session log.

There is no Finish or Abandon. The run stays open until the session ends.

### The Checks page

**Checks**, in the sidebar, gathers every verify step and `verify.md` in
order on one page. With a run open, **Run all** executes each `run` block
on the page one after another and reports how many passed. The checks run
inside the runbook's run like any other block. Without a run the page is
read-only.


## Step pages

In order:

1. **Number and title**, with badges for the kind, `destructive`, and the
   timeout when the step has executable blocks.
2. **Authoring warnings** for this step, if any.
3. **Blast radius banner** on destructive steps, in red, with the escalation
   contact. If the runbook declares no blast radius the banner says only
   that the step is destructive.
4. An **info banner** when the runbook has no run yet and the step has
   executable blocks: blocks can be read and copied but not run, with a
   link to the landing page to start the run.
5. **The body**, rendered.
6. **Step status** panel (once the runbook has a run): a note field and two buttons,
   **Mark done and continue** and **Skip**. Both record an event and move
   to the next step, or home after the last one. On a `manual` step the
   panel is headed **Acknowledge this step** and the button reads **I have
   done this, continue**; it is the same event.
7. **Prev / Next** navigation.

### Blocks

Every fenced block with a language has a toolbar:

- a **badge** with the language and flags,
- any **warnings** for the block,
- a **note** for `terminal`, `expect` and `background` blocks; an expect
  block's note links to the block it illustrates,
- **Copy**, which puts the code on the clipboard,
- **Run** or **Run (destructive)** on `run` and `destructive` blocks,
  **Start** and **Stop** on `background` blocks, **I ran this** on
  `terminal` blocks,
- a **status** area.

Clicking Run posts to the server and starts polling. The status shows
`running` with the elapsed time, and the output area below the code fills
in as the process writes, scrolled to the bottom. When the process ends the
block's border turns green (exit 0), amber (stopped) or red (anything
else), the status shows `ok`, `exit N`, `timed out`, `stopped` or
`failed to start`, and the footer shows the exit status, duration, finish
time and the name of the `.out` file in the run directory. Output longer
than 256 KB is shown from its tail with a marker on the first line.

**Run (destructive)** asks the server to run the block; the server answers
with a four-character code instead, the page shows it in a prompt, and the
block runs only when you type the code back. The code is per block and is
retired once used. It is a speed bump against a reflexive click, not a
security control; the real guard is reading the banner above it.

**Start** on a background block is Run without a timeout. While it runs
the Stop button is shown and the process is listed in the sidebar's
Running panel. **Stop** ends the process group; the status becomes
`stopped`.

**I ran this** on a terminal block opens a prompt for an optional note and
records the confirmation. The block's border turns green, the status reads
`confirmed`, and the time and note are shown in the footer. It can be
confirmed again; the record keeps every confirmation.

### Expected output

When an executable block is followed by an `expect` block, the real output
and the expected text are shown side by side once the block has run, and
the footer says `matches expected` or `differs from expected` (trailing
whitespace ignored). The expect block itself stays where the author put it.

A block can be run again at any time while the session lasts. Each execution gets its
own files and its own entry in the record. The page shows the most recent
one.

### Reloading

Nothing re-runs on reload. The page restores the last execution of each
block from the run record, including output, resumes polling if one is
still running, and restores terminal confirmations.

## Runsheet page

The record of a run is the *runsheet*; the page and the sidebar call it
that. On disk it is `run.json` and `run.md`.

`/run` shows the transcript of the run of the runbook on screen, rendered.
Before that runbook has a run in this session, the same URL shows its most
recent run. `/runs/<id>` shows any previous run of the runbook on screen. The transcript is `run.md` from the run directory; see
[The Run Record](run-record.md).

Above the transcript of a closed run, a **Runbook changed since this
run** panel appears when any block that ran now reads differently in the
runbook, with a line diff from what ran to what is there now, or when a
block is gone. The record itself is never changed; this is the runbook
drifting away from it.

## Session page

`/session`, reached from the session pill, is the notebook so far:

- **The heading**: the session id, the engineer, the host, the start time
  and how long it has been open.
- **Notes**: every note with its time, the reason the session was started
  first. **Add note** appends one; a blank note is refused. Notes are
  written to `session.json` and the session log as they are added.
- **Runs**: each runbook selected in the session, in the order it was
  selected, with the status it would close with if the session ended now
  (`partial so far`), its progress, and **Return to it**, or **On screen**
  for the runbook on screen.
- **End the session**: the **End session** button.
- **Session log**: the last 200 lines of `session.log`, with its path; run
  `tail -f` on it for the rest.

In a library, before any runbook is selected, the session page sits in the
main pane beside the tree.

## Ending the session

**End session** on the session page, or Ctrl-C in the terminal that
started `runsheets`, ends the session. Every run in it is closed with a
status worked out from what was done:

- `completed`: every numbered step was marked done or skipped;
- `partial`: anything was executed, marked or acknowledged, but not every
  step was marked;
- `opened`: the runbook was selected and nothing was done.

Anything still running, in any runbook, is stopped first and recorded as
`stopped`. **End session** then shows a **Session ended** page with each
runbook's status and where the records are, and `runsheets` exits. From
then until it does, every page answers 410 except `GET /session`.

A session whose process was killed cannot close itself. The next time
`runsheets` starts it closes any session still marked running whose process
is gone, and its runs, as `interrupted`, and writes a warning about it to
the new session's log. A session whose process is still alive on this host
belongs to another `runsheets` and is left alone.

## Search

The search box in the header searches the full text of every runbook in
the directory runsheets was started on, or of the one runbook when it was
started on one. It works before any runbook is selected. Press ++f++ to jump
to it.

- **What is searched**: each runbook's title, its front matter prose
  (when to use, prerequisites, blast radius, escalation, tags, input
  names and prompts), its preamble, and every step, `verify.md` and
  `rollback.md`: titles, prose and code alike. Plain markdown documents
  are not searched.
- **How it matches**: case-insensitive. Separate words must all appear
  somewhere in a runbook, not necessarily together; `"a quoted phrase"`
  must appear as written.
- **Results**: one card per matching runbook, best first. A match in the
  title counts most, then the front matter, then step titles, then the
  text. Under each runbook are the documents that matched, each with a
  snippet and the words highlighted.
- **Where results lead**: a step of the runbook on screen goes straight to
  its page. Any other runbook opens in the library with the matching
  step highlighted in its step list; start or return to its run from
  there.

## Keyboard shortcuts

| Key | Action |
| --- | --- |
| ++f++ | Focus the search box |
| ++h++ | Home |
| ++r++ | Runbooks (the library, when started on a directory of runbooks) |
| ++arrow-left++ / ++arrow-right++ | Previous / next step |
| ++s++ | Toggle the sidebar |
| ++escape++ | Leave a text field |

On the library page:

| Key | Action |
| --- | --- |
| ++slash++ | Focus the filter box; ++escape++ clears it |
| ++arrow-down++ / ++arrow-up++ (or ++j++ / ++k++) | Move the cursor through the tree |
| ++arrow-right++ / ++arrow-left++ | Unfold / fold the folder under the cursor |
| ++enter++ | Select the runbook or folder under the cursor |
| ++o++ | Press the selected runbook's button: **Start run**, **Return to its run** or **Continue** |
| ++b++ | Back to the runbook on screen |
| ++s++ | Toggle the tree |

Shortcuts are ignored while typing in a field.

## Errors

A request that cannot be honoured gets a page (or JSON, for the execute and
poll endpoints) with the reason:

| Status | Typical cause |
| --- | --- |
| 403 | Missing session token on a POST, or a `Host` header that is not loopback. |
| 404 | Unknown step, run, execution, file, or runbook slug. |
| 409 | A POST before the session has started, no run for the runbook on screen, block not executable, blank input referenced, unknown execution to stop, acknowledging a block that is not `terminal`, a blank note. |
| 410 | The session has ended. Only `GET /session` still answers. |
| 422 | The start page with a blank name or reason, a step mark with a status other than `done` or `skipped`, or a mark on a document that is not a numbered step. |
| 428 | A destructive block was asked to run without its confirmation code. The page handles this by prompting for the code. |
