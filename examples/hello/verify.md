---
title: Verify
kind: verify
---

Whole-procedure checks. These should pass after every run.

```bash run
test -n "$NAME" && echo "NAME is set to $NAME"
test -d "$RUNSHEETS_RUN_DIR/blocks" && echo "run directory exists: $RUNSHEETS_RUN_DIR"
```

A secret input never reaches the run record, even when a block prints it.
The value is replaced before the output is written:

```bash run
echo "the secret is $SECRET_WORD"
```
