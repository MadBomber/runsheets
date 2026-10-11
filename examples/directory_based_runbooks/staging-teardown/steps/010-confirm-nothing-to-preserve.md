---
title: Confirm nothing in staging needs to be preserved
kind: manual
---

Post in `#eng-announcements` that staging is being torn down, with the
change ticket number, and wait for anyone with an in-flight test to
respond. Give it the time the ticket says, usually an hour.

Then check the things people forget:

- Feature branches deployed to staging for review. Ask their owners.
- Data loaded by hand for a demo. If it matters, export it now; the
  snapshot in the next step keeps the database, not S3 uploads.
- Scheduled jobs that write somewhere outside staging.

Mark this step done with a note saying who confirmed and when. That note
is the audit trail for "we asked".
