# About these examples

This file has no front matter, so it is a plain document, not a runbook.
It is not listed in the library tree; runbooks link to it.

Start runsheets on this directory to choose among the examples:

```bash
runsheets --open examples
```

| Example | Shape | Safe to run |
| --- | --- | --- |
| [Hello, runsheets](hello/runbook.md) | runbook directory | yes |
| [Disk space triage](disk-space-triage.md) | single file | yes, it only reads |
| [Monthly PostgreSQL maintenance](db-maintenance.md) | single file | needs a database |
| [Staging infrastructure teardown](staging-teardown/runbook.md) | runbook directory | no, read it |

## Plain documents

Besides this file, two plain documents back the disk space triage runbook:
[the disk usage glossary](disk-usage-glossary.md) beside it, and
[the cleanup policy](policies/cleanup-policy.md) in a folder of its own.

A runbook can link to a plain document anywhere under the directory
runsheets was started on (here, `examples/`), with an ordinary relative
link. Started on a single runbook instead (`runsheets examples/hello`),
that runbook's own directory is the limit, so a link climbing out of it,
like the one `hello/runbook.md` makes to this file, does not resolve.
