---
title: Check the greeting
kind: verify
---

A `verify` step is a read-only check. It runs in its place during the
procedure, and it also runs on its own: the landing page's **Verify** panel
starts a verification run that executes only verify steps and `verify.md`,
and records it like any other run.

```bash run
echo "Hello, $NAME!" | grep -q "Hello, $NAME!" && echo "greeting looks right"
ruby -e 'puts "ruby answers: #{6 * 7}"'
```

```text expect
greeting looks right
ruby answers: 42
```
