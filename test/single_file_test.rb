# frozen_string_literal: true

require "test_helper"

class TestSingleFile < Minitest::Test
  include RunsheetsTest
  include RunsheetsTest::SessionFixtures

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

  UNMAPPED = SAMPLE.sub("interpreters:\n  sql: psql -X -f\n", "")
  ROLES = "---\ntitle: T\n---\n## Checks\n<!-- role: verify -->\nok\n## Verify\nsecond\n## Undo\n<!-- role: undo -->\nx\n## Real step\ntext\n"
  EXAMPLES = File.expand_path("../examples", __dir__)

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
  end

  def test_an_ordinary_comment_stays_in_the_body
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
    with_single_file(SAMPLE) do |rb, path|
      assert rb.single_file?
      assert_equal "one-file", rb.slug
      assert_equal "One file", rb.title
      assert_equal File.dirname(path), rb.dir
      assert_equal path, rb.main_path
      assert_equal [path], rb.source_files
      assert_empty rb.warnings
      assert_includes rb.preamble_html, "Preamble text."
    end
  end

  def test_each_section_is_a_numbered_step_named_by_its_heading
    with_single_file(SAMPLE) do |rb, _|
      assert_equal %w[010-snapshot-the-database 020-tell-the-team 030-count-the-rows 040-delete-the-stack], rb.steps.map(&:slug)
      assert_equal ["Snapshot the database", "Tell the team", "Count the rows", "Delete the stack"], rb.steps.map(&:title)
    end
  end

  def test_steps_take_their_position_and_attributes
    with_single_file(SAMPLE) do |rb, _|
      assert_equal [1, 2, 3, 4], rb.steps.map(&:position)
      assert_equal %w[automated manual verify automated], rb.steps.map(&:kind)
      assert_equal 120, rb.steps[0].timeout
      assert rb.steps[3].destructive?
    end
  end

  def test_verify_and_rollback_sections_are_extras
    with_single_file(SAMPLE) do |rb, _|
      assert_equal %w[verify rollback], rb.extras.keys
      assert_equal "Verify", rb.verify.title
      assert_includes rb.rollback.html, "Restore the snapshot."
      assert_equal %w[030-count-the-rows verify], rb.verify_documents.map(&:slug)
    end
  end

  def test_blocks_and_neighbors_are_found_as_in_a_directory
    with_single_file(SAMPLE) do |rb, _|
      step, block = rb.find_block("010-snapshot-the-database-1")
      assert_equal "010-snapshot-the-database", step.slug
      assert block.executable?
      assert_equal [rb.steps[0], rb.steps[2]], rb.neighbors(rb.steps[1])
    end
  end

  def test_sql_executes_when_the_front_matter_maps_it
    with_single_file(SAMPLE) do |rb, _|
      block = rb.step("030-count-the-rows").blocks.first
      assert_equal "sql", block.lang
      assert block.executable?, "sql is mapped under interpreters"
      assert_equal %w[psql -X -f], rb.interpreter_for("sql")
    end
  end

  def test_sql_does_not_execute_when_the_front_matter_does_not_map_it
    with_single_file(UNMAPPED) do |rb, _|
      block = rb.step("030-count-the-rows").blocks.first
      refute block.executable?
      assert_match(/sql blocks cannot execute/, rb.warnings.join)
    end
  end

  def test_runbook_md_named_file_takes_the_directory_slug
    with_single_file(SAMPLE, name: "runbook.md") do |rb, path|
      assert_equal File.basename(File.dirname(path)), rb.slug
      assert rb.single_file?
    end
  end

  def test_no_headings_warns
    with_single_file("---\ntitle: T\n---\njust prose\n") do |rb, _|
      assert_empty rb.steps
      assert_includes rb.warnings, "no steps found: add a ## heading per step"
    end
  end

  def test_role_attribute_and_duplicate_or_unknown_roles
    with_single_file(ROLES) do |rb, _|
      assert_equal "Checks", rb.verify.title
      assert_equal %w[010-real-step], rb.steps.map(&:slug)
      assert_match(/a second verify section/, rb.warnings.join("\n"))
      assert_match(/unknown role 'undo'/, rb.warnings.join("\n"))
    end
  end

  def test_stale_works_on_the_single_file
    with_single_file(SAMPLE) do |rb, path|
      fresh = rb.stale?
      write_newer(path, SAMPLE.sub("\n---", "\ntags: [x]\n---"))
      refute fresh
      assert rb.stale?
    end
  end

  def test_session_runs_a_single_file_runbook_end_to_end
    with_single_file(SAMPLE) do |rb, _|
      with_runs_dir do |root|
        s = open_session(root, runbook: rb, inputs: { "TARGET" => "qa" })
        ex = s.execute("010-snapshot-the-database-1").wait
        assert ex.success?
        assert_equal "snapshot qa\n", ex.output
        assert_equal rb.dir, s.current.working_directory(rb.steps.first)
        assert_equal 1, s.history.size
      end
    end
  end

  def test_examples_load_clean
    %w[staging-teardown db-maintenance.md].each do |name|
      rb = Runsheets::Runbook.load(File.join(EXAMPLES, name))
      assert_empty rb.warnings, "#{name}: #{rb.warnings.join('; ')}"
      assert rb.steps.size >= 4
    end
  end

  def test_the_single_file_example_uses_sql_secrets_verify_and_rollback
    db = Runsheets::Runbook.load(File.join(EXAMPLES, "db-maintenance.md"))
    executable = db.steps.flat_map(&:blocks).select(&:executable?)
    assert db.single_file?
    assert_includes executable.map(&:lang), "sql", "sql blocks execute through the interpreters map"
    assert db.verify
    assert db.rollback
    refute_empty db.inputs.select(&:secret?)
  end

  def test_the_teardown_example_uses_every_block_kind
    teardown = Runsheets::Runbook.load(File.join(EXAMPLES, "staging-teardown"))
    kinds = teardown.steps.flat_map(&:blocks).map(&:kind).uniq
    assert_empty %i[run destructive terminal background expect] - kinds
    assert teardown.destructive?
  end
end
