# frozen_string_literal: true

require "test_helper"

class TestWizard < Minitest::Test
  include RunsheetsTest
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

  PICK = { "a" => "first", "b" => "second" }.freeze

  def test_choose_by_number_or_name
    asker = wizard("/x", "2\na\n")
    assert_equal "b", asker.choose("Pick", PICK)
    assert_equal "a", asker.choose("Pick", PICK)
  end

  def test_choose_takes_the_default_for_enter
    assert_equal "a", wizard("/x", "\n").choose("Pick", PICK)
    assert_equal "b", wizard("/x", "\n").choose("Pick", PICK, default: "b")
    assert_includes @output.string, "Choose [2]: "
  end

  def test_choose_asks_again_after_a_bad_pick
    assert_equal "b", wizard("/x", "9\n00\nb\n").choose("Pick", PICK)
    assert_includes @output.string, %("9" is not one of 1-2)
    assert_includes @output.string, %("00" is not one of 1-2)
  end

  def test_pick_takes_only_a_number_in_the_list_or_a_name
    assert_equal({ "1" => "a", "02" => "b", "b" => "b", "0" => nil, "00" => nil, "3" => nil, "-1" => nil, "c" => nil },
                 %w[1 02 b 0 00 3 -1 c].to_h { [it, Wizard.pick(%w[a b], it)] })
  end

  def test_a_bad_pick_with_nothing_more_to_read_is_an_error
    error = assert_raises(Runsheets::RunbookError) { wizard("/x", "9\n").choose("Pick", { "a" => "" }) }
    assert_equal %("9" is not one of 1-1), error.message
  end

  def test_ask_name_slugs_and_asks_again_while_the_name_is_taken
    with_scratch_dir("taken.md" => "x") do |dir|
      assert_equal "fresh", wizard(dir, "taken\n!!\nFresh\n").ask_name(:file)
      assert_includes @output.string, "already exists"
      assert_includes @output.string, "a name needs a letter or digit"
    end
  end

  def test_ask_parent_takes_what_was_typed_else_the_default
    assert_equal "/typed", wizard(nil, "/typed\n").ask_parent("/default")
    assert_equal "/default", wizard(nil, "\n").ask_parent("/default")
    assert_includes @output.string, "Directory to create the runbook in [/default]: "
  end

  def test_ask_parent_expands_the_home
    with_scratch_dir do |home|
      with_env("HOME" => home) { assert_equal File.join(home, "runbooks"), wizard(nil, "~/runbooks\n").ask_parent(nil) }
    end
    refute_includes @output.string, "a directory is needed", "a directory that does not exist yet is fine"
  end

  def test_ask_parent_asks_again_for_a_home_that_does_not_exist
    with_scratch_dir do |dir|
      assert_equal dir, wizard(nil, "~no-such-user-here/x\n#{dir}\n").ask_parent(nil)
      assert_includes @output.string, "cannot expand ~no-such-user-here/x"
    end
  end

  def test_parent_problem
    with_scratch_dir("a-file" => "x") do |dir|
      assert_equal "a directory is needed", Wizard.parent_problem(nil)
      assert_match(/is a file, not a directory/, Wizard.parent_problem(File.join(dir, "a-file")))
      assert_match(/cannot expand ~no-such-user-here/, Wizard.parent_problem("~no-such-user-here"))
      assert_nil Wizard.parent_problem(dir)
      assert_nil Wizard.parent_problem(File.join(dir, "not-yet"))
    end
  end

  def test_name_problem
    with_scratch_dir("taken.md" => "x", "full/a" => "x") do |dir|
      assert_equal "a name needs a letter or digit", Wizard.name_problem(dir, "", :directory)
      assert_match(/already exists/, Wizard.name_problem(dir, "taken", :file))
      assert_nil Wizard.name_problem(dir, "taken", :directory), "a directory called taken is free"
      assert_match(/not empty/, Wizard.name_problem(dir, "full", :directory))
      assert_match(/not empty/, Wizard.name_problem(dir, "full", :folder))
      assert_nil Wizard.name_problem(dir, "full", :file), "full.md is free"
    end
  end

  def test_layout_follows_the_shape_and_the_template
    assert_equal(%i[directory directory file folder],
                 [["directory", false], ["directory", true], ["single-file", false], ["single-file", true]].map { Wizard.layout(*it) })
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

  def test_confirm_is_yes_unless_the_answer_is_no
    asker = wizard("/x", "\nyes\nNo\n")
    assert asker.confirm?("Go?"), "Enter"
    assert asker.confirm?("Go?"), "yes"
    refute asker.confirm?("Go?"), "No"
    assert asker.confirm?("Go?"), "no more input"
    assert_equal "#{"\nGo? [Y/n]: " * 4}\n", @output.string
  end

  def test_ask_all_gathers_the_answers_with_defaults_from_the_name
    answers = with_scratch_dir { wizard(it, "2\n\nShip It\n\n\n\n").ask_all }
    assert_equal ["single-file", :file, Runsheets::Template::DEFAULT, "ship-it", "Ship it"],
                 [answers.shape, answers.layout, answers.template, answers.name, answers.title]
    assert_equal Wizard::DEFAULTS.values_at(:when_to_use, :escalation), [answers.when_to_use, answers.escalation]
    assert_equal ["ship-it.md", "ship-it.md"], [answers.location, answers.main]
  end

  def test_a_single_file_from_a_template_with_support_files_gets_a_folder
    answers = with_scratch_dir { wizard(it, "2\nasgard\nShip It\n").ask_all }
    assert_equal [:folder, "ship-it", "ship-it/ship-it.md"], [answers.layout, answers.location, answers.main]
    assert_includes @output.string, "Name (the directory name)"
  end

  def test_a_single_file_in_a_folder_needs_the_folder_name_free
    with_scratch_dir("ship-it/x" => "x", "free.md" => "x") do |dir|
      answers = wizard(dir, "2\nasgard\nship-it\nfree\n").ask_all
      assert_equal "free", answers.name, "free.md does not stand in the way of a folder called free"
      assert_includes @output.string, "ship-it exists and is not empty"
    end
  end

  def test_write_checks_again_that_the_name_is_free
    with_scratch_dir("n/x" => "x") do |dir|
      answers = answers_for(:directory)
      error   = assert_raises(Runsheets::RunbookError) { wizard(dir).write(answers) }
      assert_match(/not empty/, error.message)
    end
  end

  def test_location_is_what_a_runbook_creates_in_its_parent
    assert_equal(%w[n n.md n], %i[directory file folder].map { Wizard.location("n", it) })
  end

  def test_a_rejected_answer_is_not_replaced_by_the_default_when_input_runs_out
    with_scratch_dir("taken.md" => "x") do |dir|
      error = assert_raises(Runsheets::RunbookError) { wizard(dir, "taken\n").ask_name(:file) }
      assert_match(/already exists/, error.message)
    end
  end

  def answers_for(layout, template: "tasks")
    Wizard::Answers.new(template:, name: "n", title: "N", when_to_use: "w", escalation: "e", layout:)
  end

  def test_a_directory_runbook_is_placed_in_its_directory
    files = wizard("/x").files(answers_for(:directory))
    assert_includes files.keys, "n/runbook.md"
    assert_includes files.keys, "n/steps/010-preflight.md"
  end

  def test_a_single_file_runbook_is_one_file
    files = wizard("/x").files(answers_for(:file))
    assert_equal ["n.md"], files.keys
    assert_includes files["n.md"], "\n## Preflight\n", "the steps are sections of the one file"
  end

  def test_a_single_file_with_support_files_is_placed_in_its_folder
    files = wizard("/x").files(answers_for(:folder, template: "asgard"))
    assert_equal %w[n/.loki n/n.md n/tasks.loki], files.keys.sort
    assert_includes files["n/n.md"], "\n## Preflight\n"
  end

  def test_no_templates_is_an_error
    error = assert_raises(Runsheets::RunbookError) { Wizard.new("/x", templates: []) }
    assert_equal "no runbook templates to offer", error.message
  end
end
