# HTTP Endpoints

The page's JavaScript and HTML forms are the intended clients, but the
endpoints are plain enough to drive with `curl`, which is also how the
smoke test works. All of them are served by the one `runsheets` process on
loopback.

## Authentication

Every non-GET request must carry the token, which is generated when the
server starts and embedded in every page, the start page included:

```html
<meta name="rs-token" content="492a33d8abd63f00ff946cd79bbb2255">
```

Send it as the `X-Runsheets-Token` header or as a `_token` form field.
Requests without a valid token get **403** with a JSON body on the
execution endpoints and an HTML error page elsewhere.

The `Host` header must be `localhost`, `127.0.0.1`, `::1` or the bind
address, or the request gets **403** before routing. (For a wildcard bind
the check is off; see [the CLI page](../running/cli.md#about-bind).)

Every HTML page is sent with `Cache-Control: no-store` and a
`Content-Security-Policy` whose script and style sources are a nonce unique
to that response; the page's own inline script and stylesheet carry it.

```bash
B=http://127.0.0.1:4567
TOKEN=$(curl -sL $B/session/new | sed -n 's/.*rs-token" content="\([a-f0-9]*\)".*//p')
```

`/session/new` is the one page that answers before the session has
started; once it has, the page redirects to `/session`, which carries the
same token, hence `-L`.

## The session

Until the session has started, every `GET` (other than `/session/new`)
redirects to `/session/new` with **302**, and every other request with a
valid token gets **409**. After it has ended, every request but
`GET /session` gets **410**.

| Method and path | Returns |
| --- | --- |
| `GET /session/new` | The start page: who is starting the session, and why. Once the session has started, a **302** to `/session`. |
| `POST /session` | Starts the session. Form fields: `_token`, `engineer`, `why`; `why` becomes the first note. Responds **303** to `/library` (or `/` for one runbook); **422** with the start page and a message if either is blank; **303** to `/session` if a session has already started. |
| `GET /session` | The session page: engineer, host, start time, notes, runs, the end panel and the last 200 lines of `session.log`. |
| `POST /session/notes` | Adds a timestamped note. Form fields: `_token`, `note`. Responds **303** to `/session#notes`; **409** for a blank note. |
| `POST /session/end` | Ends the session: every run is closed with its derived status, anything running is stopped, and the server stops half a second later. Responds **200** with the Session ended page. |

## Pages

| Method and path | Returns |
| --- | --- |
| `GET /` | The landing page. |
| `GET /steps/:slug` | A step page. `verify` and `rollback` are slugs too. 404 for an unknown slug. |
| `GET /verify` | The Checks page: every verify step and `verify.md`. 404 if the runbook has none. |
| `GET /run` | The transcript of the open run of the runbook on screen, or of its most recent run, with the drift panel for a closed run. 404 if the runbook has never had a run. |
| `GET /runs/:id` | A transcript of the runbook on screen, by run id. The id must match `[\w.-]+`. |
| `GET /files/*path` | A regular, non-hidden file under the directory runsheets was started on, with its content type. 404 otherwise. |
| `GET /docs/*path` | A markdown file under that directory, rendered as a page with nothing executable. One of the own files of the runbook on screen redirects to its page; another runbook in the library redirects to its library page. 404 for anything that is not a `.md` file. |
| `GET /search?q=` | Full-text search over every runbook in the library (or the one runbook), best first. Works before a runbook is selected. An empty `q` shows the search form. |

### The library

When the server was started on a directory of runbooks, these routes exist
too; otherwise they are 404. Until a runbook is selected every other page
redirects to `/library`, except the session routes, `POST /runs`,
`/search`, `/docs/*` and `/files/*`, which resolve against the library
directory so the links in a runbook's library pane work before it is
selected.

| Method and path | Returns |
| --- | --- |
| `GET /library` | The library page: the folder tree, and the root folder in the main pane. |
| `GET /library/*slug` | The same page with that runbook or folder selected. The slug is the path inside the library (`platform/database/backup`). 404 for an unknown one. |

A `GET` of a library page rescans the directory when anything in it has
changed, so a runbook added while the server is up shows on the next visit.

## Runs

### `POST /runs`

Selects a runbook: establishes its run, or returns to the run it already
has in this session, and puts it on screen. Form fields: `_token`,
`slug` (the runbook's path in the library; ignored when the server was
started on one runbook), and `inputs[NAME]` for each input. Inputs left
out resolve from earlier in the session (non-secret only), the
environment and the defaults. When the runbook already has a run, the
inputs are ignored. Selecting a runbook finishes nothing; every run stays
open until the session ends.

Responds **303** to `/`; **404** for an unknown slug; **409** before the
session has started.

```bash
curl -X POST --data-urlencode "_token=$TOKEN" --data-urlencode "slug=hello" \
  --data-urlencode "inputs[NAME]=smoke" $B/runs
```

### `POST /run/inputs`

Changes the inputs of the run of the runbook on screen. Form fields:
`_token` and `inputs[NAME]` for each input. A secret sent empty keeps its
current value. The change is recorded as an `inputs` event and logged.
Responds **303** to `/`; **409** when the runbook on screen has no run.

### `POST /steps/:slug/mark`

Form fields: `_token`, `status` (`done` or `skipped`), `note` (optional).
Responds **303** to the next step or the landing page; **422** for another
status, or for a slug that is not a numbered step (the landing page,
`verify` and `rollback` cannot be marked); **409** when the runbook on
screen has no run.

## Execution

### `POST /blocks/:id/execute`

Starts executing a `run`, `destructive` or `background` block. Responds
**202** with the execution as JSON, including its initial (usually empty)
output.

```bash
curl -s -X POST -H "X-Runsheets-Token: $TOKEN" $B/blocks/010-say-hello-1/execute
```

```json
{
  "id": "1b6a8f0c2d3e",
  "block_id": "010-say-hello-1",
  "step": "010-say-hello",
  "command": ["bash"],
  "background": false,
  "state": "running",
  "pid": 83412,
  "started_at": "2026-10-07T17:33:48.871-05:00",
  "finished_at": null,
  "duration": null,
  "exit_status": null,
  "signal": null,
  "error": null,
  "cmd": "010-say-hello-1.1.cmd",
  "log": "010-say-hello-1.1.out",
  "output": "",
  "output_size": 0,
  "output_truncated": false,
  "success": false
}
```

A **destructive** block needs a confirmation code. The first request
without one is answered **428** with the code to type:

```json
{ "error": "destructive block 040-exercise-failure-1 needs confirmation: type 72bd",
  "challenge": "72bd", "block_id": "040-exercise-failure-1" }
```

Send it back as the `confirm` form field. The code is issued per block,
stays the same until it is used, and is retired by the execution it
confirmed. A wrong code gets the same 428 again.

```bash
CODE=$(curl -s -X POST -H "X-Runsheets-Token: $TOKEN" $B/blocks/040-exercise-failure-1/execute | jq -r .challenge)
curl -s -X POST -H "X-Runsheets-Token: $TOKEN" -d "confirm=$CODE" $B/blocks/040-exercise-failure-1/execute
```

Errors are **409** with `{"error": "..."}`:

- `start the run for <runbook title> before executing blocks`
- `unknown block <id>`
- `block <id> is not executable (<kind>)`
- `blank input referenced by block: NAME`

### `POST /blocks/:id/acknowledge`

Records that the operator ran a `terminal` block in their own terminal.
Form field `note` is optional. Responds **201** with the acknowledgement:

```json
{ "at": "2026-10-07T17:33:55.120-05:00", "step": "020-inspect-ruby",
  "note": "pressed enter", "block_id": "020-inspect-ruby-3" }
```

**409** when the runbook on screen has no run, for an unknown block, or for
a block that is not `terminal`.

### `GET /executions/:id`

The current state of an execution, same shape as above. `output` is the
last 256 KB of the log, `output_size` is the full size and
`output_truncated` says whether anything was cut. **404** for an unknown
id. Requires no token (it is a GET) but, like every request, a loopback
`Host`.

The page polls this every 500 ms until `state` is no longer `running`.

```bash
curl -s $B/executions/1b6a8f0c2d3e | jq '{state, exit_status, output}'
```

### `POST /executions/:id/stop`

Asks a running execution to stop: `TERM` to its process group, `KILL` two
seconds later if needed. Responds **202** with the execution as it is at
that moment (usually still `running`); poll `GET /executions/:id` until the
state is `stopped`. Any execution in the session can be stopped, whichever
runbook started it. Stopping an execution that has already ended is a
no-op. **409** for an unknown id.

```bash
curl -s -X POST -H "X-Runsheets-Token: $TOKEN" $B/executions/1b6a8f0c2d3e/stop
```

## Errors

| Status | Meaning |
| --- | --- |
| 403 | Missing or invalid token on a non-GET request, or a non-loopback `Host`. |
| 404 | Unknown step, run, execution, file or runbook slug. |
| 409 | The operation is not allowed now (`Runsheets::RunError`): no session yet, no run for the runbook on screen, a blank note. Refusals are logged at `warn`. |
| 410 | The session has ended. Only `GET /session` still answers. |
| 422 | A blank engineer or reason on `POST /session`, an invalid step status, or a mark on a document that is not a numbered step. |
| 428 | A destructive block needs its confirmation code (`Runsheets::Run::ConfirmationRequired`); the body carries `challenge`. |
| 500 | The runbook failed to load (`Runsheets::RunbookError`), or an unexpected error. |

JSON error bodies are `{"error": "message"}` on `/blocks/*` and
`/executions/*`, or when the request accepts `application/json`. Everything
else gets an HTML error page in the normal frame.

## Driving a whole session from the shell

Against a server started on `examples/hello` without `--engineer` and
`--why`:

```bash
B=http://127.0.0.1:4567
TOKEN=$(curl -sL $B/session/new | sed -n 's/.*rs-token" content="\([a-f0-9]*\)".*/\1/p')
post() { curl -s -o /dev/null -X POST --data-urlencode "_token=$TOKEN" "$@"; }

post --data-urlencode "engineer=ci" --data-urlencode "why=smoke test" $B/session
post --data-urlencode "inputs[NAME]=cli" $B/runs

ID=$(curl -s -X POST -H "X-Runsheets-Token: $TOKEN" $B/blocks/010-say-hello-1/execute | jq -r .id)
until [ "$(curl -s $B/executions/$ID | jq -r .state)" != running ]; do sleep 0.5; done
curl -s $B/executions/$ID | jq -r .output

post --data-urlencode "status=done" $B/steps/010-say-hello/mark
post --data-urlencode "note=greeting checked from the shell" $B/session/notes
post $B/session/end
```

On a server started on a directory of runbooks, add
`--data-urlencode "slug=hello"` to the `POST /runs`. Ending the session
closes the run (`partial` here, since only one step was marked) and stops
the server.
