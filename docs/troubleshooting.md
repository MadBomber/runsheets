---
tags:
  - Troubleshooting
  - Command line
  - Configuration
  - Blocks
  - Inputs and secrets
---

# Troubleshooting and FAQ

Answers to the snags a first session tends to hit. Click a question to open
it. Messages are quoted exactly as `runsheets` prints them.

## Starting runsheets

??? question "It says the port is already in use"
    Something else (often another `runsheets`) is listening on the port.
    The command prints one line and exits `1`, before any session starts,
    so nothing is recorded:

    ```text
    runsheets: port 4567 on 127.0.0.1 is already in use; pick another with --port
    ```

    To find a `runsheets` that is still running, look for its process. The
    web server names it `puma <version> (tcp://<bind>:<port>) [runsheets]`:

    ```bash
    pgrep -lf runsheets
    ```

    Stop it with Ctrl-C in its terminal, or with `pkill -INT -f runsheets`.
    Either way the session ends properly and every run is closed.

    Pick another port for one run with `--port` or `RUNSHEETS_PORT`:

    ```bash
    runsheets -p 4580 ops/runbooks
    RUNSHEETS_PORT=4580 runsheets ops/runbooks
    ```

    To make it stick, put `port: 4580` in `~/.config/runsheets/runsheets.yml`.
    The port must be a whole number from 1 to 65535; anything else is
    refused with a message such as
    `runsheets: port must be a whole number, got "abc"`. The `PORT`
    variable is not read. See [Settings](running/cli.md#settings).

??? question "The browser shows “Open the link from the terminal”"
    The browser does not hold this start's session key. Open the link the
    banner printed, `http://127.0.0.1:4567/?token=…`; the browser keeps the
    key in a cookie until runsheets stops. Every start makes a new key, so
    a tab left open from an earlier start, or a bookmark, shows this page
    until the new link is opened. `--open` opens the right link for you.

??? question "The browser shows “Host not permitted”"
    The server only answers requests whose `Host` header is `localhost`,
    `127.0.0.1`, `::1` or the bind address. A machine name, an alias in
    `/etc/hosts`, or a LAN address in the URL gets a plain-text
    `Host not permitted` (status 403). This is what stops a hostile web
    page from reaching the server through DNS rebinding. Use the link the
    banner prints, `http://127.0.0.1:4567/?token=…`.

    To reach the server from another address, bind to it with `--bind`
    (or `RUNSHEETS_BIND`). Any address that is not loopback prints a
    warning to stderr before the banner:

    ```text
    runsheets: warning: binding to 0.0.0.0, which is not a loopback address.
    Anyone who can reach this address and guess the session token can run blocks as you.
    The Host header check is off for a wildcard bind.
    ```

    A specific address ends with
    `Only requests with this address in the Host header are accepted.`
    instead. Binding off loopback exposes shell execution on your machine
    to whoever can reach that address; read
    [About `--bind`](running/cli.md#about-bind) and
    [Host authorization](reference/security.md#host-authorization) first.

??? question "Which settings are in force, and where did they come from?"
    `--dump` prints the settings after every layer has been applied, in
    the shape of a config file, and exits:

    ```bash
    runsheets --dump
    runsheets --dump -p 4580 ops/runbooks    # what these options would give
    ```

    The layers, highest first: command-line options, `RUNSHEETS_*`
    environment variables, the project config `./config/runsheets.yml` (or
    the file `--config` or `RUNSHEETS_CONFIG` names), the user config
    `~/.config/runsheets/runsheets.yml`, and the bundled defaults. When the
    server starts, the `Config:` line of its banner lists the config files
    that were read, or `none (defaults)`. A value you did not expect usually
    comes from a config file you forgot about, or from a `RUNSHEETS_*`
    variable left set in the shell.

    `--dump` leaves out `dump`, `check`, `init` and `why`, so its output can
    be saved as a config file. See [Settings](running/cli.md#settings) and
    [Saving settings](running/cli.md#saving-settings).

??? question "How do I check a runbook without serving it?"
    ```bash
    runsheets --check ops/runbooks/db-refresh
    runsheets --check ops/runbooks          # every runbook in a library
    ```

    Warnings go to stderr prefixed `runsheets: warning:`, then one summary
    line per runbook goes to stdout:

    ```text
    Hello, runsheets: 6 steps, 0 warnings
    ```

    A runbook in a library that cannot be read is reported as
    `runsheets: error: <slug>: <message>`. The exit status is `1` if anything
    warned or failed to load, else `0`, so `--check` works in CI. See
    [Checking runbooks](running/cli.md#checking-runbooks).

## My runbook

??? question "A markdown file does not show up in the library tree"
    In a directory of runbooks, a markdown file is a runbook only when it
    starts with YAML front matter holding a `title`:

    ```markdown
    ---
    title: Rotate the staging database password
    ---
    ```

    A file without one is a plain document: it stays out of the tree,
    though a runbook can still link to it. A directory is a runbook when it
    holds `runbook.md`, which needs a `title` too. `README.md` is never a
    runbook, hidden files and directories are skipped, and a folder with no
    runbooks anywhere beneath it is left out. The tree rescans when files
    change, so a document given a title joins it without a restart.

    Two runbooks with the same name in one folder (`deploy.md` beside
    `deploy/runbook.md`, or `backup.md` beside a `backup/` folder) are shown
    broken with
    `another runbook or a folder here already has the name deploy; rename one`.

    See [Several runbooks in one directory](runbooks/structure.md#several-runbooks-in-one-directory).

??? question "A single file fails to load with “is not a runbook”"
    Passed directly, a markdown file without a front matter `title` is
    refused, and the command exits `1`:

    ```text
    runsheets: notes.md is not a runbook: it needs YAML front matter with a title
    ```

    A `runbook.md` without a title gives the same message. Add a `title`
    to the front matter. A directory with no runbooks in it at all reports
    `no runbooks in <dir>: expected .md files with a front matter title, or
    directories holding runbook.md`. See
    [Single-file runbooks](runbooks/structure.md#single-file-runbooks) and
    the [Front Matter Reference](runbooks/front-matter.md).

??? question "I edited the runbook. Do I need to restart?"
    No. The runbook on screen is reloaded on the next page when any of its
    markdown files change, and its run carries on. If the edit leaves the
    runbook unable to load, the previous version is kept and the session
    log records `<slug> no longer loads: <message>` at `error`; run
    `runsheets --check` on it to see why. See
    [Reloading](running/web-ui.md#reloading).

??? question "Run says “changed on disk since this page loaded”"
    The block's file was edited after the page was shown, and the block at
    that position is no longer the one on screen. runsheets refuses rather
    than run something you did not see. Reload the page and click Run on
    the block as it now reads.

## Running blocks

??? question "A block has no Run button"
    Work down this list:

    1. **No flag.** A block executes only when its info string asks:
       ```` ```bash run ````, `destructive` or `background`. A plain
       ```` ```bash ```` block is display only, by design. A misspelt flag
       (```` ```bash runs ````) is display only too, and `--check` reports
       `unknown flag: runs`.
    2. **No interpreter for the language.** Only `bash`, `sh`, `zsh` and
       `ruby` execute unless the runbook maps more. Otherwise the block
       shows, and `--check` prints:

        ```text
        sql blocks cannot execute; displayed only (map it under interpreters in the runbook front matter)
        ```

    3. **The fence is inside an indented code block.** A fence indented
       four or more spaces that is not inside a list item is an indented
       code block, so markdown shows it as literal text. Fences inside list
       items (indented to the item's text) and inside `>` blockquotes are
       recognised.
    4. **The button is there but greyed out.** Run buttons are disabled,
       titled `Start a run to execute blocks`, until a run has been started
       for the runbook on screen. Start one from the runbook's landing page;
       see [Starting a run](running/web-ui.md#starting-a-run).

    `runsheets --check` catches the first two. See
    [Executable Blocks](runbooks/blocks.md).

??? question "How do I run SQL, Python or another language?"
    Map the language to a command under `interpreters` in the runbook's
    front matter:

    ```yaml
    interpreters:
      sql: psql -X -v ON_ERROR_STOP=1 -f
      python: python3
    ```

    The block's code is written to a file and the command runs with that
    file's path appended, so ```` ```python run ```` becomes
    `python3 <path>`. The command is split like a shell would split it, but
    there is no shell, so a `$VARIABLE` in it is passed literally. When you
    need expansion, go through `bash -c` and take the file as `$0`:

    ```yaml
    interpreters:
      sql: bash -c 'psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -f "$0"'
    ```

    Inputs reach the block as environment variables either way. See
    [Interpreters](runbooks/blocks.md#interpreters).

??? question "A block was refused with “blank input referenced by block”"
    Before running a block, runsheets looks for `$NAME` and `${NAME}`
    references to the runbook's declared inputs. If any of them is empty it
    refuses, and nothing is spawned:

    ```text
    blank input referenced by block: SNAPSHOT_ID
    ```

    Give the input a value with **Change inputs** in the Run open panel on
    the landing page. See
    [Blank inputs are refused](runbooks/inputs.md#blank-inputs-are-refused).

??? question "Where does a blank input get its value?"
    When a run starts, each input takes the first value that is not empty:

    1. what was typed in the start-run form,
    2. the value an input of the same name was given in a run opened
       earlier in the same session (never for a secret),
    3. the environment variable of the same name in the process that
       started `runsheets`,
    4. the `default` in the front matter,
    5. otherwise the empty string.

    The form is pre-filled from 2 to 4, except secret fields, which are
    always empty. See
    [Where values come from](runbooks/inputs.md#where-values-come-from).

??? question "A block timed out"
    Every `run` and `destructive` block is bounded by its step's `timeout`,
    600 seconds unless the step says otherwise. On expiry the process group
    gets `TERM`, then `KILL` two seconds later, the block's status reads
    `timed out`, and the session log says `timed out after 600s`.

    Raise it per step. In a directory runbook, in the step's front matter:

    ```yaml
    ---
    title: Restore the snapshot
    timeout: 1800
    ---
    ```

    In a single-file runbook, in the comment after the step's heading:

    ```markdown
    ## Restore the snapshot
    <!-- timeout: 1800 -->
    ```

    There is no command-line option or config setting for it. The value
    must be a positive whole number of seconds; anything else warns
    `timeout must be a positive number of seconds (using 600)`. A
    `background` block has no timeout at all; stop it with its Stop button.
    See [Timeouts](running/execution.md#timeouts).

??? question "Running a block asks me to type a code"
    That block is `destructive`. The first attempt to run it is refused
    and the server issues a short code; the page prompts:

    ```text
    This block is destructive. Type the code 3fa9 to run it.
    ```

    Type the code shown to run it. Cancelling leaves the status at
    `cancelled`, a wrong code at `code did not match`, and the refusal is
    logged at `warn`. A code is used once; the next run of the block asks
    for a new one. See
    [Destructive confirmation](reference/security.md#destructive-confirmation).

??? question "An expect block says “differs from expected”"
    The output is compared with the expect block line by line, ignoring
    trailing whitespace, and the two are shown side by side with the
    differences marked. The output compared is stdout and stderr together,
    so a warning on stderr counts. A common cause is a value that changes
    on every run, such as a timestamp, an id or a duration. Put `{{any}}`
    in its place:

    ````markdown
    ```text expect
    snapshot {{any}} created at {{any}}
    ```
    ````

    `{{any}}` matches any characters, including none, within one line. It
    does not match across lines; a line that is only `{{any}}` matches
    exactly one line of output. The comparison is a hint for the operator
    and never fails a block. See [Expect blocks](runbooks/blocks.md#expect-blocks).

## Records, sessions and secrets

??? question "Where are my records and the session log?"
    Under the runs directory, `~/.local/share/runsheets/runs` by default
    and printed on the `Runs:` line of the banner:

    ```text
    <runs-dir>/sessions/<session-id>/session.json
    <runs-dir>/sessions/<session-id>/session.log
    <runs-dir>/<runbook-slug>/<session-id>/run.json
    <runs-dir>/<runbook-slug>/<session-id>/run.md
    <runs-dir>/<runbook-slug>/<session-id>/blocks/
    ```

    Move it with `--runs-dir DIR`, `RUNSHEETS_RUNS_DIR` or `runs_dir:` in a
    config file. runsheets never writes inside the runbook. See
    [The Run Record](running/run-record.md#location).

??? question "A session or run says “interrupted”"
    Its `runsheets` process was killed (a crash, `kill -9`, a closed
    terminal) before it could close the session. The next start, using the
    same runs directory, finds sessions still marked `running` whose
    process is gone, closes each as `interrupted` with any runs still open,
    and logs:

    ```text
    WARN  [session] earlier session 20261011T000914 was left running by a process that is gone; closed it as interrupted
    ```

    What was recorded before the kill is kept. Stopping with Ctrl-C or
    **End session** closes everything properly instead. See
    [Interrupted sessions](running/run-record.md#interrupted-sessions).

??? question "Are secrets safe?"
    An input declared `secret: true`:

    - is shown as an empty password field, never pre-filled,
    - is passed to blocks in the environment like any other input,
    - is never written to `run.json`, `run.md`, `session.json` or the
      session log (the log shows `[secret]`),
    - is never carried into another runbook's run,
    - is replaced with `[redacted NAME]` in captured output before the
      output is written or shown.

    Redaction is plain string replacement of the value as given. A secret
    a command prints base64-encoded, URL-encoded, hex-dumped or split
    across lines is not caught, and an empty secret redacts nothing. Write
    blocks that do not echo secrets, and treat the runs directory like
    terminal scrollback. See [Secrets](runbooks/inputs.md#secrets) and
    [Redaction](runbooks/inputs.md#redaction).
