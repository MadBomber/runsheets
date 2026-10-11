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

A `text expect` block after it shows what the output should look like.
Once the block has run, the page compares the two and hides the expect
block: a match just says so, and a mismatch shows both side by side with
the differences marked. The run id is different every time, so the
expected text has `{{any}}` in its place, which matches anything on that
line. It is a hint, not a verdict.

```text expect
Hello, world!
Running block 010-say-hello-1 of step 010-say-hello in run {{any}}
```

A block with no flag is just displayed. This one is the same command, but it
has no Run button:

```bash
echo "Hello, $NAME!"
```
