# Getting Started

This page installs runsheets, runs the bundled example runbook, and walks
through one complete run so the pieces are familiar before you write a
runbook of your own.

## Requirements

- Ruby 3.4 or newer.
- `bash` on the `PATH`. `ruby` is used for Ruby blocks, so it is already
  there.
- A browser on the same machine. The server binds to loopback.

## Install

=== "RubyGems"

    ```bash
    gem install runsheets
    ```

=== "From source"

    ```bash
    git clone https://github.com/MadBomber/runsheets
    cd runsheets
    bundle install
    bundle exec exe/runsheet --help
    ```

Check it is on the path:

```bash
runsheet --version
```

## Run the example

The gem ships with `examples/hello`, a runbook that exercises every block
kind without touching anything on your machine. If you installed from
RubyGems, find it with:

```bash
cd "$(gem contents runsheets | grep 'examples/hello/runbook.md' | xargs dirname)"
```

Then serve it:

```bash
runsheet --open .
```

You will see:

```text
runsheet 0.1.0
Runbook: Hello, runsheets (/path/to/examples/hello)
Runs:    /Users/you/.local/share/runsheets/runs
Open http://127.0.0.1:4567/ in your browser
Press Ctrl-C to stop
```

`--open` launches your default browser. Without it, open the printed URL
yourself.

## Walk through a run

### 1. The landing page

The landing page shows what the authoring guidance says every runbook needs
before the first step: when to use it, prerequisites, the blast radius,
escalation, and the date it was last verified. Below that is the **Start a
run** panel with one field per declared input, pre-filled from defaults and
your environment.

Nothing can be executed yet. Step pages are readable, and blocks can be
copied, but the Run buttons are inert until a run exists. That is
deliberate: every execution belongs to a run record.

### 2. Start a run

Leave `NAME` as `world` or type your own, then click **Start run**. Two
things happen:

- A run directory is created, named by the start time, under the runs
  directory printed at startup.
- You are redirected to the first step.

The header now shows a green pill with the run id. It links to the live run
record.

### 3. Run a block

Step 1, *Say hello*, has one executable block. Click **Run**. The button
disables, the status shows `running`, and output appears below the code as
the process writes it. When it exits, the border turns green for exit status
0 or red for anything else, and the footer line shows the exit status,
duration, finish time, and the name of the log file in the run directory.

Click **Run** again if you like. Both executions are recorded, with separate
`.cmd` and `.out` files.

The second block on that page is marked `expect`. It shows what the output
should look like and is never executed. The third has no flag at all: it is
the same command, display only.

### 4. Mark the step done

At the bottom of every numbered step is a **Step status** panel. Type a note
if there is something worth recording ("saw the greeting, moved on"), then
click **Mark done and continue**. The acknowledgement goes into the record
with a timestamp and you land on the next step. **Skip** records a skip
instead.

The sidebar marks each step: `✓` done, `↷` skipped, `•` ran with no
failures, `✗` a block failed, `·` untouched.

### 5. See a failure and a timeout

Step 4, *Exercise a failure*, is marked destructive in its front matter even
though it is harmless, so you can see the confirmation flow. Clicking **Run
(destructive)** asks you to type a short random word first.

The first block exits 3 on purpose. The second sleeps longer than the step's
five second timeout; runsheets sends `TERM` to the whole process group,
waits two seconds, sends `KILL`, and records the execution as `timed_out`.
Nothing is left running.

### 6. Finish the run

Back on the landing page, the **Active run** panel shows how many executions
ran and how many steps are done. **Finish run** marks the record
`completed`; **Abandon run** marks it `abandoned`. Either way the run is
closed and the record is final.

The landing page now lists it under **Previous runs**, with a link to the
rendered transcript.

### 7. Read the record

```text
~/.local/share/runsheets/runs/hello/20261007T173348/
  run.json
  run.md
  blocks/
    010-say-hello-1.1.cmd
    010-say-hello-1.1.out
    040-exercise-failure-2.1.cmd
    040-exercise-failure-2.1.out
```

`run.md` is the transcript: every execution in order with the exact code
that ran, its output and its verdict, interleaved with the step
acknowledgements. `run.json` is the same as data. See
[The Run Record](running/run-record.md) for the schema.

## Check a runbook without serving it

```bash
runsheet --check path/to/runbook
```

Loads the runbook, prints every authoring warning (unknown block flags,
automated steps with nothing to run, bad input names), and exits 1 if there
were any. Useful in CI for a repository of runbooks.

## Next

- [Writing Runbooks](runbooks/index.md) to build your own.
- [The Web Page](running/web-ui.md) for everything the page can do.
