---
title: Disk space triage
when_to_use: >
  A host is close to full: an alert on free space, a build failing with
  "No space left on device", or a log directory that keeps growing.
prerequisites:
  - A shell on the host, as a user that can read the directory to check
  - The cleanup policy (linked below) open in another tab
escalation: The owner of the host; for shared build machines, the platform channel.
tags: [disk, safe, example]
inputs:
  - name: TARGET_DIR
    prompt: Directory to check
    default: /tmp
  - name: THRESHOLD
    prompt: Highest acceptable use, in percent
    default: "90"
---

# Disk space triage

A single-file runbook that leans on plain documents kept elsewhere in the
examples directory. The background lives there, not in the steps:

- [Disk usage glossary](disk-usage-glossary.md): what `df` and `du`
  report and why they can disagree.
- [Cleanup policy](policies/cleanup-policy.md): what may be deleted, and what
  must never be.

Those files have no front matter, so runsheets treats them as documents:
they stay out of the library tree, and the links above open them as pages.
A document can sit anywhere under the directory `runsheets` was started on;
one is beside this file, the other in `policies/`. See also
[about these examples](about-the-examples.md).

Every block in this runbook only reads; nothing is deleted.

## Check free space
<!-- kind: verify, timeout: 30 -->

How full is the file system that holds `TARGET_DIR`? `df` answers for the
whole file system, not the directory; see
[df and du](disk-usage-glossary.md#df-and-du) if that is surprising.

```bash run
df -h "$TARGET_DIR"
```

## Find what is using it
<!-- timeout: 120 -->

The ten largest entries directly under `TARGET_DIR`. Entries you cannot
read are skipped.

```bash run
du -sh "$TARGET_DIR"/* 2>/dev/null | sort -rh | head -10
```

If the total here is far below what `df` reported, the space is held
somewhere else: another directory on the same file system, or deleted files
a process still holds open. The glossary explains
[deleted-but-open files](disk-usage-glossary.md#deleted-but-open-files).

## Decide what to clean
<!-- kind: manual -->

Compare what you found with the [cleanup policy](policies/cleanup-policy.md).
Delete only what it lists as safe, in your own terminal, and note here what
you removed and how much it freed.

```bash
rm -rf "$TARGET_DIR"/some-build-cache
```

## Verify

Use is at or below the threshold.

```bash run
used=$(df -P "$TARGET_DIR" | awk 'NR == 2 { sub("%", "", $5); print $5 }')
echo "use ${used}%, threshold ${THRESHOLD}%"
test "$used" -le "$THRESHOLD"
```

## Rollback

Nothing in this runbook deletes anything. If a manual cleanup removed
something it should not have, restore it from backup and tell the owner of
the host; the [cleanup policy](policies/cleanup-policy.md#when-something-was-deleted-by-mistake)
says who to call.
