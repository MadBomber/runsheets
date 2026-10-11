---
title: Check the greeting
kind: verify
---

A `verify` step is a read-only check. It runs in its place during the
procedure, and it also appears on the **Checks** page with every other
check, where **Run all** runs them one after another inside the run.

```bash run
echo "Hello, $NAME!" | grep -q "Hello, $NAME!" && echo "greeting looks right"
ruby -e 'puts "ruby answers: #{6 * 7}"'
```

```text expect
greeting looks right
ruby answers: 42
```
