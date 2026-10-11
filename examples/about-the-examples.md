# About these examples

This file has no front matter, so it is a plain document, not a runbook.
It is not listed in the library tree; runbooks link to it.

Start runsheets on this directory to choose among the examples:

```bash
runsheets --open examples
```

The examples are grouped by shape, and each group is a folder in the
library tree:

- `directory_based_runbooks/`: runbook directories, a `runbook.md` beside
  a `steps/` folder holding one file per step.
- `single_md_file_runbooks/`: single-file runbooks, every step in one
  markdown file, together with the plain documents they link to.

| Example | Shape | Safe to run |
| --- | --- | --- |
| [Hello, runsheets](directory_based_runbooks/hello/runbook.md) | runbook directory | yes |
| [Disk space triage](single_md_file_runbooks/disk-space-triage.md) | single file | yes, it only reads |
| [Monthly PostgreSQL maintenance](single_md_file_runbooks/db-maintenance.md) | single file | needs a database |
| [Staging infrastructure teardown](directory_based_runbooks/staging-teardown/runbook.md) | runbook directory | no, read it |

## Plain documents

Besides this file, two plain documents back the disk space triage runbook:
[the disk usage glossary](single_md_file_runbooks/disk-usage-glossary.md) beside it, and
[the cleanup policy](single_md_file_runbooks/policies/cleanup-policy.md) in a folder of its own.

A runbook can link to a plain document anywhere under the directory
runsheets was started on (here, `examples/`), with an ordinary relative
link. Started on a single runbook instead (`runsheets examples/directory_based_runbooks/hello`),
that runbook's own directory is the limit, so a link climbing out of it,
like the one `directory_based_runbooks/hello/runbook.md` makes to this file, does not resolve.
