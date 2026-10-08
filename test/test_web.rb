# frozen_string_literal: true

require "test_helper"
require "rack/test"

class TestWeb < Minitest::Test
  include Rack::Test::Methods
  include RunsheetsTest

  def setup
    @runs_root = Dir.mktmpdir("runsheets-web")
    @session   = Runsheets::Session.new(runbook: example_runbook, runs_root: @runs_root, token: "tok")
    Runsheets::Web.configure_for(@session)
    header "Host", "localhost"
  end

  def teardown
    FileUtils.rm_rf(@runs_root)
  end

  def app = Runsheets::Web

  def with_token = header("X-Runsheets-Token", "tok")

  def test_landing_page
    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "Hello, runsheets"
    assert_includes last_response.body, 'name="inputs[NAME]"'
    assert_includes last_response.body, 'type="password"'
    assert_includes last_response.body, "no active run"
  end

  def test_step_page_shows_blocks_and_run_buttons
    get "/steps/010-say-hello"
    assert last_response.ok?
    assert_includes last_response.body, 'data-block="010-say-hello-1"'
    assert_includes last_response.body, 'data-action="execute"'
    assert_includes last_response.body, "No active run"
    assert_includes last_response.body, '<meta name="rs-token" content="tok">'
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
    post "/run"
    assert_equal 403, last_response.status
    post "/blocks/010-say-hello-1/execute"
    assert_equal 403, last_response.status
    assert_equal "application/json", last_response.media_type
  end

  def test_execute_requires_a_run
    with_token
    post "/blocks/010-say-hello-1/execute"
    assert_equal 409, last_response.status
    assert_match(/start a run/, JSON.parse(last_response.body)["error"])
  end

  def test_start_run_execute_poll_mark_and_finish
    post "/run", { "_token" => "tok", "inputs" => { "NAME" => "web" } }
    assert_equal 302, last_response.status
    assert_match %r{/steps/010-say-hello\z}, last_response.location
    assert @session.active?

    get "/"
    assert_includes last_response.body, "Active run"
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

    post "/run/finish", { "_token" => "tok", "status" => "completed" }
    assert_equal 302, last_response.status
    refute @session.active?

    get "/"
    assert_includes last_response.body, "Previous runs"
    get "/runs/#{@session.run.id}"
    assert last_response.ok?
    assert_includes last_response.body, "completed"
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
end
