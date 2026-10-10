---
title: Hello, runsheets
when_to_use: >
  You want to see what an executable runbook looks like, or you need a
  fixture that exercises every block kind without touching anything real.
prerequisites:
  - A shell with bash and ruby on the PATH
  - Nothing else; every command here is harmless
escalation: There is nobody to call. Read the step again.
tags: [example, safe]
inputs:
  - name: NAME
    prompt: Who should be greeted?
    default: world
  - name: SECRET_WORD
    prompt: A word that must never appear in the run record
    default: hunter2
    secret: true
---

# Hello, runsheets

This runbook exists to show the shape of a runbook directory and the fenced
block convention. Nothing in it changes your machine.

A runbook is a directory:

```text
hello/
  runbook.md       this file: front matter and preamble
  steps/*.md       one file per step, ordered by filename
  verify.md        whole-procedure checks
  rollback.md      what to do when it goes wrong
```

Start a run from the panel above, then walk the steps in the sidebar.

This runbook sits in a directory of examples. [About these
examples](../about-the-examples.md) is a plain document one level up,
linked like any other markdown file.
