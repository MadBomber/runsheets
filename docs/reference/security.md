# Security Posture

runsheets executes shell on the operator's machine on request from a web
page. Everything about its design follows from taking that seriously.

## The model

- **One operator, one machine, one process.** The server is started by the
  person who will run the commands and stops when they close it. There is
  no login, no roles, and no multi-user story, and there should not be one.
- **The operator's environment is the execution environment.** Blocks run
  as the operator, with their shell environment, SSO sessions, tunnels and
  credentials. runsheets stores none of those and adds nothing.
- **Nothing executes unless two people agreed.** The author opted the block
  in with a flag in the markdown; the operator clicked Run during an active
  run. Everything else is inert text.

## Controls

### Loopback binding

The default bind address is `127.0.0.1`. Nothing on the network can reach
the server.

### Host authorization

Every request's `Host` header must be `localhost`, `127.0.0.1`, `::1`, or
the address given to `--bind`. Anything else is answered with 403. This
defeats DNS rebinding, where a hostile site points its own domain at
127.0.0.1 to reach a local server from the browser with a permitted origin.

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

### Opt-in execution

Only fenced blocks whose info string carries `run`, `destructive` or
`background` execute, and only in languages with an interpreter. Unknown
flags and unrunnable languages are surfaced as warnings so a typo cannot
quietly turn a block inert, or quietly make one runnable.

### Active run required

A block cannot execute unless a run is active. Every execution therefore
belongs to a record, and the record is written as it happens, not
afterwards.

### Destructive confirmation

Destructive blocks sit under a banner with the runbook's blast radius and
escalation contact. The server refuses to run one until the request carries
a four-character code it issued for that block (HTTP 428 carries the code;
the page prompts for it). The code is random rather than the runbook slug
so it cannot become muscle memory, it is checked server-side so a script
driving the API cannot skip it, and it is retired once used. It is a guard
against a reflexive click, not against a hostile operator, who could run
the command in a terminal anyway. The record marks the execution as
confirmed.

### Blank inputs refused

A block that references a declared input whose value is blank is refused
before anything spawns. See [Inputs and Secrets](../runbooks/inputs.md).

### Secrets stay out of the record

Inputs marked `secret` reach the child process and nothing else: not
`run.json`, not `run.md`, not the active-run panel (which shows only that
the secret is set). Output is redacted on its way from the child to the
`.out` file, so a block that prints a secret records `[redacted NAME]`
instead. This is exact string replacement and does not catch encoded or
transformed forms; see [Inputs and Secrets](../runbooks/inputs.md#redaction).

### Process groups, timeouts and stops

Every execution is its own process group. Timeouts, operator stops and the
end of the run kill the group, so a block cannot leave a child behind. The
group is created at spawn, so nothing runsheets kills can reach the
operator's shell or the server.

### File serving

`/files/*` serves only regular files inside the runbook directory. Path
components are normalised and checked against the real root; hidden entries
(anything starting with `.`) are never served, which keeps `.git`, `.env`
and editor state out of reach.

### No writes to the runbook

runsheets writes nothing inside the runbook directory, with one exception:
the `last_verified` stamp. It is offered only after a run that verified the
runbook, applied only when the operator clicks **Stamp runbook.md**, and it
replaces exactly one front-matter line (adding it if absent). The write is
recorded as a `stamp` event in the run record. Nothing else in the
directory is ever touched.

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
