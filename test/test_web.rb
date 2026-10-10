# frozen_string_literal: true

require "test_helper"
require "rack/test"

class TestWeb < Minitest::Test
  include Rack::Test::Methods
  include RunsheetsTest

  def setup
    @runs_root = Dir.mktmpdir("runsheets-web")
    @session   = start_session(@runs_root)
    Runsheets::Web.configure_for(@session)
    @stopper = StopCounter.new(0)
    Runsheets::Web.set :rs_stopper, @stopper
    header "Host", "localhost"
  end

  def teardown
    @session&.end!("teardown")
    Runsheets::Web.set :rs_stopper, nil
    FileUtils.rm_rf(@runs_root)
  end

  # Point the app at a session on +runbook+ instead.
  def serve(runbook)
    @session&.end!("switching")
    @session = start_session(@runs_root, runbook:)
    Runsheets::Web.configure_for(@session)
  end

  def app = Runsheets::Web

  def with_token = header("X-Runsheets-Token", "tok")

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
    get "/steps/010-say-hello"
    assert_includes last_response.body, 'data-action="execute" data-locked disabled title="Start a run to execute blocks"'
    get "/steps/020-inspect-ruby"
    assert_includes last_response.body, 'data-action="acknowledge" data-locked disabled title="Start a run to confirm terminal blocks"'

    post "/runs", { "_token" => "tok" }
    get "/steps/010-say-hello"
    assert_includes last_response.body, 'data-action="execute"'
    refute_includes last_response.body, "data-locked disabled"
  end

  def with_linked_document
    files = {
      "runbook.md" => "---\ntitle: Linked\n---\nSee the [glossary](docs/glossary.md) and [step one](steps/010-a.md).\n",
      "steps/010-a.md" => "---\ntitle: A\nkind: manual\n---\nBack to the [glossary](../docs/glossary.md#terms).\n",
      "docs/glossary.md" => "# Glossary\n\n```bash run\nrm -rf /\n```\n\n![diagram](flow.svg)\n",
      "docs/flow.svg" => "<svg/>",
      "notes.txt" => "plain"
    }
    with_runbook(files) do |rb|
      serve(rb)
      yield rb
    end
  end

  def test_links_to_plain_markdown_render_it_as_a_document
    with_linked_document do
      get "/"
      assert_includes last_response.body, 'href="/docs/docs/glossary.md"'
      get "/steps/010-a"
      assert_includes last_response.body, 'href="/docs/docs/glossary.md#terms"'

      get "/docs/docs/glossary.md"
      assert last_response.ok?
      body = last_response.body
      assert_includes body, "<title>Glossary · Linked</title>"
      assert_includes body, "nothing here executes"
      refute_match(/<button[^>]*data-action="execute"/, body, "a document has no Run buttons")
      assert_includes body, 'src="/files/docs/flow.svg"', "its own relative links resolve from its folder"
    end
  end

  def test_a_link_to_one_of_the_runbooks_own_files_goes_to_its_page
    with_linked_document do
      get "/docs/steps/010-a.md"
      assert_equal 302, last_response.status
      assert_match %r{/steps/010-a\z}, last_response.location
      get "/docs/runbook.md"
      assert_equal 302, last_response.status
      assert_match %r{://[^/]+/\z}, last_response.location
    end
  end

  def test_docs_route_serves_only_markdown_inside_the_runbook
    with_linked_document do
      get "/docs/notes.txt"
      assert_equal 404, last_response.status
      get "/docs/../../etc/passwd.md"
      assert_equal 404, last_response.status
      get "/docs/missing.md"
      assert_equal 404, last_response.status
    end
  end

  def test_search_on_a_single_runbook_searches_that_runbook
    get "/search", "q" => "greeting"
    assert last_response.ok?
    assert_includes last_response.body, "1 runbook match"
    assert_includes last_response.body, 'href="/steps/045-check-the-greeting"'
    assert_includes last_response.body, 'class="rs-search"', "the header has the search box"
  end

  def test_extras_and_rollback_sidebar
    get "/steps/020-inspect-ruby"
    assert_includes last_response.body, "<summary>Rollback</summary>"
    assert_includes last_response.body, "nothing to undo"
    get "/steps/verify"
    assert last_response.ok?
  end

  def test_unknown_step_is_404
    get "/steps/nope"
    assert_equal 404, last_response.status
  end

  def test_host_header_is_enforced
    header "Host", "evil.example.com"
    get "/"
    assert_equal 403, last_response.status
  end

  def test_post_without_token_is_refused
    post "/runs"
    assert_equal 403, last_response.status
    post "/blocks/010-say-hello-1/execute"
    assert_equal 403, last_response.status
    assert_equal "application/json", last_response.media_type
  end

  def test_execute_requires_a_run
    with_token
    post "/blocks/010-say-hello-1/execute"
    assert_equal 409, last_response.status
    assert_match(/start the run for Hello, runsheets/, JSON.parse(last_response.body)["error"])
  end

  def test_start_run_execute_poll_and_mark
    post "/runs", { "_token" => "tok", "inputs" => { "NAME" => "web" } }
    assert_equal 302, last_response.status
    assert_match %r{://[^/]+/\z}, last_response.location, "lands on the runbook page"
    assert @session.active?

    get "/"
    assert_includes last_response.body, "Run open"
    assert_includes last_response.body, "Work through the steps"
    refute_includes last_response.body, "/run/finish"
    assert_includes last_response.body, "<code>NAME=web</code>"
    refute_includes last_response.body, "hunter2"

    with_token
    post "/blocks/010-say-hello-1/execute"
    assert_equal 202, last_response.status
    id = JSON.parse(last_response.body)["id"]

    data = nil
    wait_for do
      get "/executions/#{id}"
      data = JSON.parse(last_response.body)
      data["state"] != "running"
    end
    assert_equal "finished", data["state"]
    assert_equal 0, data["exit_status"]
    assert data["success"]
    assert_includes data["output"], "Hello, web!"

    get "/steps/010-say-hello"
    assert_includes last_response.body, 'id="rs-prior"'
    assert_includes last_response.body, "Hello, web!"
    assert_includes last_response.body, "Mark done and continue"

    post "/steps/010-say-hello/mark", { "_token" => "tok", "status" => "done", "note" => "fine" }
    assert_equal 302, last_response.status
    assert_match %r{/steps/020-inspect-ruby\z}, last_response.location

    get "/run"
    assert last_response.ok?
    assert_includes last_response.body, "marked done"

    get "/"
    refute_includes last_response.body, "Previous runs", "the open run is not history yet"
    get "/runs/#{@session.run.id}"
    assert last_response.ok?
    assert_includes last_response.body, "running"
    assert_includes File.read(@session.log.path), "[hello 010-say-hello] marked done: fine"
  end

  def test_destructive_block_needs_the_servers_confirmation_code
    post "/runs", { "_token" => "tok" }
    with_token
    post "/blocks/040-exercise-failure-1/execute"
    assert_equal 428, last_response.status
    body = JSON.parse(last_response.body)
    assert_match(/\A[0-9a-f]{4}\z/, body["challenge"])
    assert_equal "040-exercise-failure-1", body["block_id"]

    post "/blocks/040-exercise-failure-1/execute", { "confirm" => "nope" }
    assert_equal 428, last_response.status
    assert_equal body["challenge"], JSON.parse(last_response.body)["challenge"], "the same code until it is used"

    post "/blocks/040-exercise-failure-1/execute", { "confirm" => body["challenge"] }
    assert_equal 202, last_response.status
    id = JSON.parse(last_response.body)["id"]
    wait_for do
      get "/executions/#{id}"
      JSON.parse(last_response.body)["state"] != "running"
    end
    assert_equal 3, JSON.parse(last_response.body)["exit_status"]
  end

  def test_background_start_stop_and_running_panel
    post "/runs", { "_token" => "tok" }
    get "/steps/035-keep-a-clock-running"
    assert_includes last_response.body, ">Start</button>"
    assert_includes last_response.body, 'data-action="stop"'
    refute_includes last_response.body, 'id="rs-running"'

    with_token
    post "/blocks/035-keep-a-clock-running-1/execute"
    assert_equal 202, last_response.status
    data = JSON.parse(last_response.body)
    assert data["background"]
    id = data["id"]

    get "/"
    assert_includes last_response.body, 'id="rs-running"'
    assert_includes last_response.body, "data-execution=\"#{id}\""

    post "/executions/#{id}/stop"
    assert_equal 202, last_response.status
    wait_for do
      get "/executions/#{id}"
      JSON.parse(last_response.body)["state"] != "running"
    end
    assert_equal "stopped", JSON.parse(last_response.body)["state"]

    get "/"
    refute_includes last_response.body, 'id="rs-running"'
    post "/executions/nope/stop"
    assert_equal 409, last_response.status
  end

  def test_acknowledge_terminal_block
    post "/runs", { "_token" => "tok" }
    get "/steps/020-inspect-ruby"
    assert_includes last_response.body, 'data-action="acknowledge"'

    with_token
    post "/blocks/020-inspect-ruby-3/acknowledge", { "note" => "done" }
    assert_equal 201, last_response.status
    ack = JSON.parse(last_response.body)
    assert_equal "done", ack["note"]
    assert_equal "020-inspect-ruby-3", ack["block_id"]

    get "/steps/020-inspect-ruby"
    assert_includes last_response.body, '"acks":{"020-inspect-ruby-3"'

    post "/blocks/020-inspect-ruby-1/acknowledge"
    assert_equal 409, last_response.status
  end

  def test_expect_block_is_linked_to_the_block_above_it
    get "/steps/010-say-hello"
    assert_includes last_response.body, 'data-expect-for="010-say-hello-1"'
    assert_includes last_response.body, 'data-role="expected"'
  end

  def test_active_run_panel_shows_secrets_as_set_without_values
    post "/runs", { "_token" => "tok", "inputs" => { "SECRET_WORD" => "swordfish" } }
    get "/"
    assert_includes last_response.body, "SECRET_WORD=•••"
    refute_includes last_response.body, "swordfish", "not even in the change form"
    assert_includes last_response.body, "leave blank to keep the current value"
  end

  def test_checks_run_inside_the_run
    get "/verify"
    assert last_response.ok?
    assert_includes last_response.body, "No run for this runbook yet"
    assert_includes last_response.body, 'data-block="045-check-the-greeting-1"'
    assert_includes last_response.body, 'data-block="verify-2"'
    refute_includes last_response.body, '<button type="button" class="btn primary" data-action="run-all"'

    post "/runs", { "_token" => "tok" }
    get "/"
    assert_includes last_response.body, "Go to checks (3)"
    get "/verify"
    assert_includes last_response.body, '<button type="button" class="btn primary" data-action="run-all"'
    assert_includes last_response.body, "Run all 3 checks"

    with_token
    post "/blocks/verify-1/execute"
    assert_equal 202, last_response.status
    post "/blocks/010-say-hello-1/execute"
    assert_equal 202, last_response.status, "every step runs in the one run"
  end

  def test_run_page_shows_drift_when_the_runbook_changed
    Dir.mktmpdir("runsheets-drift") do |dir|
      FileUtils.cp_r(File.join(RunsheetsTest::EXAMPLE_DIR, "."), dir)
      serve(Runsheets::Runbook.load(dir))
      post "/runs", { "_token" => "tok" }
      with_token
      post "/blocks/010-say-hello-1/execute"
      id = JSON.parse(last_response.body)["id"]
      wait_for do
        get "/executions/#{id}"
        JSON.parse(last_response.body)["state"] != "running"
      end
      @session.current.close!

      get "/runs/#{@session.run.id}"
      refute_includes last_response.body, "Runbook changed since this run"

      path = File.join(dir, "steps", "010-say-hello.md")
      File.write(path, File.read(path).sub('echo "Hello, $NAME!"', 'echo "Howdy, $NAME!"'))
      assert @session.runbook.stale?
      get "/runs/#{@session.run.id}"
      assert_includes last_response.body, "Runbook changed since this run"
      assert_includes last_response.body, "-echo &quot;Hello, $NAME!&quot;"
      assert_includes last_response.body, "+echo &quot;Howdy, $NAME!&quot;"
      get "/"
      assert_includes last_response.body, "stopped at 010-say-hello"
    end
  end

  def test_unknown_execution_is_404_json
    with_token
    get "/executions/nope"
    assert_equal 404, last_response.status
    assert_equal "application/json", last_response.media_type
  end

  def test_files_route_serves_runbook_files_but_not_traversal
    get "/files/runbook.md"
    assert last_response.ok?
    assert_includes last_response.body, "title: Hello, runsheets"
    get "/files/../../Gemfile"
    assert_equal 404, last_response.status
    get "/files/.git/config"
    assert_equal 404, last_response.status
  end

  def test_bad_run_id
    get "/runs/..%2F..%2Fetc"
    assert_equal 404, last_response.status
  end

  def test_pages_carry_a_csp_nonce_and_are_not_cached
    get "/"
    csp = last_response.headers["Content-Security-Policy"]
    nonce = csp[/script-src 'nonce-([^']+)'/, 1]
    refute_nil nonce
    assert_includes csp, "style-src 'nonce-#{nonce}'"
    assert_includes csp, "object-src 'none'"
    assert_includes last_response.body, "<script nonce=\"#{nonce}\">"
    assert_includes last_response.body, "<style nonce=\"#{nonce}\">"
    assert_equal "no-store", last_response.headers["Cache-Control"]

    get "/"
    refute_equal nonce, last_response.headers["Content-Security-Policy"][/nonce-([^']+)/, 1], "a nonce per response"

    header "Accept", "text/html"
    get "/steps/nope"
    assert_equal 404, last_response.status
    assert_match(/nonce-/, last_response.headers["Content-Security-Policy"], "error pages too")
  end

  def test_script_in_runbook_markdown_renders_without_the_nonce
    with_runbook("runbook.md" => "---\ntitle: T\n---\n<script>document.title='x'</script>\n", "steps/010-a.md" => "hi\n") do |rb|
      serve(rb)
      get "/"
      assert_includes last_response.body, "<script>document.title='x'</script>"
      assert_equal 1, last_response.body.scan('<script nonce=').size
    end
  end

  def test_files_route_does_not_follow_symlinks_out_of_the_runbook
    Dir.mktmpdir("runsheets-link") do |dir|
      FileUtils.cp_r(File.join(RunsheetsTest::EXAMPLE_DIR, "."), dir)
      File.symlink("/etc/hosts", File.join(dir, "outside"))
      File.symlink(File.join(dir, "runbook.md"), File.join(dir, "inside"))
      serve(Runsheets::Runbook.load(dir))
      get "/files/outside"
      assert_equal 404, last_response.status
      get "/files/inside"
      assert last_response.ok?, "a link that stays inside the runbook is fine"
      assert_includes last_response.body, "title: Hello, runsheets"
    end
  end

  def test_permitted_hosts_follow_the_bind_address
    assert Runsheets::Web.wildcard?("0.0.0.0")
    assert Runsheets::Web.wildcard?("::")
    refute Runsheets::Web.wildcard?("127.0.0.1")
    assert Runsheets::Web.loopback?("127.0.0.1")
    assert Runsheets::Web.loopback?("::1")
    refute Runsheets::Web.loopback?("0.0.0.0")
    refute Runsheets::Web.loopback?("192.168.1.5")

    Runsheets::Web.configure_for(@session, bind: "0.0.0.0")
    header "Host", "192.168.1.20"
    get "/"
    assert last_response.ok?, "a wildcard bind answers any host"

    Runsheets::Web.configure_for(@session, bind: "192.168.1.5")
    get "/"
    assert_equal 403, last_response.status
    header "Host", "192.168.1.5"
    get "/"
    assert last_response.ok?
    header "Host", "localhost"
    get "/"
    assert last_response.ok?, "loopback names always work"
  ensure
    Runsheets::Web.configure_for(@session)
  end

  def test_changing_inputs_partway
    post "/runs", { "_token" => "tok", "inputs" => { "NAME" => "before" } }
    get "/"
    assert_includes last_response.body, 'action="/run/inputs"'
    post "/run/inputs", { "_token" => "tok", "inputs" => { "NAME" => "after" } }
    assert_equal 302, last_response.status
    get "/"
    assert_includes last_response.body, "<code>NAME=after</code>"
    assert_equal "after", @session.current.inputs["NAME"]
  end

  def test_session_page_notes_and_ending
    get "/session"
    assert last_response.ok?
    body = last_response.body
    assert_includes body, "Session #{@session.id}"
    assert_includes body, "testing", "the why is the first note"
    assert_includes body, "No runbook selected yet"
    assert_includes body, 'action="/session/end"'

    post "/session/notes", { "_token" => "tok", "note" => "found the cause" }
    assert_equal 302, last_response.status
    post "/session/notes", { "_token" => "tok", "note" => "  " }
    assert_equal 422, last_response.status
    assert_includes last_response.body, "A note needs some text.", "the session page again, with the error"
    post "/runs", { "_token" => "tok" }
    get "/session"
    assert_includes last_response.body, "found the cause"
    assert_includes last_response.body, "opened so far"
    assert_includes last_response.body, "[session] note: found the cause", "the log tail"

    post "/session/end", { "_token" => "tok" }
    assert last_response.ok?
    assert_includes last_response.body, "Session ended"
    assert_equal 1, @stopper.calls, "the server is asked to stop"
    assert @session.ended?
    assert_equal "opened", @session.current.record.status
    get "/"
    assert_equal 410, last_response.status
    get "/session"
    assert last_response.ok?, "the record can still be read"
  end

  def test_marking_a_document_that_is_not_a_step_is_refused
    post "/runs", { "_token" => "tok" }
    post "/steps/runbook/mark", { "_token" => "tok", "status" => "done" }
    assert_equal 422, last_response.status
    post "/steps/verify/mark", { "_token" => "tok", "status" => "done" }
    assert_equal 422, last_response.status
    assert_equal 0, @session.run.steps_done
  end
end
