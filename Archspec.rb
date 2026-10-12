# frozen_string_literal: true

# Executable architecture for runsheets, checked by the archspec gem:
#
#   archspec check
#   archspec explain lib/runsheets/session.rb
#
# docs/reference/architecture.md describes the design; this file enforces it.
# runsheets is a gem: a document model, an execution layer, a record writer,
# a session over them, and two front ends (a Sinatra app and the terminal)
# wired together by the CLI. Dependencies point inward only:
#
#   cli ─┬─> routes ─> pages ─┐
#        └─> console ─────────┴─> session ─┬─> execution ─┐
#                                          ├─> recording ─┤
#                                          └─> document ──┴─> foundation
#
# Pages and routes may also read the document and recording layers directly
# (rendering, history); nothing outside session reaches execution.

root "."
source "lib/**/*.rb"

# Known violations, burned down rather than allowed: refresh with
# `archspec check --update-todo` only after fixing one.
todo "archspec_todo.yml"

# Shared building blocks with no runsheets dependencies beyond each other:
# the Runsheets module itself, settings, parsing helpers, the redactor, and the
# session log (a plain Logger wrapper that Config borrows LEVELS from).
component :foundation, in: %w[
  lib/runsheets.rb
  lib/runsheets/version.rb
  lib/runsheets/config.rb
  lib/runsheets/front_matter.rb
  lib/runsheets/fences.rb
  lib/runsheets/slug.rb
  lib/runsheets/block.rb
  lib/runsheets/diff.rb
  lib/runsheets/expectation.rb
  lib/runsheets/redactor.rb
  lib/runsheets/session_log.rb
]

# The document model: markdown files rendered into steps, runbooks, libraries.
component :document, in: %w[
  lib/runsheets/renderer.rb
  lib/runsheets/step.rb
  lib/runsheets/single_file.rb
  lib/runsheets/runbook.rb
  lib/runsheets/library.rb
  lib/runsheets/search.rb
]

# Spawning, pumping, reaping and timing out a block's process.
component :execution, in: %w[
  lib/runsheets/execution.rb
  lib/runsheets/executor.rb
]

# The runsheet: run.json, run.md and blocks/ on disk.
component :recording, in: %w[lib/runsheets/run_record.rb]

# The engineering session and each runbook's run inside it.
component :session, in: %w[
  lib/runsheets/run.rb
  lib/runsheets/session.rb
]

# Pure functions from a session to HTML, plus the inline CSS and JavaScript.
component :pages, in: %w[
  lib/runsheets/pages.rb
  lib/runsheets/pages/**/*.rb
  lib/runsheets/assets.rb
]

# The Sinatra app: routes and the host/token security checks.
component :routes, in: %w[lib/runsheets/web.rb]

# Terminal front end: prompts, templates, --new and --run.
component :console, in: %w[
  lib/runsheets/prompt.rb
  lib/runsheets/template.rb
  lib/runsheets/wizard.rb
  lib/runsheets/step_runner.rb
]

# Option parsing and the bin/runsheets entry point; the composition root.
component :cli, in: %w[lib/runsheets/cli.rb]

# ── Layering ────────────────────────────────────────────────────────────────

foundation.can_only_use(because: "the foundation is shared by every layer and depends on none")
document.can_only_use :foundation,
                      because: "the document model is tested in isolation and knows nothing of runs or front ends"
execution.can_only_use :foundation,
                       because: "the executor runs code it is handed; it does not know runbooks, records or sessions"
recording.can_only_use :foundation,
                       because: "run records are plain data on disk, readable without a live session"
session.can_only_use :foundation, :document, :execution, :recording,
                     because: "the session sits over the model and knows nothing of HTTP or the terminal"
pages.can_only_use :foundation, :document, :recording, :session,
                   because: "pages render a session; they never touch processes or routes"
routes.can_only_use :foundation, :document, :recording, :session, :pages,
                    because: "routes talk to the session and render through Pages; execution goes through the session"
console.can_only_use :foundation, :document, :session,
                     because: "terminal flows run steps through the session, never the web layer"
cli.can_only_use :foundation, :document, :session, :pages, :routes, :console,
                 because: "the CLI wires the front ends together"

no_cycles

# ── Third-party boundaries ──────────────────────────────────────────────────
#
# Each library stays behind the component that owns it: the web stack behind
# routes (and Rack::Utils for escaping in pages), kramdown and rouge behind
# Renderer, myway_config behind Config. The model loads without Sinatra.

VENDORS = {
  %w[Sinatra Puma Rackup] => %i[routes],
  %w[Rack]                => %i[routes pages],
  %w[Kramdown Rouge]      => %i[document],
  %w[MywayConfig Anyway]  => %i[foundation]
}.freeze

vendor_reason = "third-party libraries are reached only through the component that owns them"
%i[foundation document execution recording session pages routes console cli].each do |layer|
  forbidden = VENDORS.reject { |_, owners| owners.include?(layer) }.keys.flatten
  send(layer).cannot_reference_constants(*forbidden, because: vendor_reason)
end

# ── Process control ─────────────────────────────────────────────────────────

spawn_reason = "only Executor spawns runbook code, so every execution is recorded and redacted"
%i[foundation document recording session pages routes console].each do |layer|
  send(layer).cannot_call(:spawn, :exec, :system, :popen, :popen3, :capture2, :capture3, because: spawn_reason)
end
