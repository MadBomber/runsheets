# frozen_string_literal: true

require "test_helper"

class TestRunbook < Minitest::Test
  include RunsheetsTest

  def test_loads_the_example_without_warnings
    rb = example_runbook
    assert_equal "hello", rb.slug
    assert_equal "Hello, runsheets", rb.title
    assert_equal %w[010-say-hello 020-inspect-ruby 030-take-a-breath 035-keep-a-clock-running 040-exercise-failure 045-check-the-greeting], rb.steps.map(&:slug)
    assert_equal [1, 2, 3, 4, 5, 6], rb.steps.map(&:position)
    assert_equal %w[verify rollback], rb.extras.keys
    assert_equal %w[example safe], rb.tags
    assert_empty rb.warnings
  end

  def test_inputs
    rb = example_runbook
    assert_equal %w[NAME SECRET_WORD], rb.inputs.map(&:name)
    assert_equal "world", rb.input("NAME").default
    assert rb.input("SECRET_WORD").secret?
    refute rb.input("NAME").secret?
  end

  def test_step_kinds_and_blocks
    rb = example_runbook
    hello = rb.step("010-say-hello")
    assert hello.automated?
    assert_equal 30, hello.timeout
    assert_equal %w[010-say-hello-1 010-say-hello-2 010-say-hello-3], hello.blocks.map(&:id)
    assert_equal [true, false, false], hello.blocks.map(&:executable?)
    assert_equal :expect, hello.blocks[1].kind

    assert rb.step("030-take-a-breath").manual?
    assert rb.step("040-exercise-failure").destructive?
    assert rb.destructive?
    assert rb.step("verify").verify?
  end

  def test_find_block_and_neighbors
    rb = example_runbook
    step, block = rb.find_block("020-inspect-ruby-1")
    assert_equal "020-inspect-ruby", step.slug
    assert_equal "ruby", block.lang
    assert_nil rb.find_block("nope")

    prev, nxt = rb.neighbors(rb.step("020-inspect-ruby"))
    assert_equal "010-say-hello", prev.slug
    assert_equal "030-take-a-breath", nxt.slug
    assert_equal [nil, nil], rb.neighbors(rb.step("verify"))
  end

  def test_interpreters_can_be_overridden_in_front_matter
    files = {
      "runbook.md" => "---\ntitle: T\ninterpreters:\n  ruby: bin/rails runner -\n  sql: psql \"$DATABASE_URL\" -f\n---\n",
      "steps/010-a.md" => "---\ntitle: A\n---\n```ruby run\nputs 1\n```\n"
    }
    with_runbook(files) do |rb|
      assert_equal %w[bin/rails runner -], rb.interpreter_for("ruby")
      assert_equal ["psql", "$DATABASE_URL", "-f"], rb.interpreter_for("sql")
      assert_equal %w[bash], rb.interpreter_for("bash")
    end
  end

  def test_missing_runbook_md_raises
    Dir.mktmpdir { |dir| assert_raises(Runsheets::RunbookError) { Runsheets::Runbook.load(dir) } }
  end

  def test_warnings_are_collected
    files = {
      "runbook.md" => "---\ntitle: T\ninputs:\n  - name: bad-name\n---\n",
      "steps/010-a.md" => "---\nkind: automated\n---\nno blocks\n",
      "steps/020-b.md" => "```bash run nope\nx\n```\n"
    }
    with_runbook(files) do |rb|
      assert_includes rb.warnings, "input name 'bad-name' is not a valid environment variable name"
      assert_includes rb.warnings, "010-a: automated step has no executable block"
      assert_includes rb.warnings, "020-b: block 020-b-1: unknown flag: nope"
    end
  end

  def test_a_runbook_needs_front_matter_with_a_title
    ["# No front matter\n", "---\ntags: [x]\n---\n", "---\ntitle: \"\"\n---\n"].each do |text|
      error = assert_raises(Runsheets::RunbookError) { with_runbook("runbook.md" => text, "steps/010-a.md" => "a") { nil } }
      assert_includes error.message, "runbook.md is not a runbook: it needs YAML front matter with a title"
    end
  end

  def test_runbook_text_needs_a_titled_front_matter
    assert Runsheets::Runbook.runbook_text?("---\ntitle: T\n---\nbody\n")
    assert Runsheets::Runbook.runbook_text?("---\ntitle: [unclosed\n---\n"), "broken front matter was meant to be a runbook"
    refute Runsheets::Runbook.runbook_text?("# Just a document\n")
    refute Runsheets::Runbook.runbook_text?("---\ntags: [x]\n---\n# A document with other front matter\n")
  end

  def test_links_resolve_against_the_root_which_defaults_to_the_runbook_directory
    Dir.mktmpdir do |lib|
      dir = File.join(lib, "deploy")
      FileUtils.mkdir_p(File.join(dir, "steps"))
      File.write(File.join(dir, "runbook.md"), "---\ntitle: T\n---\nSee [notes](../notes.md) and [local](local.md).\n")
      File.write(File.join(dir, "steps", "010-a.md"), "Back to [notes](../../notes.md).\n")

      alone = Runsheets::Runbook.load(dir)
      assert_equal File.expand_path(dir), alone.root
      assert_includes alone.landing.html, 'href="../notes.md"', "climbing out of the root is left alone"
      assert_includes alone.landing.html, 'href="/docs/local.md"'

      in_library = Runsheets::Runbook.load(dir, root: lib)
      assert_equal File.expand_path(lib), in_library.root
      assert_includes in_library.landing.html, 'href="/docs/notes.md"'
      assert_includes in_library.landing.html, 'href="/docs/deploy/local.md"'
      assert_includes in_library.steps.first.html, 'href="/docs/notes.md"'
    end
  end

  def test_plain_document_is_markdown_outside_any_runbook
    Dir.mktmpdir do |lib|
      files = {
        "notes.md" => "# Notes\n",
        "guides/setup.md" => "# Setup\n",
        "deploy.md" => "---\ntitle: Deploy\n---\n## Go\n",
        "backup/runbook.md" => "---\ntitle: Backup\n---\n",
        "backup/steps/010-dump.md" => "Dump it.\n",
        "backup/extra.md" => "# Extra\n"
      }
      files.each do |rel, text|
        FileUtils.mkdir_p(File.dirname(File.join(lib, rel)))
        File.write(File.join(lib, rel), text)
      end
      plain = ->(rel) { Runsheets::Runbook.plain_document?(File.join(lib, rel), lib) }
      assert plain.call("notes.md")
      assert plain.call("guides/setup.md")
      refute plain.call("deploy.md"), "a single-file runbook"
      refute plain.call("backup/runbook.md")
      refute plain.call("backup/steps/010-dump.md"), "a step of a runbook directory"
      refute plain.call("backup/extra.md"), "inside a runbook directory"
      refute plain.call("missing.md")
      refute Runsheets::Runbook.plain_document?(File.join(lib, "notes.md"), File.join(lib, "guides")), "outside the root"
    end
  end

  def test_document_at_finds_the_document_read_from_a_file
    with_runbook("runbook.md" => "---\ntitle: T\n---\n", "steps/010-a.md" => "a", "notes.md" => "n") do |rb|
      assert_equal rb.landing, rb.document_at(File.join(rb.dir, "runbook.md"))
      assert_equal "010-a", rb.document_at(File.join(rb.dir, "steps", "010-a.md")).slug
      assert_nil rb.document_at(File.join(rb.dir, "notes.md"))
    end
  end

  def test_verify_documents_are_verify_steps_then_verify_md
    rb = example_runbook
    assert_equal %w[045-check-the-greeting verify], rb.verify_documents.map(&:slug)
    assert rb.verify_document?(rb.step("verify"))
    refute rb.verify_document?(rb.step("010-say-hello"))
    assert_equal %w[045-check-the-greeting-1 verify-1 verify-2], rb.verify_blocks.map(&:id)
  end

  def test_stale_when_a_source_file_changes_or_appears
    with_runbook("runbook.md" => "---\ntitle: T\n---\n", "steps/010-a.md" => "a") do |rb|
      refute rb.stale?
      sleep 0.01
      File.write(File.join(rb.dir, "steps", "010-a.md"), "b")
      assert rb.stale?
      fresh = Runsheets::Runbook.load(rb.dir)
      refute fresh.stale?
      File.write(File.join(rb.dir, "verify.md"), "v")
      assert fresh.stale?, "a new source file counts"
    end
  end

  def test_steps_sort_numerically
    files = { "runbook.md" => "---\ntitle: T\n---\n", "steps/2-b.md" => "b", "steps/10-c.md" => "c", "steps/1-a.md" => "a" }
    with_runbook(files) { assert_equal %w[1-a 2-b 10-c], it.steps.map(&:slug) }
  end

  def test_step_title_fallbacks
    files = { "runbook.md" => "---\ntitle: T\n---\n", "steps/010-do-the-thing.md" => "text", "steps/020-x.md" => "# Heading Title\n" }
    with_runbook(files) do |rb|
      assert_equal "Do the thing", rb.step("010-do-the-thing").title
      assert_equal "Heading Title", rb.step("020-x").title
    end
  end

  def test_invalid_timeout_warns_and_falls_back_to_the_default
    files = { "runbook.md" => "---\ntitle: T\n---\n", "steps/010-a.md" => "---\ntimeout: abc\n---\n```bash run\ntrue\n```\n",
              "steps/020-b.md" => "---\ntimeout: 0\n---\n```bash run\ntrue\n```\n", "steps/030-c.md" => "---\ntimeout: 42\n---\n```bash run\ntrue\n```\n" }
    with_runbook(files) do |rb|
      a, b, c = rb.steps
      assert_equal Runsheets::Step::DEFAULT_TIMEOUT, a.timeout
      assert_equal Runsheets::Step::DEFAULT_TIMEOUT, b.timeout
      assert_equal 42, c.timeout
      assert_equal 2, rb.warnings.grep(/timeout must be a positive number/).size
    end
  end
end

class TestRunbookSlug < Minitest::Test
  include RunsheetsTest

  def test_the_slug_is_the_directory_or_file_name_unless_given
    assert_equal "hello", example_runbook.slug
    assert_equal "ops/hello", Runsheets::Runbook.load(RunsheetsTest::EXAMPLE_DIR, slug: "ops/hello").slug
    path = File.expand_path("../examples/db-maintenance.md", __dir__)
    assert_equal "db-maintenance", Runsheets::Runbook.load(path).slug
    assert_equal "database/maintenance", Runsheets::Runbook.load(path, slug: "database/maintenance").slug
  end

  def test_a_runbook_loaded_from_its_main_file_takes_the_directory_name
    assert_equal "hello", Runsheets::Runbook.load(File.join(RunsheetsTest::EXAMPLE_DIR, "runbook.md")).slug
  end
end
