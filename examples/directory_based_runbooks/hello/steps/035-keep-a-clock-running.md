---
title: Keep a clock running
kind: automated
---

Some things have to stay up while you work through later steps: a tunnel, a
log tail, a port forward. A `background` block has Start and Stop buttons
instead of Run. Its output streams into the page while it runs, it has no
timeout, and it is listed in the sidebar's **Running** panel on every page
with a Stop button of its own.

```bash background
while true; do
  date "+%H:%M:%S  still here"
  sleep 1
done
```

Leave it running and move to the next step, or stop it here. Anything still
running when the run is finished is stopped for you, and the execution is
recorded as `stopped` rather than as a failure.
