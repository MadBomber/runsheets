---
title: Exercise a failure
kind: automated
destructive: true
timeout: 5
---

This step is marked destructive in its front matter even though it does no
harm, so you can see the confirmation flow. Both blocks are safe.

The first one exits non-zero on purpose. The page shows the exit status and
the run record keeps it:

```bash destructive
echo "about to fail on purpose" >&2
exit 3
```

The second one sleeps longer than the step's five second timeout, so the
process group is killed and the execution is recorded as timed out:

```bash run
echo "sleeping"
sleep 30
echo "never printed"
```
