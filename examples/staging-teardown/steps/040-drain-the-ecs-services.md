---
title: Drain the ECS services
kind: automated
timeout: 900
---

Scale every service in the cluster to zero and wait for the tasks to stop.
The load balancer starts returning 503 as soon as the last task exits,
which is expected; the DNS record goes away with the stack in step 60.

```bash run
set -euo pipefail
services=$(aws ecs list-services --cluster "$CLUSTER" --query 'serviceArns[]' --output text)
test -n "$services" || { echo "no services in $CLUSTER"; exit 0; }
for svc in $services; do
  name=${svc##*/}
  echo "scaling $name to 0"
  aws ecs update-service --cluster "$CLUSTER" --service "$name" --desired-count 0 --query 'service.desiredCount' --output text
done
aws ecs wait services-stable --cluster "$CLUSTER" --services $services
aws ecs describe-services --cluster "$CLUSTER" --services $services \
  --query 'services[].{Name:serviceName,Desired:desiredCount,Running:runningCount}' --output table
```

Every row of the final table should read `0` in both `Desired` and
`Running`. If a service refuses to drain (a task stuck in `DEPROVISIONING`
for more than ten minutes), stop its tasks directly:

```bash
aws ecs list-tasks --cluster "$CLUSTER" --service-name web --query 'taskArns[]' --output text \
  | xargs -n1 aws ecs stop-task --cluster "$CLUSTER" --reason "staging teardown" --task
```

That block is display only on purpose: run it from your terminal against
the one service that is stuck, not against all of them.
