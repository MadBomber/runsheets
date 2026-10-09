# The Web Page

Every page has the same frame: a sticky header, a sidebar, the content, and
a footer with the keyboard shortcuts.

## Header

- **Brand and slug** on the left link home.
- **Breadcrumb**: runbook title, then the current step.
- **Prev / Next** move through the numbered steps. Disabled at the ends and
  on pages that are not steps.
- **Run pill**: grey "no active run", or green with the run id when a run is
  active. The green pill links to the live run record.
- **Runbooks** appears when the server was started on a directory of
  runbooks, and leads back to the chooser.

## Sidebar

- **Running**: during a run, every process still running, with the block
  id (linking to its step), elapsed time, pid, and a **Stop** button. The
  panel appears only while something is running and keeps itself current.
- **Steps**: every numbered step with its number, title and status mark.
  The current step is highlighted.
- **Also**: `verify`, `rollback` and, during a run, the run record.
- **Rollback**: on step pages, a collapsible panel containing the whole
  rendered `rollback.md`.
- **On this page**: an outline of the current page's headings.

The sidebar toggles with the menu button or ++s++; the choice is remembered
in the browser.

### Status marks

| Mark | Meaning |
| --- | --- |
| `·` | Nothing has happened on this step in the active run. |
| `•` | At least one block ran or was confirmed, and none failed. A stopped background block counts as ran. |
| `✗` | A block in this step failed, timed out, or could not start, and the step has not been marked. |
| `✓` | Marked done by the operator. |
| `↷` | Marked skipped by the operator. |

A manual mark always wins over the execution-derived mark, so a step whose
block failed but was then marked done shows `✓`. The failure is still in
the record.

## Choosing a runbook

Started on a directory of runbooks (`runsheets ops/runbooks`), the server
opens on the library at `/library`. Every markdown file in the directory
is a single-file runbook, every directory holding `runbook.md` is a runbook
directory, and every other directory is a folder, searched the same way to
any depth. Folders that hold no runbooks are left out, as are hidden
entries. Every other page redirects to the library until a runbook is open.

The page has two panes:

- **The tree**, on the left. Folders fold and unfold; runbooks show their
  title and step count. A runbook that does not load is struck through
  with a red `!`; the runbook open now carries a green dot. The filter box
  at the top (++slash++ focuses it) narrows the tree to runbooks whose
  title, file name, path or tags contain the text, opening every folder
  that still has a match. The tree never descends into a runbook: its
  `steps/` and other files are not part of the library.
- **The main pane**, on the right, shows what is selected in the tree.
  A folder shows its `README.md` (rendered, if it has one) and a card for
  each folder and runbook it holds directly; the root folder is what
  `/library` shows. A runbook shows its `when_to_use` text beside the
  **Open** button, then its prerequisites, blast radius, escalation and
  last-verified date, its inputs with their defaults, its steps with kind
  badges, its previous runs, and its preamble. The URL is the runbook's
  path in the library (`/library/platform/database/backup`), so it can be
  bookmarked.

**Open** serves that runbook and goes to its landing page; the header
breadcrumbs there lead back through the folders to the library, and the
**Runbooks** button (++r++) goes straight to it. A runbook's slug is its
path inside the library (`platform/database/backup`), so two runbooks named
alike in different folders keep separate run records. While a run is active
the Open buttons are disabled and a banner says which runbook holds the run:
finish or abandon it, then switch. Runbooks added, removed or edited while
the server is up appear on the next visit to the library.

## Landing page

In order:

1. **Title, step count, last-verified date, tags.** A red `destructive` badge
   appears when the runbook declares a blast radius or any step is
   destructive.
2. **Authoring warnings**, if any, in an amber banner. Fix them in the
   markdown; the page updates on reload.
3. **Metadata table**: when to use, prerequisites, blast radius,
   escalation, last verified.
4. **Record the verification** offer, after a run that verified the
   runbook (see below).
5. **Start a run** form, or the **Active run** panel.
6. **Step list** with kind badges, destructive badges, the number of
   executable blocks, and status marks.
