---
title: Rollback
---

There is no rolling back a deleted stack; there is rebuilding from the
snapshot. How far you got decides what to do.

**Stopped before step 60 (nothing deleted).** Re-enable the pipeline and
scale the services back up. The next deploy restores the desired counts;
this just gets staging answering again sooner:

```bash
gh workflow enable deploy-staging.yml --repo acme/platform
for svc in web worker scheduler; do
  aws ecs update-service --cluster "$CLUSTER" --service "$svc" --desired-count 2
done
```

**Step 60 failed partway (`DELETE_FAILED`).** The stack is in a state
CloudFormation will not touch until the failing resource is dealt with.
Find it with the last block of step 60, remove whatever references it
outside the stack, and run the delete again. Do not retain resources with
`--retain-resources` unless you intend to clean them up by hand.

**Staging is needed again after step 60.** Restore the snapshot into a
new instance and point a fresh stack at it. This is the rebuild runbook,
not this one; the snapshot identifier is `$SNAPSHOT_ID` and the run
record of the teardown has the row counts to compare against.
