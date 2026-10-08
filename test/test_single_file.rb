# frozen_string_literal: true

require "test_helper"

class TestSingleFile < Minitest::Test
  include RunsheetsTest

  SingleFile = Runsheets::SingleFile

  SAMPLE = <<~MD
    ---
    title: One file
    inputs:
      - name: TARGET
        default: staging
    interpreters:
      sql: psql -X -f
    ---

    # One file

    Preamble text.

    ```bash
    ## not a heading, inside a fence
    ```

    ## Snapshot the database
    <!-- kind: automated, timeout: 120 -->

    Take a snapshot.

    ```bash run
    echo "snapshot $TARGET"
    ```

    ## Tell the team

    <!-- kind: manual -->
    Post in the channel.

    ## Count the rows
    <!-- kind: verify -->

    ```sql run
    select count(*) from things;
    ```

    ## Delete the stack
    <!-- destructive: true -->

    ```bash destructive
    echo "deleting $TARGET"
    ```

    ## Verify

    ```bash run
    echo verified
    ```

    ## Rollback

    Restore the snapshot.
  MD

  def with_single_file(text = SAMPLE, name: "one-file.md")
    Dir.mktmpdir("runsheets-single") do |dir|
      path = File.join(dir, name)
      File.write(path, text)
      yield Runsheets::Runbook.load(path), path
    end
  end

  def test_split_ignores_headings_inside_fences_and_pulls_attribute_comments
    preamble, sections = SingleFile.split(Runsheets::FrontMatter.parse(SAMPLE).body)
    assert_includes preamble, "## not a heading, inside a fence"
    assert_equal ["Snapshot the database", "Tell the team", "Count the rows", "Delete the stack", "Verify", "Rollback"], sections.map(&:title)
    assert_equal({ "kind" => "automated", "timeout" => 120 }, sections[0].data)
    assert_equal({ "kind" => "manual" }, sections[1].data, "a blank line before the comment is fine")
    assert_equal({ "destructive" => true }, sections[3].data)
    assert_includes sections[0].body, 'echo "snapshot $TARGET"'
    refute_includes sections[0].body, "<!--"
    assert sections[4].extra?
    assert_equal "verify", sections[4].role
    assert_equal "rollback", sections[5].role
    refute sections[0].extra?
  end

  def test_bad_attribute_comment_warns_and_is_ignored
    _, sections = SingleFile.split("## Step\n<!-- kind: [unclosed -->\ntext\n")
    assert_equal({}, sections.first.data)
    assert_match(/could not be parsed/, sections.first.warnings.first)
    _, sections = SingleFile.split("## Step\n<!-- just a note -->\ntext\n")
    assert_equal({}, sections.first.data)
    assert_empty sections.first.warnings
    assert_includes sections.first.body, "<!-- just a note -->", "an ordinary comment stays in the body"
  end

  def test_slug_for
    assert_equal "010-snapshot-the-database", SingleFile.slug_for("Snapshot the database", 1)
    assert_equal "120-step", SingleFile.slug_for("!!!", 12)
    assert_equal "020-count-rows-2", SingleFile.slug_for("  Count rows (2) ", 2)
  end

  def test_loads_as_a_runbook_with_the_same_shape_as_a_directory
    with_single_file do |rb, path|
      assert rb.single_file?
      assert_equal "one-file", rb.slug
      assert_equal "One file", rb.title
      assert_equal File.dirname(path), rb.dir
      assert_equal path, rb.main_path
      assert_equal [path], rb.source_files
      assert_empty rb.warnings
      assert_includes rb.preamble_html, "Preamble text."

      assert_equal %w[010-snapshot-the-database 020-tell-the-team 030-count-the-rows 040-delete-the-stack], rb.steps.map(&:slug)
      assert_equal [1, 2, 3, 4], rb.steps.map(&:position)
      assert_equal ["Snapshot the database", "Tell the team", "Count the rows", "Delete the stack"], rb.steps.map(&:title)
      assert_equal %w[automated manual verify automated], rb.steps.map(&:kind)
      assert_equal 120, rb.steps[0].timeout
      assert rb.steps[3].destructive?
      assert_equal %w[verify rollback], rb.extras.keys
      assert_equal "Verify", rb.verify.title
      assert_includes rb.rollback.html, "Restore the snapshot."
      assert_equal %w[030-count-the-rows verify], rb.verify_documents.map(&:slug)

      step, block = rb.find_block("010-snapshot-the-database-1")
      assert_equal "010-snapshot-the-database", step.slug
      assert block.executable?
      assert_equal [rb.steps[0], rb.steps[2]], rb.neighbors(rb.steps[1])
    end
  end

  def test_sql_executes_only_when_the_front_matter_maps_it
    with_single_file do |rb, _|
      block = rb.step("030-count-the-rows").blocks.first
      assert_equal "sql", block.lang
      assert block.executable?, "sql is mapped under interpreters"
      assert_equal %w[psql -X -f], rb.interpreter_for("sql")
    end
    text = SAMPLE.sub("interpreters:\n  sql: psql -X -f\n", "")
    with_single_file(text) do |rb, _|
      block = rb.step("030-count-the-rows").blocks.first
      refute block.executable?
      assert_match(/sql blocks cannot execute/, rb.warnings.join)
    end
  end

  def test_runbook_md_named_file_takes_the_directory_slug
    with_single_file(SAMPLE, name: "runbook.md") do |rb, path|
      assert_equal File.basename(File.dirname(path)), rb.slug
    end
  end

  def test_no_headings_warns
    with_single_file("---\ntitle: T\n---\njust prose\n") do |rb, _|
      assert_empty rb.steps
      assert_includes rb.warnings, "no steps found: add a ## heading per step"
    end
  end

  def test_role_attribute_and_duplicate_or_unknown_roles
    text = "---\ntitle: T\n---\n## Checks\n<!-- role: verify -->\nok\n## Verify\nsecond\n## Undo\n<!-- role: undo -->\nx\n## Real step\ntext\n"
    with_single_file(text) do |rb, _|
      assert_equal "Checks", rb.verify.title
      assert_equal %w[010-real-step], rb.steps.map(&:slug)
      assert rb.warnings.any? { it.include?("a second verify section") }
      assert rb.warnings.any? { it.include?("unknown role 'undo'") }
    end
  end

  def test_stale_and_stamp_work_on_the_single_file
    with_single_file do |rb, path|
      refute rb.stale?
      sleep 0.01
      rb.stamp_last_verified(Date.new(2026, 10, 8))
      assert_includes File.read(path), "last_verified: 2026-10-08\n---"
      assert rb.stale?
      assert_equal "2026-10-08", Runsheets::Runbook.load(path).last_verified.to_s
    end
  end

  def test_session_runs_a_single_file_runbook_end_to_end
    with_single_file do |rb, _|
      with_runs_dir do |root|
        s = Runsheets::Session.new(runbook: rb, runs_root: root)
        s.start_run(inputs: { "TARGET" => "qa" })
        ex = s.execute("010-snapshot-the-database-1").wait
        assert ex.success?
        assert_equal "snapshot qa\n", ex.output
        assert_equal rb.dir, s.working_directory(rb.steps.first)
        s.finish_run
        assert_equal 1, s.history.size
      end
    end
  end

  def test_examples_load_clean
    %w[staging-teardown db-maintenance.md].each do |name|
      rb = Runsheets::Runbook.load(File.expand_path("../examples/#{name}", __dir__))
      assert_empty rb.warnings, "#{name}: #{rb.warnings.join('; ')}"
      assert rb.steps.size >= 4
    end
    db = Runsheets::Runbook.load(File.expand_path("../examples/db-maintenance.md", __dir__))
    assert db.single_file?
    assert db.steps.any? { |s| s.blocks.any? { it.lang == "sql" && it.executable? } }, "sql blocks execute through the interpreters map"
    assert db.verify
    assert db.rollback
    assert db.inputs.any?(&:secret?)
    teardown = Runsheets::Runbook.load(File.expand_path("../examples/staging-teardown", __dir__))
    kinds = teardown.steps.flat_map(&:blocks).map(&:kind).uniq
    %i[run destructive terminal background expect].each { assert_includes kinds, it }
    assert teardown.destructive?
  end
end
