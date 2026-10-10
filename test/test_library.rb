# frozen_string_literal: true

require "test_helper"

class TestLibrary < Minitest::Test
  include RunsheetsTest

  Library = Runsheets::Library
  EXAMPLES = File.expand_path("../examples", __dir__)

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

    single = library.find("db-maintenance")
    assert single.single_file?
    assert_equal "Monthly PostgreSQL maintenance", single.title
    assert_equal 5, single.steps
    assert_equal %w[postgres maintenance], single.tags
    assert single.ok?

    dir = library.find("hello")
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
    Dir.mktmpdir("runsheets-lib") do |dir|
      FileUtils.mkdir_p(File.join(dir, "good", "steps"))
      File.write(File.join(dir, "good", "runbook.md"), "---\ntitle: Good\n---\n")
      File.write(File.join(dir, "good", "steps", "010-a.md"), "---\ntitle: A\nkind: manual\n---\nDo it.\n")
      FileUtils.mkdir_p(File.join(dir, "not-a-runbook"))
      FileUtils.mkdir_p(File.join(dir, ".hidden"))
      File.write(File.join(dir, ".hidden", "runbook.md"), "---\ntitle: Hidden\n---\n")
      File.write(File.join(dir, "notes.txt"), "not markdown")
      File.write(File.join(dir, "one.md"), "---\ntitle: One\n---\n\n## Only step\n<!-- kind: manual -->\n\nDo it.\n")

      library = Library.load(dir)
      assert_equal %w[good one], library.entries.map(&:slug)
      assert_equal [false, true], library.entries.map(&:single_file?)
    end
  end

  def test_a_runbook_that_does_not_load_is_listed_with_its_error
    Dir.mktmpdir("runsheets-lib") do |dir|
      File.write(File.join(dir, "fine.md"), "---\ntitle: Fine\n---\n\n## Step\n<!-- kind: manual -->\n\nDo it.\n")
      FileUtils.mkdir_p(File.join(dir, "broken"))
      File.write(File.join(dir, "broken", "runbook.md"), "---\ntitle: [unclosed\n---\n")

      library = Library.load(dir)
      broken = library.find("broken")
      refute broken.ok?
      assert_equal "broken", broken.title, "falls back to the slug"
      refute_nil broken.error
      assert library.find("fine").ok?
    end
  end

  def test_an_empty_or_missing_directory_is_an_error
    Dir.mktmpdir("runsheets-lib") do |dir|
      error = assert_raises(Runsheets::RunbookError) { Library.load(dir) }
      assert_match(/no runbooks in/, error.message)
    end
    assert_raises(Runsheets::RunbookError) { Library.load("/nonexistent/dir") }
  end
end

