# Architecture

runsheets is a small Ruby gem: a document model, an execution layer, a
record writer, and a thin Sinatra app over them. The model has no dependency
on Sinatra and is tested in isolation.

```text
lib/runsheets.rb              requires the model; autoloads the web layer and CLI
lib/runsheets/
  front_matter.rb             YAML front matter splitter
  fences.rb                   finds fenced blocks, rewrites info strings
  block.rb                    a fenced block and the kind its flags ask for
  renderer.rb                 kramdown + rouge, wraps executable blocks
  step.rb                     one markdown file: front matter, body, html, blocks
  single_file.rb              splits a one-file runbook into preamble and ## sections
  runbook.rb                  a directory or a single file: steps, verify, rollback; last_verified stamp
  diff.rb                     line diff for drift between a record and the runbook
  redactor.rb                 replaces secret values in captured output
  execution.rb                one execution: state, pid, files, timing
  executor.rb                 spawns, pumps output through the redactor, reaps, times out, stops
  run_record.rb               run.json, run.md, blocks/; list, load, verdicts, drift
  session.rb                  the active run, inputs, live executions, confirmation codes, stamp offer
  web.rb                      Sinatra routes and the security checks
  pages.rb                    pure functions that build the HTML
  assets.rb                   inline CSS and JavaScript
  cli.rb                      option parsing and the exe entry point
bin/runsheets
examples/hello/               a safe runbook; also the test fixture
```

<div class="diagram" markdown>
![Rendering and execution pipelines](../assets/images/pipeline.svg)
</div>

## Rendering

### The fence problem

kramdown's GFM parser accepts only a single word as a fence info string.
"```bash run" is not a code block to it at all; the fence and its contents
fall through as a paragraph. So the block convention cannot be read from
kramdown's parse tree.

`Fences.extract` walks the markdown line by line, tracking open and close
fences (backtick or tilde, any length of three or more, up to three spaces
of indentation, matching the CommonMark rules closely enough for runbooks).
For each fence with an info string it records the info, the dedented code
and the line number, and rewrites the info string in the markdown to
`lang?rs=N`, where `N` is the fence's index. Bare fences are tracked, so
their contents are never mistaken for fences, but not recorded.

kramdown passes `lang?opts` through as the block's language (the form it
uses for Rouge options). `Renderer::HtmlConverter`, a subclass of
kramdown's HTML converter, overrides `convert_codeblock`: when it sees the
marker it strips it, restores the real language so Rouge highlights
correctly, lets the parent produce the highlighted `<div>`, and wraps the
result in the `rs-block` markup with the data attributes and toolbar the
page's JavaScript needs.

Because the marker travels inside kramdown's own data, blocks nested in
list items are found and numbered correctly, and a fence kramdown decides
not to treat as a code block simply renders unwrapped rather than
desynchronising the numbering.

### Syntax highlighting

Rouge, through kramdown's highlighter hook, with a small formatter subclass
that produces the `<div class="highlight"><pre><code>` wrapper the stylesheet
expects without using Rouge's deprecated legacy formatter. The Monokai dark
theme's CSS is inlined into every page.

### Steps and the runbook

`Step` is one markdown file: it splits front matter, renders the body once
at load time, keeps the blocks, and computes its warnings. `Runbook` loads
`runbook.md` as a step with slug `runbook`, the numbered steps in sorted
order, and the optional extras, and exposes lookups: `step(slug)`,
`find_block(id)`, `neighbors(step)`, `interpreter_for(lang)`. Everything is
immutable after load; editing a runbook means restarting the server.

## Executing

`Executor#start` writes the code to the execution's `.cmd` path, opens the
`.out` path, and calls `Process.spawn` with the interpreter command plus the
`.cmd` path, `pgroup: true`, stdin from `/dev/null`, stdout and stderr to
the log. A reaper thread polls `Process.wait2` with `WNOHANG` and the
timeout deadline; on expiry it signals the group with `TERM`, waits up to
two seconds, then `KILL`, and records the result as `timed_out`.

`Execution` is the state holder, mutated only by the executor through
`started!`, `finished!` and `failed!` under a mutex, and read by everyone
else. `wait` joins the reaper thread, which is how tests and the Ruby API
run a block synchronously.

## Recording

`RunRecord.start` creates the run directory and writes the initial
`run.json`. Executions are recorded as hashes the moment they are created,
before spawning, so the order in the record is the order of clicks. Live
`Execution` objects are kept alongside; `refresh!` copies their current
state into the hashes before any write. `write!` produces both `run.json`
and the `run.md` transcript from the same data.

`RunRecord.load` and `RunRecord.list` read records back for the history
panel and the `/runs/:id` page. A record also knows how to judge itself:
`verified?` says whether a completed run exercised the whole runbook with
nothing left failing, and `drift` compares each block's recorded `.cmd`
with the runbook as it reads now, using the small LCS diff in `diff.rb`.

The session reloads the runbook whenever one of its markdown files changes
on disk (checked on every GET), so a runbook can be edited while the
server is up and the drift view compares against what is there now.

## The session

`Session` is the in-memory operator state: the runbook, the active
`RunRecord`, the resolved inputs (secrets included, never written), and
the live executions by id. It is the only object the web layer talks to.
`execute(block_id)` does the checks (active run, executable block, no blank
referenced inputs), allocates file paths from the record, builds the
environment, and hands off to the executor. A mutex serialises the
state-changing calls.

## The web layer

`Web` is a `Sinatra::Base` subclass with a `before` filter that enforces
the host and token checks, a handful of page routes that call into
`Pages`, and two JSON endpoints for execute and poll. `Pages` is a module of
pure functions from a session to HTML, so every page can be rendered in a
test without HTTP. `Assets` holds the CSS and JavaScript as strings; a
page is one self-contained response and the gem serves no static files.

The JavaScript is small and framework-free: sidebar toggle, outline, copy
buttons, the execute-and-poll loop, restoring prior executions from a JSON
blob the step page embeds, and keyboard shortcuts.

## Testing

Minitest. The model classes are tested directly against the example
runbook and small generated runbooks in temporary directories; the executor
against real `bash` and `ruby` processes including a timeout; the record
against a temporary runs directory; and `Web` with rack-test, driving a
whole run from start to finish through HTTP.

```bash
bundle exec rake test
```

## Extension points

- **Languages**: the `interpreters` front matter, or `Block::INTERPRETERS`
  for defaults.
- **Executor**: `Session.new(executor: ...)` accepts anything responding to
  `start(execution, code:, env:, cwd:)`, which is how a test or an embedding
  application can intercept execution.
- **Pages**: every page builder is a module function taking a session; an
  embedding app can reuse `Renderer` and `Pages` or replace them.
