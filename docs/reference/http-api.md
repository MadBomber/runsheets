# HTTP Endpoints

The page's JavaScript and HTML forms are the intended clients, but the
endpoints are plain enough to drive with `curl`, which is also how the
smoke test works. All of them are served by the one `runsheets` process on
loopback.

## Authentication

Every non-GET request must carry the session token, which is generated when
the server starts and embedded in every page:

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
TOKEN=$(curl -s $B/ | sed -n 's/.*rs-token" content="\([a-f0-9]*\)".*/\1/p')
```

## Pages

| Method and path | Returns |
| --- | --- |
| `GET /` | The landing page. |
| `GET /steps/:slug` | A step page. `verify` and `rollback` are slugs too. 404 for an unknown slug. |
| `GET /verify` | The Checks page: every verify step and `verify.md`. 404 if the runbook has none. |
| `GET /run` | The active run's transcript, or the most recent run's, with the drift panel for a finished run. 404 if there has never been a run. |
| `GET /runs/:id` | A previous run's transcript. The id must match `[\w.-]+`. |
| `GET /files/*path` | A regular, non-hidden file under the directory runsheets was started on, with its content type. 404 otherwise. |
| `GET /docs/*path` | A markdown file under that directory, rendered as a page with nothing executable. One of the open runbook's own files redirects to its page; another runbook in the library redirects to its library page. 404 for anything that is not a `.md` file. |
| `GET /search?q=` | Full-text search over every runbook in the library (or the one runbook), best first. Works before a runbook is open. An empty `q` shows the search form. |

### The library

When the server was started on a directory of runbooks, these routes exist
too; otherwise they are 404. Until a runbook is open every other page
redirects to `/library`.

| Method and path | Returns |
| --- | --- |
| `GET /library` | The library page: the folder tree, and the root folder in the main pane. |
| `GET /library/*slug` | The same page with that runbook or folder selected. The slug is the path inside the library (`platform/database/backup`). 404 for an unknown one. |
| `POST /library/open` | Opens the runbook named by the `slug` field and redirects to `/`. Needs the token. 404 for an unknown slug, 409 while a run is active. |

A `GET` of a library page rescans the directory when anything in it has
changed, so a runbook added while the server is up shows on the next visit.

## Run lifecycle

### `POST /run`

Starts a run. Form fields: `_token`, `inputs[NAME]` for each input, and
`kind` (`run`, the default, or `verify` for a verification run that may
only execute verify steps and `verify.md`). Missing inputs resolve from the
environment and defaults.

Responds **303** to the first step (or to `/verify` for a verification),
or **409** if a run is already active or `kind=verify` is asked of a
runbook with no verify documents.

```bash
curl -X POST --data-urlencode "_token=$TOKEN" \
  --data-urlencode "inputs[NAME]=smoke" $B/run
```

### `POST /run/finish`

Form fields: `_token`, `status` (`completed`, default, or `abandoned`).
Anything still running is stopped first. Responds **303** to the landing
page; **422** for another status, checked before anything is stopped;
**409** with no active run.

### `POST /steps/:slug/mark`

Form fields: `_token`, `status` (`done` or `skipped`), `note` (optional).
Responds **303** to the next step or the landing page; **422** for another
status, or for a slug that is not a numbered step (the landing page,
`verify` and `rollback` cannot be marked); **409** with no active run.

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

- `start a run before executing blocks`
- `unknown block <id>`
- `block <id> is not executable (<kind>)`
- `a verification run only executes verify steps and verify.md; <id> is in <step>`
- `blank input referenced by block: NAME`

### `POST /blocks/:id/acknowledge`

Records that the operator ran a `terminal` block in their own terminal.
Form field `note` is optional. Responds **201** with the acknowledgement:

```json
{ "at": "2026-10-07T17:33:55.120-05:00", "step": "020-inspect-ruby",
  "note": "pressed enter", "block_id": "020-inspect-ruby-3" }
```

**409** with no active run, an unknown block, or a block that is not
`terminal`.

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
state is `stopped`. Stopping an execution that has already ended is a
no-op. **409** for an unknown id.

```bash
curl -s -X POST -H "X-Runsheets-Token: $TOKEN" $B/executions/1b6a8f0c2d3e/stop
```

## Errors

| Status | Meaning |
| --- | --- |
| 403 | Missing or invalid token on a non-GET request, or a non-loopback `Host`. |
| 404 | Unknown step, run, execution or file. |
| 409 | The operation is not allowed in the current run state (`Runsheets::RunError`). |
| 422 | Invalid step or finish status, or a mark on a document that is not a numbered step. |
| 428 | A destructive block needs its confirmation code (`Runsheets::Session::ConfirmationRequired`); the body carries `challenge`. |
| 500 | The runbook failed to load (`Runsheets::RunbookError`). |
| 503 | The server has no runbook configured. |

JSON error bodies are `{"error": "message"}` on `/blocks/*` and
`/executions/*`, or when the request accepts `application/json`. Everything
else gets an HTML error page in the normal frame.

## Driving a whole run from the shell

```bash
B=http://127.0.0.1:4567
TOKEN=$(curl -s $B/ | sed -n 's/.*rs-token" content="\([a-f0-9]*\)".*/\1/p')

curl -s -o /dev/null -X POST --data-urlencode "_token=$TOKEN" --data-urlencode "inputs[NAME]=cli" $B/run

ID=$(curl -s -X POST -H "X-Runsheets-Token: $TOKEN" $B/blocks/010-say-hello-1/execute | jq -r .id)
until [ "$(curl -s $B/executions/$ID | jq -r .state)" != running ]; do sleep 0.5; done
curl -s $B/executions/$ID | jq -r .output

curl -s -o /dev/null -X POST --data-urlencode "_token=$TOKEN" --data-urlencode "status=done" $B/steps/010-say-hello/mark
curl -s -o /dev/null -X POST --data-urlencode "_token=$TOKEN" --data-urlencode "status=completed" $B/run/finish
```
