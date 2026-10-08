# HTTP Endpoints

The page's JavaScript and HTML forms are the intended clients, but the
endpoints are plain enough to drive with `curl`, which is also how the
smoke test works. All of them are served by the one `runsheet` process on
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
address, or the request gets **403** before routing.

```bash
B=http://127.0.0.1:4567
TOKEN=$(curl -s $B/ | sed -n 's/.*rs-token" content="\([a-f0-9]*\)".*/\1/p')
```

## Pages

| Method and path | Returns |
| --- | --- |
| `GET /` | The landing page. |
| `GET /steps/:slug` | A step page. `verify` and `rollback` are slugs too. 404 for an unknown slug. |
| `GET /run` | The active run's transcript, or the most recent run's. 404 if there has never been a run. |
| `GET /runs/:id` | A previous run's transcript. The id must match `[\w.-]+`. |
| `GET /files/*path` | A regular, non-hidden file inside the runbook directory, with its content type. 404 otherwise. |

## Run lifecycle

### `POST /run`

Starts a run. Form fields: `_token`, and `inputs[NAME]` for each input.
Missing inputs resolve from the environment and defaults.

Responds **303** to the first step, or **409** if a run is already active.

```bash
curl -X POST --data-urlencode "_token=$TOKEN" \
  --data-urlencode "inputs[NAME]=smoke" $B/run
```

### `POST /run/finish`

Form fields: `_token`, `status` (`completed`, default, or `abandoned`).
Responds **303** to the landing page, or **409** with no active run.

### `POST /steps/:slug/mark`

Form fields: `_token`, `status` (`done` or `skipped`), `note` (optional).
Responds **303** to the next step or the landing page; **422** for another
status; **409** with no active run.

## Execution

### `POST /blocks/:id/execute`

Starts executing a block. No body. Responds **202** with the execution as
JSON, including its initial (usually empty) output.

```bash
curl -s -X POST -H "X-Runsheets-Token: $TOKEN" $B/blocks/010-say-hello-1/execute
```

```json
{
  "id": "1b6a8f0c2d3e",
  "block_id": "010-say-hello-1",
  "step": "010-say-hello",
  "command": ["bash"],
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
  "success": false
}
```

Errors are **409** with `{"error": "..."}`:

- `start a run before executing blocks`
- `unknown block <id>`
- `block <id> is not executable (<kind>)`
- `blank input referenced by block: NAME`

### `GET /executions/:id`

The current state of an execution, same shape as above. `output` is the
last 256 KB of the log; `output_size` is the full size. **404** for an
unknown id. Requires no token (it is a GET) but, like every request, a
loopback `Host`.

The page polls this every 500 ms until `state` is no longer `running`.

```bash
curl -s $B/executions/1b6a8f0c2d3e | jq '{state, exit_status, output}'
```

## Errors

| Status | Meaning |
| --- | --- |
| 403 | Missing or invalid token on a non-GET request, or a non-loopback `Host`. |
| 404 | Unknown step, run, execution or file. |
| 409 | The operation is not allowed in the current run state (`Runsheets::RunError`). |
| 422 | Invalid step status. |
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
