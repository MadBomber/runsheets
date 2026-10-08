---
title: Delete the CloudFormation stack
kind: automated
destructive: true
timeout: 3600
---

This is the step that cannot be undone. Everything the stack owns goes:
the ECS cluster and services, the RDS instance (its final snapshot from
step 20 stays), the load balancer, the DNS record, the security groups.

Check once more that the snapshot exists and is `available`, in the same
process that will delete the stack, so a wrong `AWS_PROFILE` fails here
rather than on the delete:

```bash run
set -euo pipefail
aws sts get-caller-identity --query '{Account:Account,Arn:Arn}' --output table
aws rds describe-db-snapshots --db-snapshot-identifier "$SNAPSHOT_ID" --query 'DBSnapshots[0].Status' --output text
```

```text expect
available
```

Then delete. The confirmation code the page asks for is a speed bump; the
real check is the table above showing the staging account, not
production.

```bash destructive
set -euo pipefail
aws cloudformation delete-stack --stack-name "$STACK_NAME"
aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME"
echo "stack $STACK_NAME deleted"
```

`wait stack-delete-complete` can take forty minutes for a stack with an
RDS instance in it; the step timeout allows an hour. If it fails with
`DELETE_FAILED`, the events tell you which resource refused, usually a
security group something outside the stack still references:

```bash run
aws cloudformation describe-stack-events --stack-name "$STACK_NAME" \
  --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`].{Resource:LogicalResourceId,Reason:ResourceStatusReason}' \
  --output table
```