# Nested libraries: folders to any depth, READMEs, slugs that are paths.
class TestNestedLibrary < Minitest::Test
  include RunsheetsTest

  Library = Runsheets::Library

  SINGLE = "---\ntitle: %s\ntags: [%s]\n---\n\n## Only step\n<!-- kind: manual -->\n\nDo it.\n"

  def with_nested
    Dir.mktmpdir("runsheets-nested") do |dir|
      write(dir, "README.md", "# Ops\n\nEverything we run **by hand**.\n")
      write(dir, "deploy.md", format(SINGLE, "Deploy", "release"))
      write(dir, "database/backup/runbook.md", "---\ntitle: Backup the database\n---\n")
      write(dir, "database/backup/steps/010-dump.md", "---\ntitle: Dump\nkind: manual\n---\nDo it.\n")
      write(dir, "database/backup/steps/020-copy.md", "---\ntitle: Copy\nkind: manual\n---\nDo it.\n")
      write(dir, "database/restore.md", format(SINGLE, "Restore the database", "postgres"))
      write(dir, "database/readme.md", "Lower-case readme counts too.\n")
      write(dir, "network/edge/teardown/runbook.md", "---\ntitle: Tear down the edge\n---\n")
      write(dir, "network/edge/teardown/steps/010-go.md", "---\ntitle: Go\nkind: manual\n---\nDo it.\n")
      write(dir, "network/backup.md", format(SINGLE, "Backup the routers", "network"))
      write(dir, "empty/deeper/notes.txt", "nothing here")
      write(dir, ".hidden/secret.md", format(SINGLE, "Hidden", "x"))
      yield dir, Library.load(dir)
    end
  end

  def write(dir, rel, text)
    path = File.join(dir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  def test_slugs_are_paths_inside_the_library_and_folders_are_found_to_any_depth
    with_nested do |_dir, library|
      assert_equal %w[database/backup database/restore deploy network/backup network/edge/teardown], library.entries.map(&:slug)
      assert_equal %w[database network network/edge], library.folders.map(&:slug), "folders without runbooks are left out"
      assert_equal 5, library.size
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

  def test_the_tree_lists_folders_then_runbooks_in_title_order
    with_nested do |_dir, library|
      root = library.root
      assert root.root?
      assert_equal %w[database network], root.folders.map(&:name)
      assert_equal %w[deploy], root.entries.map(&:slug)
      database = library.folder("database")
      assert_equal ["Backup the database", "Restore the database"], database.entries.map(&:title)
      assert_equal 1, database.depth
      assert_equal 2, library.folder("network/edge").depth
      assert_equal %w[network/backup network/edge/teardown], library.folder("network").runbooks.map(&:slug)
      assert_equal %w[network/edge], library.folder("network").subfolders.map(&:slug)
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

  def test_node_and_ancestors_resolve_runbooks_folders_and_the_root
    with_nested do |_dir, library|
      assert library.node("deploy").runbook?
      assert library.node("network/edge").folder?
      assert library.node("").root?
      assert_nil library.node("nope")
      assert_nil library.node("network/nope")
      assert_equal %w[network network/edge], library.ancestors("network/edge/teardown").map(&:slug)
      assert_equal %w[network], library.ancestors("network/edge").map(&:slug)
      assert_equal [], library.ancestors("deploy")
    end
  end

  def test_refresh_picks_up_added_removed_and_edited_runbooks
    with_nested do |dir, library|
      refute library.stale?
      write(dir, "network/new.md", format(SINGLE, "New", "x"))
      assert library.stale?, "a folder gained a child"
      library.refresh!
      assert_equal "New", library.find("network/new").title
      refute library.stale?

      File.write(File.join(dir, "network", "new.md"), format(SINGLE, "Renamed", "x"))
      FileUtils.touch(File.join(dir, "network", "new.md"), mtime: Time.now + 2)
      assert library.stale?, "a runbook's file changed"
      assert_equal "Renamed", library.refresh!.find("network/new").title

      FileUtils.rm(File.join(dir, "network", "new.md"))
      assert library.stale?
      assert_nil library.refresh!.find("network/new")
    end
  end

  def test_markdown_without_a_front_matter_title_is_a_document_not_a_runbook
    with_nested do |dir, _library|
      write(dir, "glossary.md", "# Glossary\n\nTerms we use.\n")
      write(dir, "database/conventions.md", "---\ntags: [style]\n---\n# Conventions\n")
      library = Library.load(dir)
      assert_nil library.find("glossary")
      assert_nil library.find("database/conventions")
      assert_equal 5, library.size
    end
  end

  def test_a_document_edited_into_a_runbook_joins_the_tree
    with_nested do |dir, _library|
      write(dir, "glossary.md", "# Glossary\n")
      library = Library.load(dir)
      refute library.stale?
      File.write(File.join(dir, "glossary.md"), format(SINGLE, "Glossary", "x"))
      FileUtils.touch(File.join(dir, "glossary.md"), mtime: Time.now + 2)
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
      write(dir, "notes.md", "# Notes\n")
      assert_nil library.entry_at(File.join(dir, "notes.md"))
      assert_nil library.entry_at(File.join(dir, "database/backupx.md")), "a name sharing a prefix is not inside"
    end
  end

  def test_clashing_slugs_are_reported_not_hidden
    with_nested do |dir, _library|
      write(dir, "deploy/runbook.md", "---\ntitle: Deploy dir\n---\n")
      write(dir, "deploy/steps/010-go.md", "---\ntitle: Go\nkind: manual\n---\nGo.\n")
      library = Library.load(dir)
      clashes = library.entries.select { it.slug == "deploy" }
      assert_equal 2, clashes.size
      assert_equal 1, clashes.count(&:ok?), "the first keeps the slug"
      assert_match(/already has the name deploy/, clashes.reject(&:ok?).first.error)
    end
  end

  def test_a_runbook_added_to_a_folder_without_runbooks_is_found
    with_nested do |dir, library|
      write(dir, "empty/deeper/new.md", format(SINGLE, "New here", "x"))
      FileUtils.touch(File.join(dir, "empty", "deeper"), mtime: Time.now + 2)
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
