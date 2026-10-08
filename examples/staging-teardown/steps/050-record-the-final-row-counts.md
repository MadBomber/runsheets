---
title: Record the final row counts
kind: verify
timeout: 300
---

Before the database goes, write its row counts into the run record. When
staging is rebuilt from the snapshot, the same query proves the restore
is complete.

The database is only reachable through the bastion. Open a port forward
and leave it running while the queries run; stop it from the Running
panel, or let finishing the run stop it:

```bash background
aws ssm start-session \
  --target "$(aws ec2 describe-instances --filters Name=tag:Role,Values=bastion Name=instance-state-name,Values=running \
      --query 'Reservations[0].Instances[0].InstanceId' --output text)" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$(aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE" \
      --query 'DBInstances[0].Endpoint.Address' --output text)\"],\"portNumber\":[\"5432\"],\"localPortNumber\":[\"15432\"]}"
```

With the tunnel up, count the rows in the tables that matter. The password
comes from the secret in the staging account, never from this file:

```bash run
set -euo pipefail
export PGPASSWORD=$(aws secretsmanager get-secret-value --secret-id "staging/db/app" --query SecretString --output text | jq -r .password)
psql -h localhost -p 15432 -U app -d app -X -At -c "
  select relname, n_live_tup from pg_stat_user_tables order by n_live_tup desc limit 10;"
```

```text expect
users|48213
orders|172045
events|9120044
```

The numbers will differ; the point is that the query runs and the record
keeps whatever it printed.
