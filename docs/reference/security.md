# Security Posture

runsheets executes shell on the operator's machine on request from a web
page. Everything about its design follows from taking that seriously.

## The model

- **One operator, one machine, one process, one session.** The server is
  started by the person who will run the commands and stops when they
  close it. Everything in between is one session, recorded under the name
  the operator gives on the start page or with `--engineer`. That name is
  the operator's own statement, written into the record; it is not
  authenticated. There is no login, no roles, and no multi-user story, and
  there should not be one.
- **The operator's environment is the execution environment.** Blocks run
  as the operator, with their shell environment, SSO sessions, tunnels and
  credentials. runsheets stores none of those and adds nothing.
- **Nothing executes unless two people agreed.** The author opted the block
  in with a flag in the markdown; the operator clicked Run once the
  runbook had a run. Everything else is inert text.

## Controls

### Loopback binding

The default bind address is `127.0.0.1`. Nothing on the network can reach
the server.

### Host authorization

Every request's `Host` header must be `localhost`, `127.0.0.1`, `::1`, or
the address given to `--bind`. Anything else is answered with 403. This
defeats DNS rebinding, where a hostile site points its own domain at
127.0.0.1 to reach a local server from the browser with a permitted origin.

A wildcard bind (`0.0.0.0` or `::`) answers on every interface, so no host
list can be right: the check is off for one, and the CLI says so when it
starts. A specific non-loopback address permits itself as well as the
loopback names.

### Session token

When the server starts it generates a random 128-bit token. Every page
embeds it in a `<meta>` tag, and every state-changing request must carry
it, either in the `X-Runsheets-Token` header (used by the page's
JavaScript) or in a `_token` form field (used by the HTML forms). Requests
without it are refused with 403 before any handler runs.

A page on another origin cannot read the token: same-origin policy stops it
reading the response of a request to `127.0.0.1`. It also cannot send the
custom header without a CORS preflight, which this server never answers.
And a plain cross-site form POST, which browsers do allow, has no way to
include the token. Together these close the hole where "a loopback server
with POST routes that spawn shell" could be driven by any web page the
operator happens to have open.

Sinatra's rack-protection middleware is left enabled as well, including its
`Origin` check on non-GET requests.

### Content Security Policy

The token in the page guards against other origins. It would be no guard
against the runbook itself: markdown may contain raw HTML, kramdown renders
it as written, and a runbook cloned from a repository is not necessarily
trusted. So every page is sent with a `Content-Security-Policy` whose
script and style sources are a nonce generated for that one response. The
page's own inline script and stylesheet carry the nonce; nothing else on
the page can run script, load a frame or plugin, or submit a form
elsewhere. A `<script>` in a step still renders as text in the HTML, and
does nothing. Pages are also sent with `Cache-Control: no-store`, since
they carry the token.

A Content Security Policy cannot stop a `<meta http-equiv="refresh">`
from navigating the page, so `<meta>` tags are removed from rendered
markdown altogether, in runbooks and in plain documents alike. A runbook
has no use for any other `<meta>`.

### Nothing recorded becomes markup

What the operator and the commands produce is shown on pages too, so it
is escaped on the way:

- **The runsheet.** `run.md` is rendered as markdown on the runsheet
  page. Command output and code go in a code fence longer than any run of
  backticks inside them, so they cannot close it; notes have their HTML
  and markdown characters escaped; input values and step slugs are code
  spans. Output cannot become live HTML on the runsheet page.
- **Restored output.** A step page embeds the last execution of each
  block as JSON for its script to restore. `<` is escaped in that JSON,
  so output holding `</script>` or `<!--` cannot end the block early.
- **The session log.** Tags (the runbook slug, the step, the execution
  id) have control characters replaced with `?`, so a file name holding a
  newline cannot forge a log line.

### Opt-in execution

Only fenced blocks whose info string carries `run`, `destructive` or
`background` execute, and only in languages with an interpreter. Unknown
flags and unrunnable languages are surfaced as warnings so a typo cannot
quietly turn a block inert, or quietly make one runnable.

### A session and a run required

Nothing can be posted until the session has started: until then every
page redirects to the start page and every other request is refused. A
block cannot execute until the runbook on screen has a run. Every
execution therefore belongs to a record, and the record and the session
log are written as it happens, not afterwards. Once the session has ended,
every request but the session page is refused with 410.

### Destructive confirmation

