# Inputs and Secrets

Inputs are the values a runbook needs that differ from run to run: an AWS
profile, a cluster name, a snapshot id, a password. They are declared once
in `runbook.md`, collected when a run starts, and exported as environment
variables to every executed block.

## Declaring inputs

```yaml
inputs:
  - name: AWS_PROFILE
    prompt: AWS profile with admin access
    default: staging-admin
  - name: SNAPSHOT_ID
    prompt: Identifier for the pre-teardown snapshot
    default: xyzzy-staging-final-preteardown
  - name: DB_PASSWORD
    prompt: Database password
    secret: true
```

`name` must be a valid environment variable name. `prompt` labels the form
field. `default` pre-fills it. `secret` masks it and keeps it out of the
record.

## Using inputs in blocks

Blocks refer to inputs as environment variables, which keeps the markdown
copy-pasteable into a terminal unchanged:

````markdown
```bash run
aws --profile "$AWS_PROFILE" rds create-db-snapshot \
  --db-snapshot-identifier "$SNAPSHOT_ID" \
  --db-instance-identifier staging
```
````

Ruby blocks read them from `ENV`:

````markdown
```ruby run
puts ENV.fetch("AWS_PROFILE")
```
````

## Where values come from

When the start-run form is submitted, each input resolves in this order:

1. What the operator typed in the form.
2. If blank, the environment variable of the same name in the process that
   started `runsheet`. A devcontainer with `AWS_PROFILE` already set needs no
   typing.
3. If still blank, the `default` from the front matter.
4. Otherwise the empty string.

The form is pre-filled with the result of steps 2 and 3, so the operator
sees what will be used before starting.

## Blank inputs are refused

An input that resolves to the empty string is dangerous: `aws rds
delete-db-snapshot --db-snapshot-identifier ""` is a different command from
the one the author wrote. Before executing a block, runsheets scans its code
for `$NAME` and `${NAME}` references to *declared* inputs and refuses to run
if any of them is blank:

```text
blank input referenced by block: SNAPSHOT_ID
```

The refusal appears in the block's status line and nothing is spawned.
Variables that are not declared inputs are not checked; they are the
block's own business.

## Secrets

A `secret: true` input:

- is rendered as a password field,
- is passed to the child process like any other input,
- is never written to `run.json` or `run.md`; the active-run panel shows
  only that it is set,
- is redacted from captured output before the output is written.

### Redaction

Every execution's stdout and stderr pass through a redactor on their way
to the `.out` file. Each occurrence of each secret value is replaced with
`[redacted NAME]`, longest secret first, so a block that prints
`password=hunter2` is recorded as `password=[redacted DB_PASSWORD]`. Output
arrives in chunks and a secret can straddle two of them, so the redactor
holds back a tail that could be the start of a secret until the next chunk
settles it. Nothing unredacted ever reaches the disk, the page, or the
transcript.

!!! warning "String replacement only"
    The redactor matches the value exactly as it was given. A secret that a
    command prints base64-encoded, URL-encoded, hex-dumped, wrapped across
    lines or inside a JWT is not caught. Treat the run directory with the
    same care as the terminal scrollback it replaces, and write blocks that
    do not echo secrets at all.

A secret whose value is blank is not redacted (there is nothing to match).
A very short secret would redact every occurrence of those characters in
the output, which is a nuisance rather than a leak; prefer secrets of
reasonable length.

Credentials are never stored by runsheets. A runbook that needs one either
asks through a secret input or hands the step to the operator's own terminal
with a `terminal` block.

## Variables runsheets sets

Every execution also receives these, so a block can find its own record if
it needs to:

| Variable | Value |
| --- | --- |
| `RUNSHEETS_RUN_ID` | The run's id, for example `20261007T173348`. |
| `RUNSHEETS_RUN_DIR` | Absolute path of the run directory. |
| `RUNSHEETS_RUNBOOK` | The runbook slug. |
| `RUNSHEETS_STEP` | The step slug. |
| `RUNSHEETS_BLOCK` | The block id. |

A block that wants to leave an artefact for the operator can write it under
`$RUNSHEETS_RUN_DIR`:

````markdown
```bash run
aws cloudformation describe-stacks > "$RUNSHEETS_RUN_DIR/stacks-before.json"
echo "saved $(wc -c < "$RUNSHEETS_RUN_DIR/stacks-before.json") bytes"
```
````

## The rest of the environment

The child inherits the full environment of the `runsheet` process, with
inputs and the `RUNSHEETS_*` variables layered on top. SSO sessions, `PATH`,
`HOME`, tunnels and anything else the operator's shell had are available.
Start `runsheet` from the shell you would have run the commands in.
