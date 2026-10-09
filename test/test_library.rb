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

  def test_the_examples_directory_lists_its_three_runbooks_in_slug_order
    library = Library.load(EXAMPLES)
    assert_equal %w[db-maintenance hello staging-teardown], library.entries.map(&:slug)
    assert_equal 3, library.size

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
