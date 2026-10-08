---
title: Inspect the Ruby that will run things
kind: automated
---

Ruby blocks execute with `ruby` unless the runbook's front matter maps the
language to another command, such as `bin/rails runner -`.

```ruby run
puts "Ruby #{RUBY_VERSION} on #{RUBY_PLATFORM}"
puts "cwd: #{Dir.pwd}"
puts "greeting for: #{ENV.fetch('NAME', '(unset)')}"
```

Other languages stay display only until there is a safe way to route them.
This SQL is for a client you open yourself:

```sql
SELECT count(*) FROM runs WHERE status = 'completed';
```

Some things cannot be run from a page at all, because they are interactive.
Do them in your own terminal, then click **I ran this** so the run record
shows you did, with a note if you want one:

```bash terminal
read -r -p "Press Enter when you have looked at the output above: "
```
