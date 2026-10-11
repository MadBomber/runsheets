# frozen_string_literal: true

require "test_helper"

class TestWizard < Minitest::Test
  include RunsheetsTest::CliFixtures

  Wizard = Runsheets::Wizard

  def wizard(parent, typed = "", default_parent: nil)
    @output = StringIO.new
    Wizard.new(parent, input: StringIO.new(typed), output: @output, default_parent:)
  end

  def test_slug_makes_a_safe_basename
    assert_equal "db-refresh", Wizard.slug("  DB Refresh! ")
    assert_equal "db-refresh", Wizard.slug("db-refresh.md")
    assert_equal "etc-passwd", Wizard.slug("../../etc/passwd")
    assert_equal "", Wizard.slug("!!!")
  end

  def test_title_for_a_name
    assert_equal "Db refresh", Wizard.title_for("db-refresh")
    assert_equal "Nightly backup", Wizard.title_for("nightly_backup")
  end

  def test_conflict_names_an_existing_file_or_a_full_directory
    with_scratch_dir("file.md" => "x", "full/a" => "x") do |dir|
      FileUtils.mkdir(File.join(dir, "empty"))
      assert_match(/already exists/, Wizard.conflict(File.join(dir, "file.md")))
      assert_match(/not empty/, Wizard.conflict(File.join(dir, "full")))
      assert_nil Wizard.conflict(File.join(dir, "empty"))
      assert_nil Wizard.conflict(File.join(dir, "absent"))
    end
  end

  def test_ask_takes_the_default_for_a_blank_or_missing_answer
    assert_equal "typed", wizard("/x", "typed\n").ask("Q", default: "d")
    assert_equal "d", wizard("/x", "\n").ask("Q", default: "d")
    assert_equal "d", wizard("/x").ask("Q", default: "d")
    assert_includes @output.string, "Q [d]: "
  end

  def test_choose_by_number_or_name_and_asks_again_after_a_bad_pick
    options = { "a" => "first", "b" => "second" }
    assert_equal "b", wizard("/x", "2\n").choose("Pick", options)
    assert_equal "b", wizard("/x", "b\n").choose("Pick", options)
    assert_equal "a", wizard("/x", "\n").choose("Pick", options)
    assert_equal "b", wizard("/x", "\n").choose("Pick", options, default: "b")
    assert_includes @output.string, "Choose [2]: "
    assert_equal "b", wizard("/x", "9\n0\nb\n").choose("Pick", options)
    assert_includes @output.string, %("9" is not one of 1-2)
  end

  def test_a_bad_pick_with_nothing_more_to_read_is_an_error
    assert_raises(Runsheets::RunbookError) { wizard("/x", "9\n").choose("Pick", { "a" => "" }) }
  end

  def test_ask_name_slugs_and_asks_again_while_the_name_is_taken
    with_scratch_dir("taken.md" => "x") do |dir|
      assert_equal "fresh", wizard(dir, "taken\n!!\nFresh\n").ask_name("single-file")
      assert_includes @output.string, "already exists"
      assert_includes @output.string, "a name needs a letter or digit"
    end
  end

  def test_ask_parent_takes_what_was_typed_else_the_default
    assert_equal "/typed", wizard(nil, "/typed\n").ask_parent("/default")
    assert_equal "/default", wizard(nil, "\n").ask_parent("/default")
    assert_includes @output.string, "Directory to create the runbook in [/default]: "
    assert_equal File.join(Dir.home, "runbooks"), wizard(nil, "~/runbooks\n").ask_parent(nil)
  end

  def test_ask_parent_asks_again_for_a_blank_with_no_default_or_a_file
    with_scratch_dir("a-file" => "x") do |dir|
      assert_equal dir, wizard(nil, "\n#{dir}/a-file\n#{dir}\n").ask_parent(nil)
      assert_includes @output.string, "Directory to create the runbook in: "
      assert_includes @output.string, "a directory is needed"
      assert_includes @output.string, "a-file is a file, not a directory"
    end
  end

  def test_run_asks_for_the_parent_when_none_was_given
    with_scratch_dir do |dir|
      assert_equal 0, wizard(nil, "\n\n\nmade\n", default_parent: dir).run
      assert File.file?(File.join(dir, "made", "runbook.md"))
    end
  end

  def test_confirm_is_yes_unless_the_answer_starts_with_n
    assert wizard("/x", "\n").confirm?("Go?")
    assert wizard("/x", "yes\n").confirm?("Go?")
    refute wizard("/x", "No\n").confirm?("Go?")
  end

  def test_ask_all_gathers_the_answers_with_defaults_from_the_name
    answers = wizard("/x", "2\n\nShip It\n\n\n\n").ask_all
    assert_equal ["single-file", Runsheets::Template::DEFAULT, "ship-it", "Ship it"], [answers.shape, answers.template, answers.name, answers.title]
    assert_equal Wizard::DEFAULT_WHEN_TO_USE, answers.when_to_use
    assert_equal Wizard::DEFAULT_ESCALATION, answers.escalation
    refute answers.folder
    assert_equal ["ship-it.md", "ship-it.md"], [answers.location, answers.main]
  end

  def test_a_single_file_from_a_template_with_support_files_gets_a_folder
    answers = wizard("/x", "2\nasgard\nShip It\n").ask_all
    assert answers.folder
    assert_equal ["ship-it", "ship-it/ship-it.md"], [answers.location, answers.main]
    assert_includes @output.string, "Name (the directory name)"
  end

  def test_location_is_what_a_runbook_creates_in_its_parent
    assert_equal "n", Wizard.location("n", single_file: false)
    assert_equal "n.md", Wizard.location("n", single_file: true)
    assert_equal "n", Wizard.location("n", single_file: true, folder: true)
  end

  def test_files_are_placed_under_the_runbook_location
    answers = Wizard::Answers.new(shape: "directory", template: "tasks", name: "n", title: "N", when_to_use: "w", escalation: "e", folder: false)
    assert_includes wizard("/x").files(answers).keys, "n/runbook.md"
    assert_equal ["n.md"], wizard("/x").files(answers.with(shape: "single-file")).keys
    asgard = answers.with(shape: "single-file", template: "asgard", folder: true)
    assert_equal %w[n/.loki n/n.md n/tasks.loki], wizard("/x").files(asgard).keys.sort
  end

  def test_an_empty_template_directory_is_an_error
    assert_raises(Runsheets::RunbookError) { Wizard.new("/x", templates: []) }
  end
end
