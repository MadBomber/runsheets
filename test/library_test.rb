# frozen_string_literal: true

require "test_helper"

class TestLibrary < Minitest::Test
  include RunsheetsTest
  include RunsheetsTest::LibraryFixtures

  Library = Runsheets::Library

  def test_a_directory_of_runbooks_is_a_library_and_a_runbook_is_not
    assert Library.library?(EXAMPLES)
    refute Library.library?(RunsheetsTest::EXAMPLE_DIR), "holds runbook.md"
    refute Library.library?(File.join(EXAMPLES, "db-maintenance.md")), "a file"
    refute Library.library?("/nonexistent")
  end

  def test_the_examples_directory_lists_its_four_runbooks_in_slug_order
    library = Library.load(EXAMPLES)
    assert_equal %w[db-maintenance disk-space-triage hello staging-teardown], library.entries.map(&:slug)
    assert_equal 4, library.size
    assert_empty library.folders, "examples/docs holds only plain documents"
  end

  def test_a_single_file_entry_carries_its_front_matter
    single = Library.load(EXAMPLES).find("db-maintenance")
    assert single.single_file?
    assert_equal "Monthly PostgreSQL maintenance", single.title
    assert_equal 5, single.steps
    assert_equal %w[postgres maintenance], single.tags
    assert single.ok?
  end

  def test_a_directory_entry_carries_its_title_and_path
    dir = Library.load(EXAMPLES).find("hello")
    refute dir.single_file?
    assert_equal "Hello, runsheets", dir.title
    assert_equal File.join(EXAMPLES, "hello"), dir.path
  end

  def test_runbook_loads_an_entry_and_unknown_slugs_raise
    library = Library.load(EXAMPLES)
    assert_equal "Hello, runsheets", library.runbook("hello").title
    assert library.runbook("db-maintenance").single_file?
    assert_raises(Runsheets::RunbookError) { library.runbook("nope") }
  end

  def test_only_runbooks_count_and_hidden_entries_are_skipped
    files = {
      "good/runbook.md" => "---\ntitle: Good\n---\n",
      "good/steps/010-a.md" => manual_step("A"),
      "not-a-runbook/.keep" => "",
      ".hidden/runbook.md" => "---\ntitle: Hidden\n---\n",
      "notes.txt" => "not markdown",
      "one.md" => single_runbook("One")
    }
    with_files(files) do |dir|
      library = Library.load(dir)
      assert_equal %w[good one], library.entries.map(&:slug)
      assert_equal [false, true], library.entries.map(&:single_file?)
    end
  end

  def test_a_runbook_that_does_not_load_is_listed_with_its_error
    with_files("fine.md" => single_runbook("Fine"), "broken/runbook.md" => "---\ntitle: [unclosed\n---\n") do |dir|
      library = Library.load(dir)
      broken = library.find("broken")
      refute broken.ok?
      assert_equal "broken", broken.title, "falls back to the slug"
      refute_nil broken.error
      assert library.find("fine").ok?
    end
  end

  def test_an_empty_or_missing_directory_is_an_error
    with_files({}) do |dir|
      error = assert_raises(Runsheets::RunbookError) { Library.load(dir) }
      assert_match(/no runbooks in/, error.message)
      assert_raises(Runsheets::RunbookError) { Library.load("/nonexistent/dir") }
    end
  end
end

