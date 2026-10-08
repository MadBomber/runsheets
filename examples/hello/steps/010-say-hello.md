---
title: Say hello
kind: automated
timeout: 30
---

The inputs you gave when starting the run are exported as environment
variables, so a block can refer to them as `$NAME` and still be pasted into a
terminal unchanged.

```bash run
echo "Hello, $NAME!"
echo "Running block $RUNSHEETS_BLOCK of step $RUNSHEETS_STEP in run $RUNSHEETS_RUN_ID"
```

You should see something like:

```text expect
Hello, world!
Running block 010-say-hello-1 of step 010-say-hello in run 20261007T120000
```

A block with no flag is just displayed. This one is the same command, but it
has no Run button:

```bash
echo "Hello, $NAME!"
```
