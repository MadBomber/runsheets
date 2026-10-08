---
title: Verify
kind: verify
timeout: 300
---

Run after the last step, or on their own with **Verify only** at any time
afterwards: these prove staging is really gone and the snapshot is really
there.

```bash run
set -euo pipefail
status=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].StackStatus' --output text 2>&1 || true)
case "$status" in
  *"does not exist"*) echo "stack $STACK_NAME: gone" ;;
  *) echo "stack $STACK_NAME still reports: $status"; exit 1 ;;
esac
```

```bash run
set -euo pipefail
aws ecs describe-clusters --clusters "$CLUSTER" --query 'clusters[0].status' --output text | grep -qx INACTIVE \
  && echo "cluster $CLUSTER: inactive" || { echo "cluster $CLUSTER is still active"; exit 1; }
```

```bash run
set -euo pipefail
aws rds describe-db-snapshots --db-snapshot-identifier "$SNAPSHOT_ID" \
  --query 'DBSnapshots[0].{Status:Status,SizeGB:AllocatedStorage,Encrypted:Encrypted}' --output table
```

```text expect
--------------------------------------
|         DescribeDBSnapshots        |
+-----------+----------+-------------+
| Encrypted | SizeGB   |   Status    |
+-----------+----------+-------------+
|  True     |  100     |  available  |
+-----------+----------+-------------+
```
