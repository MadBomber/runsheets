---
title: Monthly PostgreSQL maintenance
when_to_use: >
  The first Monday of the month, or when the bloat report in the monitoring
  dashboard crosses 30% on any table. Run against one database at a time.
prerequisites:
  - psql 14 or newer on the PATH
  - A role with ownership of the application tables (VACUUM and REINDEX need it)
  - Nobody running a long report; REINDEX takes a lock
escalation: The data platform channel; after hours, the database on-call.
last_verified: 2026-09-01
tags: [postgres, maintenance]
inputs:
  - name: PGHOST
    prompt: Database host
    default: localhost
  - name: PGPORT
    prompt: Port
    default: "5432"
  - name: PGDATABASE
    prompt: Database name
    default: app
  - name: PGUSER
    prompt: Role to connect as
    default: app_owner
  - name: PGPASSWORD
    prompt: Password for that role
    secret: true
interpreters:
  sql: psql -X -v ON_ERROR_STOP=1 --pset footer=off -f
---

# Monthly PostgreSQL maintenance

A single-file runbook: this one markdown file holds the front matter, this
preamble, and one `##` heading per step. It also shows `sql run` blocks.
They execute because the front matter maps `sql` to a `psql` command; the
`.sql` file runsheets writes for each block is appended to that command,
and `psql` picks the connection up from the `PG*` inputs in the
environment. The password is a secret input: it reaches `psql`, never the
run record, and is redacted if anything prints it.

Step attributes live in an HTML comment right after each heading. GitHub
and every other renderer hide the comment, so the file reads as ordinary
markdown anywhere else.

## Check the connection
<!-- kind: verify, timeout: 30 -->

Prove the inputs are right before anything else. This also runs on its
own from the Checks page.

```sql run
select current_database() as database, current_user as role, version();
```

```text expect
 database |   role    |                    version
----------+-----------+-----------------------------------------------
 app      | app_owner | PostgreSQL 16.4 on x86_64-pc-linux-gnu, ...
```

## Find the bloated tables
<!-- kind: automated, timeout: 120 -->

Dead tuples that autovacuum has not caught up with. Anything with more
than a fifth of its rows dead is a candidate for the next step.

```sql run
select relname,
       n_live_tup as live,
       n_dead_tup as dead,
       round(100.0 * n_dead_tup / greatest(n_live_tup + n_dead_tup, 1), 1) as dead_pct,
       last_autovacuum
  from pg_stat_user_tables
 where n_dead_tup > 10000
 order by dead_pct desc
 limit 15;
```

Note the worst table in the step note; the next step takes its name as a
literal because `VACUUM` cannot be parameterised.

## Vacuum the worst table
<!-- kind: automated, timeout: 1800 -->

`VACUUM (VERBOSE, ANALYZE)` does not take an exclusive lock and can run
while the application is up. Edit the table name before clicking Run;
the exact text that ran is what the record keeps.

```sql run
vacuum (verbose, analyze) events;
```

Then confirm the dead count dropped:

```sql run
select relname, n_live_tup, n_dead_tup, last_vacuum
  from pg_stat_user_tables
 where relname = 'events';
```

## Reindex
<!-- kind: automated, destructive: true, timeout: 3600 -->

`REINDEX` takes a lock that blocks writes to the table for its duration.
It is marked destructive so the page asks for a confirmation code and
shows the escalation contact: the harm is downtime, not data loss.

```sql destructive
reindex (verbose) table concurrently events;
```

If `CONCURRENTLY` fails partway it leaves an invalid index behind. Find
and drop it:

```sql run
select indexrelid::regclass as index, indisvalid
  from pg_index
 where indrelid = 'events'::regclass and not indisvalid;
```

## Tell the team
<!-- kind: manual -->

Post the before and after dead-tuple counts from steps 2 and 3 in the
data platform channel. Mark this step done with a link to the post.

## Verify

Whole-procedure checks. Everything here is read-only and safe to run at
any time from the Checks page.

```sql run
select count(*) filter (where not indisvalid) as invalid_indexes
  from pg_index;
```

```text expect
 invalid_indexes
-----------------
               0
```

```sql run
select relname, n_dead_tup
  from pg_stat_user_tables
 where n_dead_tup > 100000
 order by n_dead_tup desc;
```

## Rollback

Nothing here destroys data. A `VACUUM` interrupted partway has done part
of its work and left the rest for next time. A `REINDEX CONCURRENTLY`
interrupted partway leaves an invalid index; drop it with the query in
the Reindex step and run the reindex again when there is a quiet window:

```sql
drop index concurrently events_created_at_idx_ccnew;
```
