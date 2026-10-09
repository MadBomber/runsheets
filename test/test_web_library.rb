# frozen_string_literal: true

require "test_helper"
require "rack/test"

# The server started on a directory of runbooks: the chooser, opening one,
# and switching.
class TestWebLibrary < Minitest::Test
  include Rack::Test::Methods
  include RunsheetsTest

  EXAMPLES = File.expand_path("../examples", __dir__)

  def setup
    @runs_root = Dir.mktmpdir("runsheets-web")
    Runsheets.runs_dir = @runs_root # sessions opened from the library default to this
    @library = Runsheets::Library.load(EXAMPLES)
    Runsheets::Web.configure_for(nil, library: @library)
    Runsheets::Web.set :rs_token, "tok"
    header "Host", "localhost"
  end

  def teardown
    Runsheets::Web.configure_for(Runsheets::Session.new(runbook: example_runbook, runs_root: @runs_root, token: "tok"))
    Runsheets.runs_dir = nil
    FileUtils.rm_rf(@runs_root)
  end

  def app = Runsheets::Web

  def with_token = header("X-Runsheets-Token", "tok")

  def open_runbook(slug) = post("/library/open", "_token" => "tok", "slug" => slug)

  def test_the_chooser_lists_every_runbook_and_nothing_is_open_yet
    get "/library"
    assert last_response.ok?
    body = last_response.body
    %w[db-maintenance hello staging-teardown].each { assert_includes body, "data-slug=\"#{it}\"" }
    assert_includes body, "Monthly PostgreSQL maintenance"
    assert_includes body, "single file"
    assert_includes body, "3 runbooks in"
    assert_includes body, "no runbook open"
    assert_includes body, 'name="slug" value="hello"'
    assert_equal 3, body.scan(" Open</button>").size
    assert_includes last_response.headers["Content-Security-Policy"], "nonce-"
  end

  def test_everything_else_redirects_to_the_chooser_until_a_runbook_is_open
    get "/"
    assert_equal 302, last_response.status
    assert_match %r{/library\z}, last_response.headers["Location"]
    get "/steps/010-say-hello"
    assert_equal 302, last_response.status
  end

  def test_opening_a_runbook_serves_it_and_the_header_links_back
    open_runbook("hello")
    assert_equal 302, last_response.status
    assert_match %r{/\z}, last_response.headers["Location"]
    assert_same @library, Runsheets::Web.session.library
    assert_equal "tok", Runsheets::Web.session.token, "the token carries over"

    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "Hello, runsheets"
    assert_includes last_response.body, 'href="/library"'

    get "/library"
    assert_includes last_response.body, ">current<"
    assert_includes last_response.body, "Continue"
    assert_equal 2, last_response.body.scan(" Open</button>").size
  end

  def test_switching_runbooks_and_single_file_runbooks_open_too
    open_runbook("hello")
    open_runbook("db-maintenance")
    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "Monthly PostgreSQL maintenance"
    assert Runsheets::Web.session.runbook.single_file?
  end

  def test_opening_needs_the_token_and_a_known_slug
    post "/library/open", "slug" => "hello"
    assert_equal 403, last_response.status
    assert_nil Runsheets::Web.session
    open_runbook("nope")
    assert_equal 404, last_response.status
    assert_nil Runsheets::Web.session
  end

  def test_switching_is_refused_while_a_run_is_active
    open_runbook("hello")
    with_token
    post "/run", "_token" => "tok"
    assert_equal 302, last_response.status
    assert Runsheets::Web.session.active?

    open_runbook("db-maintenance")
    assert_equal 409, last_response.status
    assert_equal "hello", Runsheets::Web.session.runbook.slug

    get "/library"
    assert_includes last_response.body, "finish the active run"
    assert_equal 0, last_response.body.scan(" Open</button>").size
  ensure
    Runsheets::Web.session&.abandon_if_active
  end

  def test_the_chooser_is_404_when_serving_one_runbook
    Runsheets::Web.configure_for(Runsheets::Session.new(runbook: example_runbook, runs_root: @runs_root, token: "tok"))
    get "/library"
    assert_equal 404, last_response.status
    get "/"
    assert last_response.ok?
    refute_includes last_response.body, 'href="/library"'
  end
end
