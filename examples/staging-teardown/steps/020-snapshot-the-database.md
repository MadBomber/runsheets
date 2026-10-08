---
title: Take a final snapshot of the database
kind: automated
timeout: 1800
---

A manual snapshot survives the deletion of the instance; automated ones do
not. This is the only copy of staging data that will exist afterwards, so
wait for it to reach `available` before moving on.

```bash run
set -euo pipefail
aws rds create-db-snapshot \
  --db-instance-identifier "$DB_INSTANCE" \
  --db-snapshot-identifier "$SNAPSHOT_ID" \
  --query 'DBSnapshot.{Id:DBSnapshotIdentifier,Status:Status}' --output table
aws rds wait db-snapshot-available --db-snapshot-identifier "$SNAPSHOT_ID"
aws rds describe-db-snapshots --db-snapshot-identifier "$SNAPSHOT_ID" \
  --query 'DBSnapshots[0].{Id:DBSnapshotIdentifier,Status:Status,SizeGB:AllocatedStorage,Created:SnapshotCreateTime}' \
  --output table
```

The second table is what you want to see, with `Status` at `available`:

```text expect
-------------------------------------------------------------------
|                       DescribeDBSnapshots                       |
+----------------------------+---------------------+--------+-----+
|  Created                   |  Id                 | SizeGB |Status|
+----------------------------+---------------------+--------+-----+
|  2026-10-01T14:02:11+00:00 |  acme-staging-final-preteardown | 100 | available |
+----------------------------+---------------------+--------+-----+
```

If `create-db-snapshot` fails with `DBSnapshotAlreadyExists`, someone ran
this step already. Check the existing snapshot's date before reusing it;
if it is older than today, pick a new `SNAPSHOT_ID` and start the run
again.
