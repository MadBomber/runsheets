# frozen_string_literal: true

require "test_helper"

class TestTemplate < Minitest::Test
  include RunsheetsTest::CliFixtures
  include RunsheetsTest::TemplateFixtures

  Template = Runsheets::Template

  def test_the_bundled_templates_are_listed_simplest_first
    names = Template.all.map(&:name)
    assert_equal %w[checks tasks rollback timeouts inputs asgard], names
    assert_includes names, Template::DEFAULT
    assert Template.all.all? { !it.description.empty? }, "every template describes itself for the menu"
  end

  def test_render_fills_in_the_answers_and_drops_erb
    files = bundled_template("tasks").render(template_context)
    assert_includes files.keys, "runbook.md"
    assert_includes files.keys, "steps/010-preflight.md"
    assert(files.keys.none? { it.end_with?(".erb") })
    assert_includes files["runbook.md"], %(title: "Db refresh")
    assert_includes files["runbook.md"], %(escalation: "#ops")
    assert_includes files["runbook.md"], "default: /tmp/db-refresh"
  end

  def test_render_copies_plain_files_and_renders_dotfiles
    files = bundled_template("asgard").render(template_context)
    assert_equal File.read(File.join(Template::DIR, "asgard", "tasks.loki")), files["tasks.loki"]
    assert_includes files[".loki"], "db-refresh: tasks for the Db refresh runbook"
    refute files.key?("template.yml")
  end

  def test_runbook_files_and_support_files
    assert Template.runbook_file?("runbook.md")
    assert Template.runbook_file?("steps/010-a.md")
    assert Template.runbook_file?("rollback.md")
    refute Template.runbook_file?(".loki")
    refute Template.runbook_file?("steps/helper.sh")
    refute Template.runbook_file?("docs/notes.md")
    assert_equal({ ".loki" => "x" }, Template.support_files("runbook.md" => "r", ".loki" => "x"))
    assert bundled_template("asgard").support_files?
    refute bundled_template("tasks").support_files?
  end

  def test_templates_sort_by_their_order_then_name
    files = { "b/template.yml" => "order: 1\n", "a/template.yml" => "order: 2\n", "c/runbook.md.erb" => "x", "d/template.yml" => "order: soon\n" }
    with_scratch_dir(files) do |dir|
      all = Template.all(root: dir)
      assert_equal %w[b a c d], all.map(&:name)
      assert_equal [1, 2, Template::UNORDERED, Template::UNORDERED], all.map(&:order), "an order that is not a number is none"
    end
  end

  def test_every_template_checks_clean_in_both_shapes
    shapes   = templates_in_both_shapes
    warned   = shapes.transform_values { |runbooks| runbooks.flat_map(&:warnings) }.reject { _2.empty? }
    differed = shapes.transform_values { |runbooks| runbooks.map { outline(it) }.uniq }.reject { _2.one? }
    assert_equal Template.all.map(&:name), shapes.keys
    assert_empty warned, "templates with warnings in either shape"
    assert_empty differed, "templates whose steps differ between the shapes"
  end

  def test_titles_yaml_would_misread_stay_strings
    titles    = %w[null yes 0x1F]
    tasks     = bundled_template("tasks")
    directory = titles.map { Runsheets::FrontMatter.parse(tasks.render(template_context(title: it))["runbook.md"]).data["title"] }
    single    = titles.map { Runsheets::FrontMatter.parse(single_file_text(tasks, title: it)).data["title"] }
    assert_equal titles, directory
    assert_equal titles, single
  end

  def test_no_templates_is_an_error_naming_where_it_looked
    with_scratch_dir do |dir|
      error = assert_raises(Runsheets::RunbookError) { Template.all(root: dir) }
      assert_equal "no runbook templates found in #{dir}", error.message
    end
  end

  def test_a_template_yml_that_is_not_a_mapping_is_ignored
    with_scratch_dir("odd/template.yml" => "- a\n", "odd/runbook.md.erb" => "x") do |dir|
      odd = Template.all(root: dir).first
      assert_equal "", odd.description
      assert_equal Template::UNORDERED, odd.order
    end
  end

  def test_the_asgard_header_is_a_ruby_string_whatever_the_title
    ['Fix "prod"', "Run \#{exit 1}", "Back\\slash"].each do |title|
      loki   = bundled_template("asgard").render(template_context(title:))[".loki"]
      header = loki[/^  header (.+)$/, 1]
      assert_equal "db-refresh: tasks for the #{title} runbook", RubyVM::InstructionSequence.compile("#{header}.itself").eval, title
      assert RubyVM::InstructionSequence.compile(loki), "#{title}: the .loki file parses"
    end
  end

  def test_a_template_directory_without_template_yml_has_no_description
    with_scratch_dir("plain/runbook.md.erb" => "x") do |dir|
      plain = Template.all(root: dir).first
      assert_equal "plain", plain.name
      assert_equal "", plain.description
    end
  end
end