# Nested libraries: folders to any depth, READMEs, slugs that are paths.
class TestNestedLibrary < Minitest::Test
  include RunsheetsTest
  include RunsheetsTest::LibraryFixtures

  Library = Runsheets::Library

  def test_slugs_are_paths_inside_the_library_and_folders_are_found_to_any_depth
    with_nested do |_dir, library|
      assert_equal %w[database/backup database/restore deploy network/backup network/edge/teardown], library.entries.map(&:slug)
      assert_equal %w[database network network/edge], library.folders.map(&:slug), "folders without runbooks are left out"
      assert_equal 5, library.size
    end
  end

  def test_an_entry_knows_its_name_folder_and_depth
    with_nested do |_dir, library|
      assert_equal "backup", library.find("database/backup").name
      assert_equal "database", library.find("database/backup").folder
      assert_equal "", library.find("deploy").folder
      assert_equal 1, library.find("database/backup").depth, "folders above it"
    end
  end

  def test_two_runbooks_named_alike_in_different_folders_are_distinct
    with_nested do |_dir, library|
      db  = library.runbook("database/backup")
      net = library.runbook("network/backup")
      assert_equal "database/backup", db.slug
      assert_equal "network/backup", net.slug
      assert_equal "Backup the database", db.title
      assert_equal "Backup the routers", net.title
    end
  end

  def test_the_root_lists_its_folders_and_its_own_runbooks
    with_nested do |_dir, library|
      root = library.root
      assert root.root?
      assert_equal %w[database network], root.folders.map(&:name)
      assert_equal %w[deploy], root.entries.map(&:slug)
    end
  end

  def test_folders_list_runbooks_in_title_order_and_know_their_depth
    with_nested do |_dir, library|
      database = library.folder("database")
      assert_equal ["Backup the database", "Restore the database"], database.entries.map(&:title)
      assert_equal 1, database.depth
      assert_equal 2, library.folder("network/edge").depth
    end
  end

  def test_a_folder_lists_its_runbooks_and_subfolders_to_any_depth
    with_nested do |_dir, library|
      network = library.folder("network")
      assert_equal %w[network/backup network/edge/teardown], network.runbooks.map(&:slug)
      assert_equal %w[network/edge], network.subfolders.map(&:slug)
    end
  end

  def test_a_readme_describes_its_folder_and_is_not_a_runbook
    with_nested do |_dir, library|
      assert library.root.readme?
      assert_includes library.root.readme_html, "<strong>by hand</strong>"
      assert library.folder("database").readme?, "any case of README.md"
      refute library.folder("network").readme?
      assert_nil library.find("README")
      assert_nil library.find("database/readme")
    end
  end

  def test_node_resolves_runbooks_folders_and_the_root
    with_nested do |_dir, library|
      assert library.node("deploy").runbook?
      assert library.node("network/edge").folder?
      assert library.node("").root?
      assert_nil library.node("nope")
      assert_nil library.node("network/nope")
    end
  end

  def test_ancestors_are_the_folders_above_a_node
    with_nested do |_dir, library|
      assert_equal %w[network network/edge], library.ancestors("network/edge/teardown").map(&:slug)
      assert_equal %w[network], library.ancestors("network/edge").map(&:slug)
      assert_equal [], library.ancestors("deploy")
    end
  end

  def test_a_freshly_loaded_library_is_not_stale
    with_nested do |_dir, library|
      refute library.stale?
      assert_equal 5, library.size
    end
  end

  def test_refresh_picks_up_an_added_runbook
    with_nested do |dir, library|
      write_file(dir, "network/new.md", single_runbook("New", "x"))
      stale = library.stale?
      library.refresh!
      assert stale, "a folder gained a child"
      assert_equal "New", library.find("network/new").title
      refute library.stale?
    end
  end

  def test_refresh_picks_up_an_edited_runbook
    with_nested do |dir, library|
      rewrite_file(dir, "network/backup.md", single_runbook("Renamed", "x"))
      assert library.stale?, "a runbook's file changed"
      assert_equal "Renamed", library.refresh!.find("network/backup").title
    end
  end

  def test_refresh_drops_a_removed_runbook
    with_nested do |dir, library|
      remove_file(dir, "network/backup.md")
      assert library.stale?
      assert_nil library.refresh!.find("network/backup")
    end
  end

  def test_markdown_without_a_front_matter_title_is_a_document_not_a_runbook
    files = nested_library_files.merge("glossary.md" => "# Glossary\n\nTerms we use.\n",
                                       "database/conventions.md" => "---\ntags: [style]\n---\n# Conventions\n")
    with_files(files) do |dir|
      library = Library.load(dir)
      assert_nil library.find("glossary")
      assert_nil library.find("database/conventions")
      assert_equal 5, library.size
    end
  end

  def test_a_document_edited_into_a_runbook_joins_the_tree
    with_files(nested_library_files.merge("glossary.md" => "# Glossary\n")) do |dir|
      library = Library.load(dir)
      unchanged = library.stale?
      rewrite_file(dir, "glossary.md", single_runbook("Glossary", "x"))
      refute unchanged
      assert library.stale?, "a document changed"
      assert_equal "Glossary", library.refresh!.find("glossary").title
    end
  end

  def test_runbooks_in_a_library_resolve_links_from_the_library_root
    with_nested do |dir, library|
      assert_equal File.realpath(dir), File.realpath(library.runbook("database/backup").root)
      assert_equal File.realpath(dir), File.realpath(library.find("deploy").runbook.root)
    end
  end

  def test_entry_at_finds_the_runbook_a_file_belongs_to
    with_nested do |dir, library|
      assert_equal "deploy", library.entry_at(File.join(dir, "deploy.md")).slug
      assert_equal "database/backup", library.entry_at(File.join(dir, "database/backup/runbook.md")).slug
      assert_equal "database/backup", library.entry_at(File.join(dir, "database/backup/steps/010-dump.md")).slug
    end
  end

  def test_entry_at_is_nil_for_a_file_outside_every_runbook
    with_files(nested_library_files.merge("notes.md" => "# Notes\n")) do |dir|
      library = Library.load(dir)
      assert_nil library.entry_at(File.join(dir, "notes.md"))
      assert_nil library.entry_at(File.join(dir, "database/backupx.md")), "a name sharing a prefix is not inside"
    end
  end

  def test_clashing_slugs_are_reported_not_hidden
    files = nested_library_files.merge("deploy/runbook.md" => "---\ntitle: Deploy dir\n---\n",
                                       "deploy/steps/010-go.md" => manual_step("Go"))
    with_files(files) do |dir|
      clashes = Library.load(dir).entries.select { it.slug == "deploy" }
      assert_equal 2, clashes.size
      assert_equal 1, clashes.count(&:ok?), "the first keeps the slug"
      assert_match(/already has the name deploy/, clashes.reject(&:ok?).first.error)
    end
  end

  def test_a_runbook_added_to_a_folder_without_runbooks_is_found
    with_nested do |dir, library|
      write_file(dir, "empty/deeper/new.md", single_runbook("New here", "x"))
      touch_later(File.join(dir, "empty", "deeper"))
      assert library.stale?
      assert library.refresh!.find("empty/deeper/new")
    end
  end

  def test_a_symlink_cycle_does_not_recurse_forever
    with_nested do |dir, library|
      File.symlink(dir, File.join(dir, "network", "loop"))
      assert_equal 5, library.refresh!.size
      assert_nil library.folder("network/loop")
    end
  end
end