7. **Previous runs**, newest first. Each row shows the run id (linking to
   the transcript), a `run` or `verify` badge, the verdict (`verified`,
   `completed`, `abandoned` or `running`, plus `stamped` if the run stamped
   the runbook), start time and duration, execution and failure counts,
   and either steps done with the step it stopped at, or checks run and how
   many are still failing.
8. The **preamble** from `runbook.md`.

### Verification runs

Next to **Start run** is **Verify only**, shown when the runbook has verify
steps or a `verify.md`. It starts a run of kind `verify` with the same
inputs and goes to the **Checks** page, which gathers every verify
document in order. **Run all** executes each `run` block on the page one
after another and reports how many passed. During a verification run,
blocks outside the verify documents refuse to execute and their step pages
say so. The record is written like any other run and gets a `-verify`
suffix in its id.

The Checks page is also reachable from the sidebar at any time; without an
active run it is read-only.

### Record the verification

After **Finish** on a full run with every step marked done, or on a
verification that ran at least one check, with no block left in a failed
state (a failure that was re-run successfully does not count), the landing
page offers to stamp the run's date into `runbook.md` as `last_verified`.
**Stamp runbook.md** rewrites that one front-matter line, notes a `stamp`
event in the run record, and reloads the runbook. **Not now** hides the
offer for that run. The offer is not made when the runbook's
`last_verified` is already that date or later.

### Starting a run

The form has one field per declared input, pre-filled from the environment
and the defaults. Secret inputs are password fields. Submitting creates the
run directory and redirects to the first step.

### The active run panel

Shows the run id, start time, counts, the inputs (values for plain inputs,
`NAME=•••` for a secret that is set), and three actions: **Go to first step**, **Finish run** (status `completed`), and
**Abandon run** (status `abandoned`). Finishing writes the final record;
the landing page then lists the run under previous runs.

## Step pages

In order:

1. **Number and title**, with badges for the kind, `destructive`, and the
   timeout when the step has executable blocks.
2. **Authoring warnings** for this step, if any.
3. **Blast radius banner** on destructive steps, in red, with the escalation
   contact. If the runbook declares no blast radius the banner says only
   that the step is destructive.
4. An **info banner** when there is no active run and the step has
   executable blocks: blocks can be read and copied but not run.
5. **The body**, rendered.
6. **Step status** panel (only during a run): a note field and two buttons,
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

A block can be run again while the run is active. Each execution gets its
own files and its own entry in the record. The page shows the most recent
one.

### Reloading

Nothing re-runs on reload. The page restores the last execution of each
block from the run record, including output, resumes polling if one is
still running, and restores terminal confirmations.

## Runsheet page

The record of a run is the *runsheet*; the page, the sidebar and the run
pill call it that. On disk it is still `run.json` and `run.md`.

`/run` shows the active run's transcript, rendered. After the run is
finished the same URL shows the most recent run. `/runs/<id>` shows any
previous run. The transcript is `run.md` from the run directory; see
[The Run Record](run-record.md).

Above the transcript of a finished run, a **Runbook changed since this
run** panel appears when any block that ran now reads differently in the
runbook, with a line diff from what ran to what is there now, or when a
block is gone. The record itself is never changed; this is the runbook
drifting away from it.

## Keyboard shortcuts

| Key | Action |
| --- | --- |
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
| ++o++ | Open the selected runbook |
| ++b++ | Back to the runbook open now |
| ++s++ | Toggle the tree |

Shortcuts are ignored while typing in a field.

## Errors

A request that cannot be honoured gets a page (or JSON, for the execute and
poll endpoints) with the reason:

| Status | Typical cause |
| --- | --- |
| 403 | Missing session token on a POST, or a `Host` header that is not loopback. |
| 404 | Unknown step, run, execution, or file. |
| 409 | No active run, a run already active, block not executable, blank input referenced, unknown execution to stop, acknowledging a block that is not `terminal`. |
| 422 | A step mark with a status other than `done` or `skipped`, a mark on a document that is not a numbered step, or a finish with a status other than `completed` or `abandoned`. |
| 428 | A destructive block was asked to run without its confirmation code. The page handles this by prompting for the code. |
