---
title: Staging infrastructure teardown
when_to_use: >
  The staging environment is being retired or rebuilt from scratch and
  nothing in it needs to survive. Not for routine deploys, not for
  production, never while a release is being verified on staging.
prerequisites:
  - AWS CLI v2 logged in through SSO to the staging account (`aws sso login`)
  - GitHub CLI (`gh`) authenticated with permission to disable workflows
  - Session Manager plugin for the SSM port forward in step 50
  - jq on the PATH
blast_radius: >
  Every ECS service, the RDS instance, the load balancer and the DNS record
  for staging. Anything in staging that was not snapshotted in step 20 is
  gone for good. Production is untouched: a different account, a different
  profile.
escalation: The platform on-call engineer, via the #platform-oncall channel.
last_verified: 2026-10-01
tags: [aws, ecs, rds, staging, destructive]
inputs:
  - name: AWS_PROFILE
    prompt: AWS profile for the staging account
    default: acme-staging-admin
  - name: AWS_REGION
    prompt: Region the staging stack lives in
    default: us-east-1
  - name: CLUSTER
    prompt: ECS cluster name
    default: acme-staging
  - name: DB_INSTANCE
    prompt: RDS instance identifier
    default: acme-staging-db
  - name: SNAPSHOT_ID
    prompt: Identifier for the final pre-teardown snapshot
    default: acme-staging-final-preteardown
  - name: STACK_NAME
    prompt: CloudFormation stack that owns the environment
    default: acme-staging
---

# Staging infrastructure teardown

This runbook takes the staging environment down in an order that leaves a
restorable database snapshot and no orphaned resources. It is the shape of
a real teardown runbook: the commands are the ones you would type, the
account names are made up.

Read the blast radius above before starting a run. The steps are:

1. Confirm with the team that nothing in staging needs to be kept.
2. Take and verify a final RDS snapshot.
3. Stop the deployment pipeline so nothing redeploys mid-teardown.
4. Drain the ECS services to zero.
5. Open a tunnel to the database and record the final row counts.
6. Delete the CloudFormation stack.

Every executed command, its output and your acknowledgements are recorded.
Attach the run record to the change ticket when you are done.