Destructive blocks sit under a banner with the runbook's blast radius and
escalation contact. The server refuses to run one until the request carries
a four-character code it issued for that block (HTTP 428 carries the code;
the page prompts for it). The code is random rather than the runbook slug
so it cannot become muscle memory, and it is retired once used. Because
the 428 response itself carries the code, anything that holds the session
token can read it and send it back: the code guards against a slip, not
against a script driving the API. It is no guard against a hostile
operator either, who could run the command in a terminal anyway. The
record marks the execution as confirmed.

### Blank inputs refused

A block that references a declared input whose value is blank is refused
before anything spawns. See [Inputs and Secrets](../runbooks/inputs.md).

### Secrets stay out of the record

Inputs marked `secret` reach the child process and nothing else: not
`run.json`, not `run.md`, not `session.json`, not the session log (which
shows `NAME=[secret]`), and not the page. A secret's field on the start
form is always empty, even when the environment or a default has a value
for it; its placeholder says it will use `$NAME` from the environment or
the default, and the server fills a blank secret from those when the run
starts. The Run open panel shows only that the secret is set, and the
Change inputs form leaves secret fields empty, keeping the current value
when one is left empty. A secret is never sent to the browser. A secret
is never carried from one run to
another within a session. Output is redacted on its way from the child to the
`.out` file and the session log, so a block that prints a secret records
`[redacted NAME]` instead. This is exact string replacement and does not catch encoded or
transformed forms; see [Inputs and Secrets](../runbooks/inputs.md#redaction).

### Process groups, timeouts and stops

Every execution is its own process group. Timeouts, operator stops and the
end of the session kill the group, so a block cannot leave a child behind.
The group is created at spawn, so nothing runsheets kills can reach the
operator's shell or the server. When the server stops (**End session**,
Ctrl-C, or a crash on the way up), the session ends: every run is closed
with the status its work earns and whatever is still running, in any
runbook, is stopped the same way, so a `background` block cannot outlive
the tool. A process that is killed outright leaves its session marked
running; the next start closes it as `interrupted`.

### File serving

`/files/*` serves only regular files inside the directory runsheets was
started on. Path components are normalised and checked against the real
root, and symbolic links are resolved and must land inside it too; hidden
entries (anything starting with `.`) are never served, which keeps
`.git`, `.env` and editor state out of reach.

A served file is not a page. Every `/files/*` response carries

```text
Content-Security-Policy: default-src 'none'; img-src 'self' data:; style-src 'unsafe-inline'; sandbox
X-Content-Type-Options: nosniff
```

and only images, PDFs and plain text (`.png`, `.jpg`, `.jpeg`, `.gif`,
`.webp`, `.svg`, `.pdf`, `.txt`) are served inline. Everything else is
sent as a download (`Content-Disposition: attachment`). An HTML or XML
file in a runbook directory can never become a page that runs script on
this origin, where it could read the session token.

### Front matter is data

Front matter is read with YAML's safe loader. Aliases (`&` and `*`) are
refused, so a small file cannot expand into a huge one, and so are tags
and classes other than dates and times. Either is a load error with a
message saying which: in a step file the message names the file; in a
library the runbook shows as broken, and `--check` reports it as an
error. A UTF-8 byte order mark is accepted, and bytes
that are not valid UTF-8 are replaced rather than failing the load.

### Bounded reads

A page never reads a whole output file or log. Block output on a page
and in the poll response is the last 256 KB of the execution's `.out`
file; the session page's log tail reads the last 64 KB of `session.log`
and shows its last 200 lines.

### No writes to the runbook

runsheets writes nothing inside the runbook directory. Session records,
the session log, run records, captured output and everything else it
produces go to the runs directory outside it; the runbook's files are only ever read.

Records (`run.json`, `run.md`, `session.json`) are written to a
temporary file and renamed into place, so a reader or a crash never sees
half a record. When the next start closes a killed session as
`interrupted`, it touches only run directories under the runs directory,
whatever the old `session.json` says.

## What is deliberately not done

- **No sandboxing of blocks.** They run as the operator on purpose.
- **No HTTPS.** Loopback traffic does not leave the machine.
- **No authentication beyond the token.** There is one operator and the
  token is already bound to their browser session.
- **No remote mode.** Binding to a non-loopback address is possible with
  `--bind` and is a bad idea on any network you do not fully control. The
  token is then the only thing between the network and your shell.

## Reporting

Security issues can be reported through the repository's issue tracker.
