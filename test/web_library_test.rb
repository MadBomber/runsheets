# frozen_string_literal: true

require "test_helper"
require "rack/test"

# The server started on a directory of runbooks: the tree, the detail
# pane, opening one, and switching.
class TestWebLibrary < Minitest::Test
  include Rack::Test::Methods
  include RunsheetsTest
  include RunsheetsTest::WebLibraryFixtures

  def setup = serve_examples_library

  def teardown = stop_library_server

  def app = Runsheets::Web

  def test_before_the_session_starts_everything_goes_to_the_start_page
    restart_without_session
    library = get "/library"
    form    = get "/session/new"
    refused = post "/runs", "_token" => "tok", "slug" => "hello"
    assert_match %r{/session/new\z}, library.location
    assert form.ok?
    assert_includes form.body, 'value="Prefilled"', "the engineer is prefilled"
    assert_equal 409, refused.status
  end

  def test_starting_the_session_leads_to_the_library_once_per_process
    restart_without_session
    started = post "/session", "_token" => "tok", "engineer" => "Ada", "why" => "nightly checks"
    again   = get "/session/new"
    assert_match %r{/library\z}, started.location
    assert_equal "Ada", Runsheets::Web.session.engineer
    assert_equal "nightly checks", Runsheets::Web.session.why
    assert_match %r{/session\z}, again.location, "one session per process"
  end

  def test_the_home_page_shows_the_tree_and_the_root_folder_with_nothing_open_yet
    body = get("/library").body
    %w[db-maintenance disk-space-triage hello staging-teardown].each { assert_includes body, "data-slug=\"#{it}\"" }
    assert_includes body, 'href="/library/hello"'
    assert_includes body, "Monthly PostgreSQL maintenance"
    assert_includes body, "4 runbooks"
    assert_includes body, 'id="lib-filter"'
  end

  def test_the_home_page_has_a_card_per_runbook_and_the_session_header
    response = get "/library"
    body = response.body
    assert response.ok?
    assert_includes body, ">Tester · ", "the session in the header"
    assert_equal 4, body.scan(" Open</a>").size, "a card per runbook, each leading to its pane and inputs"
    refute_includes body, 'data-key="o"', "the o key belongs to the detail pane, not a card"
    assert_includes response.headers["Content-Security-Policy"], "nonce-"
  end

  def test_selecting_a_runbook_shows_its_details
    response = get "/library/hello"
    body = response.body
    assert response.ok?
    assert_includes body, "<title>Hello, runsheets · runsheets</title>"
    assert_includes body, 'class="tree-runbook ready active'
    assert_includes body, "When to use"
    assert_includes body, "Prerequisites"
    assert_includes body, "$NAME"
    assert_includes body, "Say hello"
    assert_includes body, '<span class="current">Hello, runsheets</span>'
  end

  def test_selecting_a_runbook_shows_the_open_button_and_its_inputs_form
    body = get("/library/hello").body
    assert_includes body, 'data-key="o"'
    assert_equal 1, body.scan(" Start run</button>").size
    assert_includes body, 'name="inputs[NAME]"', "the pane carries the inputs form"
    assert_includes body, 'name="slug" value="hello"'
  end

  def test_runbook_pages_redirect_to_the_library_until_a_runbook_is_open
    home    = get "/"
    step    = get "/steps/010-say-hello"
    unknown = get "/library/nope"
    assert_equal 302, home.status
    assert_match %r{/library\z}, home.headers["Location"]
    assert_equal 302, step.status
    assert_equal 404, unknown.status
  end

  def test_opening_a_runbook_redirects_to_it_and_carries_the_token
    response = open_runbook("hello")
    assert_equal 302, response.status
    assert_match %r{/\z}, response.headers["Location"]
    assert_same @library, Runsheets::Web.session.library
    assert_equal "tok", Runsheets::Web.session.token, "the token carries over"
  end

  def test_an_open_runbook_is_served_and_the_header_links_back
    open_runbook("hello")
    home = get "/"
    assert home.ok?
    assert_includes home.body, "Hello, runsheets"
    assert_includes home.body, 'href="/library"'
  end

  def test_the_library_offers_to_continue_the_open_runbook
    open_runbook("hello")
    library = get("/library").body
    pane    = get("/library/hello").body
    assert_includes library, "Continue"
    assert_includes library, "Back to runbook"
    assert_equal 3, library.scan(" Open</a>").size
    assert_includes pane, ">open now<"
    assert_includes pane, 'class="tree-runbook current active'
  end

  def test_plain_documents_anywhere_in_the_library_open_from_any_runbook
    open_runbook("hello")
    home   = get("/").body
    about  = get "/docs/about-the-examples.md"
    policy = get "/docs/policies/cleanup-policy.md"
    image  = get "/files/policies/images/triage-flow.svg"
    assert_includes home, 'href="/docs/about-the-examples.md"', "a runbook directory links one level up"
    assert about.ok?
    assert_includes about.body, "<title>About these examples · Hello, runsheets</title>"
    assert_includes about.body, 'href="/docs/policies/cleanup-policy.md"'
    assert policy.ok?
    assert_includes policy.body, 'src="/files/policies/images/triage-flow.svg"'
    assert image.ok?
  end

  def test_document_links_to_runbooks_go_to_the_runbook_not_the_markdown
    open_runbook("hello")
    other = get "/docs/disk-space-triage.md"
    own   = get "/docs/hello/steps/010-say-hello.md"
    assert_equal 302, other.status
    assert_match %r{/library/disk-space-triage\z}, other.location, "another runbook opens in the library"
    assert_match %r{/steps/010-say-hello\z}, own.location, "the open runbook's own step"
  end

  def test_search_works_before_a_runbook_is_open_and_links_into_the_library
    response = get "/search", "q" => "vacuum"
    body = response.body
    assert response.ok?
    assert_includes body, "<title>Search · runsheets</title>"
    assert_includes body, "1 runbook match <strong>vacuum</strong>"
    assert_includes body, 'href="/library/db-maintenance"'
    assert_includes body, "<mark>"
    assert_includes body, 'id="lib-tree-nav"', "results sit beside the tree"
    assert_includes body, 'value="vacuum"', "the header box keeps the query"
  end

  def test_search_hits_link_to_the_step_rows_of_the_library_pane
    results = get("/search", "q" => "vacuum").body
    pane    = get("/library/db-maintenance").body
    assert_match %r{href="/library/db-maintenance#step-\d+-[a-z-]+"}, results, "a numbered step links to its row"
    assert_match(/<li id="step-\d+-[a-z-]+">/, pane, "step rows carry the anchors")
  end

  def test_search_links_the_open_runbook_straight_to_its_steps
    open_runbook("disk-space-triage")
    body = get("/search", "q" => "threshold").body
    assert_includes body, "open now"
    assert_includes body, 'href="/steps/verify"'
  end

  def test_search_with_no_query_or_no_match
    empty  = get "/search"
    missed = get("/search", "q" => "zzzz-not-there").body
    assert empty.ok?
    assert_includes empty.body, "Search the text of every runbook"
    assert_includes missed, "0 runbooks match"
    assert_includes missed, "No runbook contains every word"
  end

  def test_query_is_escaped
    get "/search", "q" => "<script>alert(1)</script>"
    refute_includes last_response.body, "<script>alert(1)</script>"
    assert_includes last_response.body, "&lt;script&gt;"
  end

  def test_documents_open_beside_the_tree_before_a_runbook_is_open
    pane     = get("/library/disk-space-triage").body
    glossary = get "/docs/disk-usage-glossary.md"
    assert_includes pane, %(href="/docs/disk-usage-glossary.md")
    assert glossary.ok?, "no redirect to the library"
    assert_includes glossary.body, "<title>Disk usage glossary · runsheets</title>"
    assert_includes glossary.body, %(id="lib-tree-nav"), "shown beside the tree"
    assert_includes glossary.body, %(href="/docs/policies/cleanup-policy.md")
  end

  def test_linked_documents_and_files_serve_before_a_runbook_is_open
    policy  = get "/docs/policies/cleanup-policy.md"
    image   = get "/files/policies/images/triage-flow.svg"
    missing = get "/docs/missing.md"
    assert policy.ok?
    assert image.ok?
    assert_equal 404, missing.status
  end

  def test_runbook_links_and_pages_need_an_open_runbook
    runbook = get "/docs/disk-space-triage.md"
    step    = get "/steps/010-say-hello"
    assert_match %r{/library/disk-space-triage\z}, runbook.location, "a runbook opens in the library"
    assert_match %r{/library\z}, step.location, "runbook pages still need an open runbook"
  end

  def test_document_links_open_in_a_new_tab_and_runbook_links_do_not
    pane  = get("/library/disk-space-triage").body
    about = get("/docs/about-the-examples.md").body
    assert_includes pane, '<a href="/docs/disk-usage-glossary.md" target="_blank" rel="noopener">'
    assert_includes about, '<a href="/docs/disk-space-triage.md">', "a runbook link stays in the tab"
    assert_includes about, '<a href="/docs/disk-usage-glossary.md">', "inside a document tab, documents stay in that tab"
  end

  def test_plain_documents_stay_out_of_the_tree
    response = get "/library"
    assert response.ok?
    %w[about-the-examples disk-usage-glossary policies].each { refute_includes response.body, "data-slug=\"#{it}\"" }
  end

  def test_switching_serves_the_new_runbook_and_keeps_the_earlier_run_open
    open_runbook("hello", inputs: { "NAME" => "first" })
    open_runbook("db-maintenance")
    home = get "/"
    session = Runsheets::Web.session
    assert home.ok?
    assert_includes home.body, "Monthly PostgreSQL maintenance"
    assert session.runbook.single_file?
    assert session.run_for("hello").open?, "switching finishes nothing"
  end

  def test_returning_to_an_earlier_runbook_finds_its_open_run
    open_runbook("hello", inputs: { "NAME" => "first" })
    open_runbook("db-maintenance")
    pane = get("/library/hello").body
    open_runbook("hello")
    session = Runsheets::Web.session
    assert_includes pane, ">run open<"
    assert_includes pane, "Return to its run"
    assert_equal "hello", session.runbook.slug
    assert_equal "first", session.current.inputs["NAME"], "the same run"
    assert_equal 2, session.runs.size
  end

  def test_opening_needs_the_token_and_a_known_slug
    tokenless = post "/runs", "slug" => "hello"
    unknown   = open_runbook("nope")
    assert_equal 403, tokenless.status
    assert_equal 404, unknown.status
    assert_empty Runsheets::Web.session.runs
  end

  def test_the_session_page_sits_beside_the_tree_before_a_runbook_is_open
    get "/session"
    assert last_response.ok?
    assert_includes last_response.body, 'id="lib-tree-nav"'
    assert_includes last_response.body, "No runbook selected yet"
  end

  def test_the_library_is_404_when_serving_one_runbook
    serve_one_runbook
    library = get "/library"
    pane    = get "/library/hello"
    home    = get "/"
    assert_equal 404, library.status
    assert_equal 404, pane.status
    assert home.ok?
    refute_includes home.body, 'href="/library"'
  end
