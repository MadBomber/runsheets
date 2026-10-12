# frozen_string_literal: true

module RunsheetsTest
  # Fixtures for the Template tests: the bundled templates, the answers
  # they are rendered with, and each one written out in both shapes.
  module TemplateFixtures
    # The bundled template called +name+.
    def bundled_template(name) = Runsheets::Template.all.find { it.name == name }

    # The answers a template is rendered with.
    def template_context(single_file: false, title: "Db refresh")
      Runsheets::Template::Context.new(name: "db-refresh", title:, when_to_use: "Monthly", escalation: "#ops", single_file:)
    end

    # Every bundled template written in both shapes and loaded, by name:
    # [the directory runbook, the single-file runbook].
    def templates_in_both_shapes
      Dir.mktmpdir("runsheets-templates") do |dir|
        Runsheets::Template.all.to_h do |template|
          [template.name, [write_directory(template, dir), write_single_file(template, dir)].map { Runsheets::Runbook.load(it) }]
        end
      end
    end

    # What a runbook's shape must not change: its steps' titles and kinds,
    # and which of verify and rollback it has.
    def outline(runbook) = [runbook.steps.map(&:title), runbook.steps.map(&:kind), runbook.extras.keys]

    # The single-file runbook +template+ renders, as its text.
    def single_file_text(template, title: "Db refresh")
      Runsheets::SingleFile.from_directory(template.render(template_context(single_file: true, title:)))
    end

    private

    def write_directory(template, dir)
      root = File.join(dir, template.name)
      template.render(template_context).each do |rel, text|
        path = File.join(root, rel)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, text)
      end
      root
    end

    def write_single_file(template, dir)
      File.join(dir, "#{template.name}.md").tap { File.write(it, single_file_text(template)) }
    end
  end
end
