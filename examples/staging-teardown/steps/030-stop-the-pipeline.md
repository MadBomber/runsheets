---
title: Stop the deployment pipeline
kind: automated
timeout: 120
---

Nothing must redeploy to staging while the services are being drained.
Disable the deploy workflow rather than deleting it, so re-enabling it is
one command when the environment is rebuilt.

```bash run
set -euo pipefail
gh workflow disable deploy-staging.yml --repo acme/platform
gh workflow list --repo acme/platform --all | grep -i staging
```

Expect the staging workflow to show `disabled_manually`:

```text expect
Deploy to staging   disabled_manually   12345678
```

Some teams also have a bot that re-enables workflows it finds disabled.
If yours does, pause it in its own UI; that part is interactive, so do it
in your terminal and confirm here:

```bash terminal
gh auth status
open "https://github.com/acme/platform/actions/workflows/deploy-staging.yml"
```