end

# A nested library: folders in the tree, slugs that are paths, run records
# filed under them.
class TestWebNestedLibrary < Minitest::Test
  include Rack::Test::Methods
  include RunsheetsTest
  include RunsheetsTest::WebLibraryFixtures

  def setup = serve_nested_library

  def teardown = stop_library_server

  def app = Runsheets::Web

  def test_the_root_shows_the_readme_and_folder_cards
    body = get("/library").body
    assert_includes body, "<strong>root</strong>"
    assert_includes body, "4 runbooks in 3 folders"
    assert_includes body, 'class="lib-card folder" href="/library/platform"'
  end

  def test_the_root_shows_the_whole_tree
    body = get("/library").body
    assert_includes body, 'data-slug="platform/database/backup"'
    assert_includes body, 'href="/library/platform/network/backup"'
    assert_includes body, "<details open>", "the first level is open"
    assert_includes body, 'data-search="backup backup the routers platform/network/backup"'
    assert_includes body, 'class="tree-runbook broken"'
  end

  def test_selecting_a_folder_shows_its_readme_and_contents_with_crumbs
    response = get "/library/platform"
    body = response.body
    assert response.ok?
    assert_includes body, "Platform things."
    assert_includes body, "3 runbooks in 2 folders"
    assert_includes body, '<a href="/library">Runbooks</a>'
    assert_includes body, '<span class="current">platform</span>'
    assert_includes body, 'href="/library/platform/database"'
  end

  def test_a_folder_reports_a_broken_runbook_and_takes_a_trailing_slash
    broken   = get("/library/platform").body
    trailing = get "/library/platform/"
    assert_includes broken, "does not load"
    assert_includes broken, "not valid YAML"
    assert trailing.ok?, "a trailing slash is fine"
  end

  def test_selecting_a_nested_runbook_shows_it_with_the_crumbs
    response = get "/library/platform/database/backup"
    body = response.body
    assert response.ok?
    assert_includes body, "Backup the database"
    assert_includes body, "Nightly."
    assert_includes body, "Preamble here."
    assert_includes body, '<a href="/library/platform">platform</a>'
    assert_includes body, '<a href="/library/platform/database">database</a>'
    assert_includes body, '<span class="current">Backup the database</span>'
  end

  def test_selecting_a_nested_runbook_expands_only_its_folders
    body = get("/library/platform/database/backup").body
    network = body[%r{data-slug="platform/network".*?<details[^>]*>}m]
    assert_includes body, 'name="slug" value="platform/database/backup"'
    refute_includes network, "open", "a sibling folder stays folded"
  end

  def test_opening_a_nested_runbook_carries_its_path_slug_into_the_session_and_run_records
    response = open_runbook("platform/database/backup")
    session = Runsheets::Web.session
    assert_equal 302, response.status
    assert_equal "platform/database/backup", session.runbook.slug
    assert_equal File.join(@runs_root, "platform/database/backup"), File.dirname(session.run.dir)
    assert_equal "platform/database/backup", session.run.runbook_slug
  end

  def test_an_open_nested_runbook_shows_its_folders_as_crumbs
    open_runbook("platform/database/backup")
    home = get "/"
    assert home.ok?
    assert_includes home.body, '<a href="/library" title="Runbooks [r]">Runbooks</a>'
    assert_includes home.body, '<a href="/library/platform">platform</a>'
    assert_includes home.body, '<a href="/library/platform/database">database</a>'
  end

  def test_the_pane_of_an_open_nested_runbook_lists_its_runs
    open_runbook("platform/database/backup")
    body = get("/library/platform/database/backup").body
    assert_includes body, "Previous runs"
    assert_includes body, Runsheets::Web.session.run.id
    assert_includes body, ">open now<"
  end

  def test_a_runbook_added_while_serving_appears_on_the_next_visit
    before = get("/library").body
    write_file(@dir, "platform/late.md", single_runbook("Late arrival"))
    after = get("/library/platform").body
    refute_includes before, "Late arrival"
    assert_includes after, "Late arrival"
    assert_includes after, 'href="/library/platform/late"'
  end
end
