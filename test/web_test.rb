# frozen_string_literal: true

require "test_helper"

class TestWeb < Minitest::Test
  include RunsheetsTest::WebFixtures

  LINKED_DOCUMENT = {
    "runbook.md" => "---\ntitle: Linked\n---\nSee the [glossary](docs/glossary.md) and [step one](steps/010-a.md).\n",
    "steps/010-a.md" => "---\ntitle: A\nkind: manual\n---\nBack to the [glossary](../docs/glossary.md#terms).\n",
    "docs/glossary.md" => "# Glossary\n\n```bash run\nrm -rf /\n```\n\n![diagram](flow.svg)\n",
    "docs/flow.svg" => "<svg/>",
    "notes.txt" => "plain"
  }.freeze

  INLINE_SCRIPT = {
    "runbook.md" => "---\ntitle: T\n---\n<script>document.title='x'</script>\n",
    "steps/010-a.md" => "hi\n"
  }.freeze

  def setup = serve_web

  def teardown = stop_web

  def test_landing_page
    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "Hello, runsheets"
    assert_includes last_response.body, 'name="inputs[NAME]"'
    assert_includes last_response.body, 'type="password"'
    assert_includes last_response.body, 'action="/runs"'
    assert_includes last_response.body, ">Tester · ", "the session in the header"
    refute_includes last_response.body, "Verify only"
  end

  def test_step_page_shows_blocks_and_run_buttons
    get "/steps/010-say-hello"
    assert last_response.ok?
    assert_includes last_response.body, 'data-block="010-say-hello-1"'
    assert_includes last_response.body, 'data-action="execute"'
    assert_includes last_response.body, "No run for this runbook yet"
    assert_includes last_response.body, '<meta name="rs-token" content="tok">'
  end

  def test_run_buttons_are_disabled_without_an_active_run
    say_hello = get("/steps/010-say-hello").body
    inspect   = get("/steps/020-inspect-ruby").body
    start_run
    unlocked  = get("/steps/010-say-hello").body
    assert_includes say_hello, 'data-action="execute" data-locked disabled title="Start a run to execute blocks"'
    assert_includes inspect, 'data-action="acknowledge" data-locked disabled title="Start a run to confirm terminal blocks"'
    assert_includes unlocked, 'data-action="execute"'
    refute_includes unlocked, "data-locked disabled"
  end

  def test_links_to_plain_markdown_point_at_the_docs_route
    serve_files(LINKED_DOCUMENT)
    runbook = get("/").body
    step    = get("/steps/010-a").body
    assert_includes runbook, 'href="/docs/docs/glossary.md"'
    assert_includes step, 'href="/docs/docs/glossary.md#terms"'
  end

  def test_plain_markdown_renders_as_a_document
    serve_files(LINKED_DOCUMENT)
    document = get("/docs/docs/glossary.md")
    assert document.ok?
    assert_includes document.body, "<title>Glossary · Linked</title>"
    assert_includes document.body, "nothing here executes"
    refute_match(/<button[^>]*data-action="execute"/, document.body, "a document has no Run buttons")
    assert_includes document.body, 'src="/files/docs/flow.svg"', "its own relative links resolve from its folder"
  end

  def test_a_link_to_one_of_the_runbooks_own_files_goes_to_its_page
    serve_files(LINKED_DOCUMENT)
    step    = get "/docs/steps/010-a.md"
    runbook = get "/docs/runbook.md"
    assert_equal 302, step.status
    assert_match %r{/steps/010-a\z}, step.location
    assert_equal 302, runbook.status
    assert_match %r{://[^/]+/\z}, runbook.location
  end

  def test_docs_route_serves_only_markdown_inside_the_runbook
    serve_files(LINKED_DOCUMENT)
    not_markdown = get "/docs/notes.txt"
    traversal    = get "/docs/../../etc/passwd.md"
    missing      = get "/docs/missing.md"
    assert_equal 404, not_markdown.status
    assert_equal 404, traversal.status
    assert_equal 404, missing.status
  end

  def test_search_on_a_single_runbook_searches_that_runbook
    get "/search", "q" => "greeting"
    assert last_response.ok?
    assert_includes last_response.body, "1 runbook match"
    assert_includes last_response.body, 'href="/steps/045-check-the-greeting"'
    assert_includes last_response.body, 'class="rs-search"', "the header has the search box"
  end

  def test_extras_and_rollback_sidebar
    inspect = get("/steps/020-inspect-ruby").body
    verify  = get "/steps/verify"
    assert_includes inspect, "<summary>Rollback</summary>"
    assert_includes inspect, "nothing to undo"
    assert verify.ok?
  end

  def test_unknown_step_is_404
    get "/steps/nope"
    assert_equal 404, last_response.status
  end

  def test_the_default_bind_refuses_other_hosts_and_a_wildcard_bind_accepts_them
    header "Host", "evil.example.com"
    refused = get "/"
    Runsheets::Web.configure_for(@session, bind: "0.0.0.0")
    header "Host", "192.168.1.20"
    anyone = get "/"
    assert_equal 403, refused.status
    assert anyone.ok?, "a wildcard bind answers any host"
  end

  def test_post_without_token_is_refused
    run   = post "/runs"
    block = post "/blocks/010-say-hello-1/execute"
    assert_equal 403, run.status
    assert_equal 403, block.status
    assert_equal "application/json", block.media_type
  end

  def test_execute_requires_a_run
    execute("010-say-hello-1")
    assert_equal 409, last_response.status
    assert_match(/start the run for Hello, runsheets/, json["error"])
  end

  def test_starting_a_run_lands_on_the_runbook_page_with_the_run_open
    started = start_run("NAME" => "web")
    page    = get("/").body
    assert_equal 302, started.status
    assert_match %r{://[^/]+/\z}, started.location, "lands on the runbook page"
    assert @session.active?
    assert_includes page, "Run open"
    assert_includes page, "Work through the steps"
    refute_includes page, "/run/finish"
    assert_includes page, "<code>NAME=web</code>"
    refute_includes page, "hunter2"
  end

  def test_an_executed_block_reports_its_output
    start_run("NAME" => "web")
    started = execute("010-say-hello-1")
    data    = finish(json(started)["id"])
    assert_equal 202, started.status
    assert_equal "finished", data["state"]
    assert_equal 0, data["exit_status"]
    assert data["success"]
    assert_includes data["output"], "Hello, web!"
  end

  def test_a_step_page_shows_the_output_of_its_last_execution
    start_run("NAME" => "web")
    finish(json(execute("010-say-hello-1"))["id"])
    page = get("/steps/010-say-hello").body
    assert_includes page, 'id="rs-prior"'
    assert_includes page, "Hello, web!"
    assert_includes page, "Mark done and continue"
  end

  def test_marking_a_step_moves_on_and_is_recorded
    start_run("NAME" => "web")
    finish(json(execute("010-say-hello-1"))["id"])
    marked = post "/steps/010-say-hello/mark", { "_token" => "tok", "status" => "done", "note" => "fine" }
    run    = get "/run"
    home   = get("/").body
    record = get "/runs/#{@session.run.id}"
    assert_equal 302, marked.status
    assert_match %r{/steps/020-inspect-ruby\z}, marked.location
    assert run.ok?
    assert_includes run.body, "marked done"
    refute_includes home, "Previous runs", "the open run is not history yet"
    assert record.ok?
    assert_includes record.body, "running"
    assert_includes File.read(@session.log.path), "[hello 010-say-hello] marked done: fine"
  end

  def test_destructive_block_needs_the_servers_confirmation_code
    start_run
    asked = execute("040-exercise-failure-1")
    wrong = execute("040-exercise-failure-1", "confirm" => "nope")
    code  = json(asked)["challenge"]
    right = execute("040-exercise-failure-1", "confirm" => code)
    done  = finish(json(right)["id"])
    assert_equal 428, asked.status
    assert_match(/\A[0-9a-f]{4}\z/, code)
    assert_equal "040-exercise-failure-1", json(asked)["block_id"]
    assert_equal 428, wrong.status
    assert_equal code, json(wrong)["challenge"], "the same code until it is used"
    assert_equal 202, right.status
    assert_equal 3, done["exit_status"]
  end

  def test_a_background_block_has_start_and_stop_buttons
    start_run
    page = get("/steps/035-keep-a-clock-running").body
    assert_includes page, ">Start</button>"
    assert_includes page, 'data-action="stop"'
    refute_includes page, 'id="rs-running"'
  end

  def test_a_started_background_block_shows_in_the_running_panel
    start_run
    started = execute("035-keep-a-clock-running-1")
    home    = get("/").body
    assert_equal 202, started.status
    assert json(started)["background"]
    assert_includes home, 'id="rs-running"'
    assert_includes home, "data-execution=\"#{json(started)['id']}\""
  end

  def test_stopping_a_background_block
    start_run
    id      = json(execute("035-keep-a-clock-running-1"))["id"]
    stopped = post "/executions/#{id}/stop"
    data    = finish(id)
    home    = get("/").body
    unknown = post "/executions/nope/stop"
    assert_equal 202, stopped.status
    assert_equal "stopped", data["state"]
    refute_includes home, 'id="rs-running"'
    assert_equal 409, unknown.status
  end

  def test_acknowledge_terminal_block
    start_run
    before = get("/steps/020-inspect-ruby").body
    with_token
    ack     = post "/blocks/020-inspect-ruby-3/acknowledge", { "note" => "done" }
    after   = get("/steps/020-inspect-ruby").body
    refused = post "/blocks/020-inspect-ruby-1/acknowledge"
    assert_includes before, 'data-action="acknowledge"'
    assert_equal 201, ack.status
    assert_equal "done", json(ack)["note"]
    assert_equal "020-inspect-ruby-3", json(ack)["block_id"]
    assert_includes after, '"acks":{"020-inspect-ruby-3"'
    assert_equal 409, refused.status
  end

  def test_expect_block_is_linked_to_the_block_above_it
    get "/steps/010-say-hello"
    assert_includes last_response.body, 'data-expect-for="010-say-hello-1"'
    assert_includes last_response.body, 'data-role="expected"'
  end

  def test_active_run_panel_shows_secrets_as_set_without_values
    start_run("SECRET_WORD" => "swordfish")
    get "/"
    assert_includes last_response.body, "SECRET_WORD=•••"
    refute_includes last_response.body, "swordfish", "not even in the change form"
    assert_includes last_response.body, "leave blank to keep the current value"
  end

  def test_the_checks_page_before_a_run
    get "/verify"
    assert last_response.ok?
    assert_includes last_response.body, "No run for this runbook yet"
    assert_includes last_response.body, 'data-block="045-check-the-greeting-1"'
    assert_includes last_response.body, 'data-block="verify-2"'
    refute_includes last_response.body, '<button type="button" class="btn primary" data-action="run-all"'
  end

  def test_the_checks_page_in_a_run_offers_run_all
    start_run
    home   = get("/").body
    checks = get("/verify").body
    assert_includes home, "Go to checks (3)"
    assert_includes checks, '<button type="button" class="btn primary" data-action="run-all"'
    assert_includes checks, "Run all 3 checks"
  end

  def test_checks_and_steps_execute_in_the_one_run
    start_run
    check = execute("verify-1")
    step  = execute("010-say-hello-1")
    assert_equal 202, check.status
    assert_equal 202, step.status, "every step runs in the one run"
  end

  def test_run_page_shows_drift_when_the_runbook_changed
    dir = example_copy
    serve(Runsheets::Runbook.load(dir))
    start_run
    finish(json(execute("010-say-hello-1"))["id"])
    @session.current.close!
    unchanged = get("/runs/#{@session.run.id}").body
    path = File.join(dir, "steps", "010-say-hello.md")
    File.write(path, File.read(path).sub('echo "Hello, $NAME!"', 'echo "Howdy, $NAME!"'))
    stale   = @session.runbook.stale?
    changed = get("/runs/#{@session.run.id}").body
    home    = get("/").body
    refute_includes unchanged, "Runbook changed since this run"
    assert stale
    assert_includes changed, "Runbook changed since this run"
    assert_includes changed, "-echo &quot;Hello, $NAME!&quot;"
    assert_includes changed, "+echo &quot;Howdy, $NAME!&quot;"
    assert_includes home, "stopped at 010-say-hello"
  end

  def test_unknown_execution_is_404_json
    with_token
    get "/executions/nope"
    assert_equal 404, last_response.status
    assert_equal "application/json", last_response.media_type
  end

  def test_files_route_serves_runbook_files_but_not_traversal
    runbook   = get "/files/runbook.md"
    traversal = get "/files/../../Gemfile"
    git       = get "/files/.git/config"
    assert runbook.ok?
    assert_includes runbook.body, "title: Hello, runsheets"
    assert_equal 404, traversal.status
    assert_equal 404, git.status
  end

  def test_bad_run_id
    get "/runs/..%2F..%2Fetc"
    assert_equal 404, last_response.status
  end

  def test_pages_carry_a_csp_nonce_and_are_not_cached
    page  = get "/"
    csp   = page.headers["Content-Security-Policy"]
    nonce = csp[/script-src 'nonce-([^']+)'/, 1]
    refute_nil nonce
    assert_includes csp, "style-src 'nonce-#{nonce}'"
    assert_includes csp, "object-src 'none'"
    assert_includes page.body, "<script nonce=\"#{nonce}\">"
    assert_includes page.body, "<style nonce=\"#{nonce}\">"
    assert_equal "no-store", page.headers["Cache-Control"]
  end

  def test_each_response_gets_its_own_nonce
    first  = get("/").headers["Content-Security-Policy"][/nonce-([^']+)/, 1]
    second = get("/").headers["Content-Security-Policy"][/nonce-([^']+)/, 1]
    refute_nil first
    refute_equal first, second, "a nonce per response"
  end

  def test_error_pages_carry_a_nonce_too
    header "Accept", "text/html"
    missing = get "/steps/nope"
    assert_equal 404, missing.status
    assert_match(/nonce-/, missing.headers["Content-Security-Policy"], "error pages too")
  end

  def test_script_in_runbook_markdown_renders_without_the_nonce
    serve_files(INLINE_SCRIPT)
    body = get("/").body
    assert_includes body, "<script>document.title='x'</script>"
    assert_equal 1, body.scan("<script nonce=").size
  end

  def test_files_route_does_not_follow_symlinks_out_of_the_runbook
    dir = example_copy
    File.symlink("/etc/hosts", File.join(dir, "outside"))
    File.symlink(File.join(dir, "runbook.md"), File.join(dir, "inside"))
    serve(Runsheets::Runbook.load(dir))
    outside = get "/files/outside"
    inside  = get "/files/inside"
    assert_equal 404, outside.status
    assert inside.ok?, "a link that stays inside the runbook is fine"
    assert_includes inside.body, "title: Hello, runsheets"
  end

  def test_wildcard_and_loopback_addresses
    assert Runsheets::Web.wildcard?("0.0.0.0")
    assert Runsheets::Web.wildcard?("::")
    refute Runsheets::Web.wildcard?("127.0.0.1")
    assert Runsheets::Web.loopback?("127.0.0.1")
    assert Runsheets::Web.loopback?("::1")
    refute Runsheets::Web.loopback?("0.0.0.0")
    refute Runsheets::Web.loopback?("192.168.1.5")
  end

  def test_a_specific_bind_answers_its_own_address_and_loopback_names
    Runsheets::Web.configure_for(@session, bind: "192.168.1.5")
    header "Host", "192.168.1.20"
    other = get "/"
    header "Host", "192.168.1.5"
    own = get "/"
    header "Host", "localhost"
    loopback = get "/"
    assert_equal 403, other.status
    assert own.ok?
    assert loopback.ok?, "loopback names always work"
  end

  def test_changing_inputs_partway
    start_run("NAME" => "before")
    before  = get("/").body
    changed = post "/run/inputs", { "_token" => "tok", "inputs" => { "NAME" => "after" } }
    after   = get("/").body
    assert_includes before, 'action="/run/inputs"'
    assert_equal 302, changed.status
    assert_includes after, "<code>NAME=after</code>"
    assert_equal "after", @session.current.inputs["NAME"]
  end

  def test_session_page_before_any_runbook
    body = get("/session").body
    assert last_response.ok?
    assert_includes body, "Session #{@session.id}"
    assert_includes body, "testing", "the why is the first note"
    assert_includes body, "No runbook selected yet"
    assert_includes body, 'action="/session/end"'
  end

  def test_session_notes
    added = post "/session/notes", { "_token" => "tok", "note" => "found the cause" }
    blank = post "/session/notes", { "_token" => "tok", "note" => "  " }
    start_run
    page = get("/session").body
    assert_equal 302, added.status
    assert_equal 422, blank.status
    assert_includes blank.body, "A note needs some text.", "the session page again, with the error"
    assert_includes page, "found the cause"
    assert_includes page, "opened so far"
    assert_includes page, "[session] note: found the cause", "the log tail"
  end

  def test_ending_the_session
    start_run
    ended  = post "/session/end", { "_token" => "tok" }
    home   = get "/"
    record = get "/session"
    assert ended.ok?
    assert_includes ended.body, "Session ended"
    assert_equal 1, @stopper.calls, "the server is asked to stop"
    assert @session.ended?
    assert_equal "opened", @session.current.record.status
    assert_equal 410, home.status
    assert record.ok?, "the record can still be read"
  end

  def test_marking_a_document_that_is_not_a_step_is_refused
    start_run
    runbook = post "/steps/runbook/mark", { "_token" => "tok", "status" => "done" }
    verify  = post "/steps/verify/mark", { "_token" => "tok", "status" => "done" }
    assert_equal 422, runbook.status
    assert_equal 422, verify.status
    assert_equal 0, @session.run.steps_done
  end
end
