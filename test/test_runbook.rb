# frozen_string_literal: true

require "test_helper"

class TestRunbook < Minitest::Test
  include RunsheetsTest

  def test_loads_the_example_without_warnings
    rb = example_runbook
    assert_equal "hello", rb.slug
    assert_equal "Hello, runsheets", rb.title
    assert_equal %w[010-say-hello 020-inspect-ruby 030-take-a-breath 035-keep-a-clock-running 040-exercise-failure], rb.steps.map(&:slug)
    assert_equal [1, 2, 3, 4, 5], rb.steps.map(&:position)
    assert_equal %w[verify rollback], rb.extras.keys
    assert_equal %w[example safe], rb.tags
    assert_equal Date.new(2026, 10, 7), rb.last_verified
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
      "runbook.md" => "---\ninputs:\n  - name: bad-name\n---\n",
      "steps/010-a.md" => "---\nkind: automated\n---\nno blocks\n",
      "steps/020-b.md" => "```bash run nope\nx\n```\n"
    }
    with_runbook(files) do |rb|
      assert_includes rb.warnings, "title missing from runbook.md front matter"
      assert_includes rb.warnings, "input name 'bad-name' is not a valid environment variable name"
      assert_includes rb.warnings, "010-a: automated step has no executable block"
      assert_includes rb.warnings, "020-b: block 020-b-1: unknown flag: nope"
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
end
