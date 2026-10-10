# frozen_string_literal: true

require "test_helper"
require "rack/test"

# The server started on a directory of runbooks: the tree, the detail
# pane, opening one, and switching.
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

  def test_the_home_page_shows_the_tree_and_the_root_folder_with_nothing_open_yet
    get "/library"
    assert last_response.ok?
    body = last_response.body
    %w[db-maintenance disk-space-triage hello staging-teardown].each { assert_includes body, "data-slug=\"#{it}\"" }
    assert_includes body, 'href="/library/hello"'
    assert_includes body, "Monthly PostgreSQL maintenance"
    assert_includes body, "4 runbooks"
    assert_includes body, "no runbook open"
    assert_includes body, 'id="lib-filter"'
    assert_includes body, 'name="slug" value="hello"'
    assert_equal 4, body.scan(" Open</button>").size, "a card per runbook, each with Open"
    refute_includes body, 'data-key="o"', "the o key belongs to the detail pane, not a card"
    assert_includes last_response.headers["Content-Security-Policy"], "nonce-"
  end

  def test_selecting_a_runbook_shows_its_details_and_the_open_button
    get "/library/hello"
    assert last_response.ok?
    body = last_response.body
    assert_includes body, "<title>Hello, runsheets · runsheets</title>"
    assert_includes body, 'class="tree-runbook ready active'
    assert_includes body, "When to use"
    assert_includes body, "Prerequisites"
    assert_includes body, "$NAME"
    assert_includes body, "Say hello"
    assert_includes body, 'data-key="o"'
    assert_equal 1, body.scan(" Open</button>").size
    assert_includes body, '<span class="current">Hello, runsheets</span>'
  end

  def test_everything_else_redirects_to_the_library_until_a_runbook_is_open
    get "/"
    assert_equal 302, last_response.status
    assert_match %r{/library\z}, last_response.headers["Location"]
    get "/steps/010-say-hello"
    assert_equal 302, last_response.status
    get "/library/nope"
    assert_equal 404, last_response.status
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
    assert_includes last_response.body, "Continue"
    assert_includes last_response.body, "Back to runbook"
    assert_equal 3, last_response.body.scan(" Open</button>").size
    get "/library/hello"
    assert_includes last_response.body, ">open now<"
    assert_includes last_response.body, 'class="tree-runbook current active'
  end

  def test_plain_documents_anywhere_in_the_library_open_from_any_runbook
    open_runbook("hello")
    get "/"
    assert_includes last_response.body, 'href="/docs/about-the-examples.md"', "a runbook directory links one level up"

    get "/docs/about-the-examples.md"
    assert last_response.ok?
    assert_includes last_response.body, "<title>About these examples · Hello, runsheets</title>"
    assert_includes last_response.body, 'href="/docs/policies/cleanup-policy.md"'

    get "/docs/policies/cleanup-policy.md"
    assert last_response.ok?
    assert_includes last_response.body, 'src="/files/policies/images/triage-flow.svg"'
    get "/files/policies/images/triage-flow.svg"
    assert last_response.ok?

    get "/docs/disk-space-triage.md"
    assert_equal 302, last_response.status
    assert_match %r{/library/disk-space-triage\z}, last_response.location, "another runbook opens in the library"
    get "/docs/hello/steps/010-say-hello.md"
    assert_match %r{/steps/010-say-hello\z}, last_response.location, "the open runbook's own step"
  end

  def test_search_works_before_a_runbook_is_open_and_links_into_the_library
    get "/search", "q" => "vacuum"
    assert last_response.ok?
    body = last_response.body
    assert_includes body, "<title>Search · runsheets</title>"
    assert_includes body, "1 runbook match <strong>vacuum</strong>"
    assert_includes body, 'href="/library/db-maintenance"'
    assert_match %r{href="/library/db-maintenance#step-\d+-[a-z-]+"}, body, "a numbered step links to its row"
    assert_includes body, "<mark>"
    assert_includes body, 'id="lib-tree-nav"', "results sit beside the tree"
    assert_includes body, 'value="vacuum"', "the header box keeps the query"

    get "/library/db-maintenance"
    assert_match(/<li id="step-\d+-[a-z-]+">/, last_response.body, "step rows carry the anchors")
  end

  def test_search_links_the_open_runbook_straight_to_its_steps
    open_runbook("disk-space-triage")
    get "/search", "q" => "threshold"
    assert_includes last_response.body, "open now"
    assert_includes last_response.body, 'href="/steps/verify"'
  end

  def test_search_with_no_query_or_no_match
    get "/search"
    assert last_response.ok?
    assert_includes last_response.body, "Search the text of every runbook"
    get "/search", "q" => "zzzz-not-there"
    assert_includes last_response.body, "0 runbooks match"
    assert_includes last_response.body, "No runbook contains every word"
  end

  def test_query_is_escaped
    get "/search", "q" => "<script>alert(1)</script>"
    refute_includes last_response.body, "<script>alert(1)</script>"
    assert_includes last_response.body, "&lt;script&gt;"
  end

  def test_plain_documents_stay_out_of_the_tree
    get "/library"
    %w[about-the-examples disk-usage-glossary policies].each { refute_includes last_response.body, "data-slug=\"#{it}\"" }
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

    get "/library/db-maintenance"
    assert_includes last_response.body, "Finish or abandon it"
    assert_includes last_response.body, "Finish the active run first"
    assert_equal 0, last_response.body.scan(" Open</button>").size
  ensure
    Runsheets::Web.session&.abandon_if_active
  end

  def test_the_library_is_404_when_serving_one_runbook
    Runsheets::Web.configure_for(Runsheets::Session.new(runbook: example_runbook, runs_root: @runs_root, token: "tok"))
    get "/library"
    assert_equal 404, last_response.status
    get "/library/hello"
    assert_equal 404, last_response.status
    get "/"
    assert last_response.ok?
    refute_includes last_response.body, 'href="/library"'
  end
