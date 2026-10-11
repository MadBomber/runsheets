# frozen_string_literal: true

require "test_helper"

class TestTemplate < Minitest::Test
  include RunsheetsTest::CliFixtures

  Template = Runsheets::Template

  def template(name) = Template.all.find { it.name == name }

  def context(single_file: false, title: "Db refresh")
    Template::Context.new(name: "db-refresh", title:, when_to_use: "Monthly", escalation: "#ops", single_file:)
  end

  def test_the_bundled_templates_are_listed_simplest_first
    names = Template.all.map(&:name)
    assert_equal %w[checks tasks rollback timeouts inputs asgard], names
    assert_includes names, Template::DEFAULT
    assert Template.all.all? { !it.description.empty? }, "every template describes itself for the menu"
  end

  def test_render_fills_in_the_answers_and_drops_erb
    files = template("tasks").render(context)
    assert_includes files.keys, "runbook.md"
    assert_includes files.keys, "steps/010-preflight.md"
    assert(files.keys.none? { it.end_with?(".erb") })
    assert_includes files["runbook.md"], %(title: "Db refresh")
    assert_includes files["runbook.md"], %(escalation: "#ops")
    assert_includes files["runbook.md"], "default: /tmp/db-refresh"
  end

  def test_render_copies_plain_files_and_renders_dotfiles
    files = template("asgard").render(context)
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
    assert template("asgard").support_files?
    refute template("tasks").support_files?
  end

  def test_templates_sort_by_their_order_then_name
    files = { "b/template.yml" => "order: 1\n", "a/template.yml" => "order: 2\n", "c/runbook.md.erb" => "x", "d/template.yml" => "order: soon\n" }
    with_scratch_dir(files) do |dir|
      assert_equal %w[b a c d], Template.all(root: dir).map(&:name)
    end
  end

  def test_single_file_joins_the_steps_under_headings_with_their_attributes
    files = { "runbook.md" => "---\ntitle: T\n---\n\n# T\n\nPreamble.\n",
              "steps/020-b.md" => "---\ntitle: Second\nkind: manual\n---\n\nDo B.\n",
              "steps/010-a.md" => "Do A.\n",
              "rollback.md" => "---\ntitle: Rollback\n---\n\nUndo.\n" }
    text = Template.single_file(files)
    assert_equal "---\ntitle: T\n---\n\n# T\n\nPreamble.\n\n## A\n\nDo A.\n\n## Second\n<!-- kind: manual -->\n\nDo B.\n\n## Rollback\n\nUndo.\n", text
  end

  def test_attributes_quote_only_what_yaml_would_misread
    assert_equal "kind: automated, timeout: 300, destructive: true", Template.attributes("kind" => "automated", "timeout" => 300, "destructive" => true)
    assert_equal %(cwd: "yes", note: "a: b", id: "010"), Template.attributes("cwd" => "yes", "note" => "a: b", "id" => "010")
  end

  def test_every_template_checks_clean_in_both_shapes
    Template.all.each do |template|
      with_scratch_dir do |dir|
        directory = File.join(dir, template.name)
        single    = File.join(dir, "#{template.name}.md")
        template.render(context).each do |rel, text|
          FileUtils.mkdir_p(File.dirname(File.join(directory, rel)))
          File.write(File.join(directory, rel), text)
        end
        File.write(single, Template.single_file(template.render(context(single_file: true))))
        by_dir  = Runsheets::Runbook.load(directory)
        by_file = Runsheets::Runbook.load(single)
        assert_empty by_dir.warnings, "#{template.name} as a directory"
        assert_empty by_file.warnings, "#{template.name} as a single file"
        assert_equal by_dir.steps.map(&:title), by_file.steps.map(&:title), "#{template.name}: the same steps either way"
        assert_equal by_dir.steps.map(&:kind), by_file.steps.map(&:kind)
        assert_equal by_dir.extras.keys, by_file.extras.keys
      end
    end
  end

  def test_titles_yaml_would_misread_stay_strings
    %w[null yes 0x1F].each do |title|
      files = Template.all.first.render(context(title:))
      assert_equal title, Runsheets::FrontMatter.parse(files["runbook.md"]).data["title"]
    end
  end

  def test_a_template_directory_without_template_yml_has_no_description
    with_scratch_dir("plain/runbook.md.erb" => "x") do |dir|
      assert_equal([["plain", ""]], Template.all(root: dir).map { [it.name, it.description] })
    end
  end
end