end

# A nested library: folders in the tree, slugs that are paths, run records
# filed under them.
class TestWebNestedLibrary < Minitest::Test
  include Rack::Test::Methods
  include RunsheetsTest

  def setup
    @runs_root = Dir.mktmpdir("runsheets-web")
    @dir       = Dir.mktmpdir("runsheets-nested")
    Runsheets.runs_dir = @runs_root
    write("README.md", "# Ops\n\nThe **root** readme.\n")
    write("deploy.md", single("Deploy"))
    write("platform/README.md", "Platform things.\n")
    write("platform/database/backup/runbook.md", "---\ntitle: Backup the database\nwhen_to_use: Nightly.\n---\n\nPreamble here.\n")
    write("platform/database/backup/steps/010-dump.md", "---\ntitle: Dump\nkind: manual\n---\nDo it.\n")
    write("platform/network/backup.md", single("Backup the routers"))
    write("platform/broken.md", "---\ntitle: [oops\n---\n")
    @library = Runsheets::Library.load(@dir)
    Runsheets::Web.configure_for(nil, library: @library)
    Runsheets::Web.set :rs_token, "tok"
    header "Host", "localhost"
  end

  def teardown
    Runsheets::Web.session&.abandon_if_active
    Runsheets::Web.configure_for(Runsheets::Session.new(runbook: example_runbook, runs_root: @runs_root, token: "tok"))
    Runsheets.runs_dir = nil
    FileUtils.rm_rf(@runs_root)
    FileUtils.rm_rf(@dir)
  end

  def app = Runsheets::Web

  def single(title) = "---\ntitle: #{title}\n---\n\n## Only step\n<!-- kind: manual -->\n\nDo it.\n"

  def write(rel, text)
    path = File.join(@dir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  def open_runbook(slug) = post("/library/open", "_token" => "tok", "slug" => slug)

  def test_the_root_shows_the_readme_folder_cards_and_the_whole_tree
    get "/library"
    body = last_response.body
    assert_includes body, "<strong>root</strong>"
    assert_includes body, "4 runbooks in 3 folders"
    assert_includes body, 'class="lib-card folder" href="/library/platform"'
    assert_includes body, 'data-slug="platform/database/backup"'
    assert_includes body, 'href="/library/platform/network/backup"'
    assert_includes body, "<details open>", "the first level is open"
    assert_includes body, 'data-search="backup backup the routers platform/network/backup"'
    assert_includes body, 'class="tree-runbook broken"'
  end

  def test_selecting_a_folder_shows_its_readme_and_contents_with_crumbs
    get "/library/platform"
    body = last_response.body
    assert last_response.ok?
    assert_includes body, "Platform things."
    assert_includes body, "3 runbooks in 2 folders"
    assert_includes body, '<a href="/library">Runbooks</a>'
    assert_includes body, '<span class="current">platform</span>'
    assert_includes body, 'href="/library/platform/database"'
    assert_includes body, "does not load"
    assert_includes body, "not valid YAML"
    get "/library/platform/"
    assert last_response.ok?, "a trailing slash is fine"
  end

  def test_selecting_a_nested_runbook_expands_its_folders_and_shows_the_crumbs
    get "/library/platform/database/backup"
    body = last_response.body
    assert last_response.ok?
    assert_includes body, "Backup the database"
    assert_includes body, "Nightly."
    assert_includes body, "Preamble here."
    assert_includes body, '<a href="/library/platform">platform</a>'
    assert_includes body, '<a href="/library/platform/database">database</a>'
    assert_includes body, '<span class="current">Backup the database</span>'
    assert_includes body, 'name="slug" value="platform/database/backup"'
    network = body[%r{data-slug="platform/network".*?<details[^>]*>}m]
    refute_includes network, "open", "a sibling folder stays folded"
  end

  def test_opening_a_nested_runbook_carries_its_path_slug_into_the_session_and_run_records
    open_runbook("platform/database/backup")
    assert_equal 302, last_response.status
    session = Runsheets::Web.session
    assert_equal "platform/database/backup", session.runbook.slug

    get "/"
    body = last_response.body
    assert last_response.ok?
    assert_includes body, '<a href="/library" title="Runbooks [r]">Runbooks</a>'
    assert_includes body, '<a href="/library/platform">platform</a>'
    assert_includes body, '<a href="/library/platform/database">database</a>'

    header "X-Runsheets-Token", "tok"
    post "/run", "_token" => "tok"
    assert_equal 302, last_response.status
    assert_equal File.join(@runs_root, "platform/database/backup"), File.dirname(session.run.dir)
    assert_equal "platform/database/backup", session.run.runbook_slug
    post "/run/finish", "_token" => "tok", "status" => "completed"

    get "/library/platform/database/backup"
    assert_includes last_response.body, "Previous runs"
    assert_includes last_response.body, session.run.id
    assert_includes last_response.body, ">open now<"
  end

  def test_a_runbook_added_while_serving_appears_on_the_next_visit
    get "/library"
    refute_includes last_response.body, "Late arrival"
    write("platform/late.md", single("Late arrival"))
    get "/library/platform"
    assert_includes last_response.body, "Late arrival"
    assert_includes last_response.body, 'href="/library/platform/late"'
  end
end
