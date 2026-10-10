# frozen_string_literal: true

require_relative "lib/runsheets/version"

Gem::Specification.new do |spec|
  spec.name = "runsheets"
  spec.version = Runsheets::VERSION
  spec.authors = ["Dewayne VanHoozer"]
  spec.email = ["dewayne@vanhoozer.me"]

  spec.summary = "Executable runbooks: markdown steps rendered in the browser, run and recorded."

  spec.description = <<~DESC
    runsheets turns a directory of markdown files into an executable runbook served
    from a local web page. Fenced code blocks the author marks as runnable get a Run
    button; every execution, its output, exit status and timing, and every operator
    acknowledgement is captured in order into a run record (the runsheet). The tool
    binds to loopback only, executes only blocks that opt in, and modifies nothing in
    the runbook directory.
  DESC

  spec.homepage = "https://github.com/madbomber/runsheets"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[Gemfile . test/ docs/ site/ PLAN.md Rakefile mkdocs.yml]) || f.end_with?("_output.txt")
    end
  end

  # The one executable, `runsheets`, lives in bin/. There is no exe/ directory
  # and no other scripts under bin/.
  spec.bindir = "bin"
  spec.executables = spec.files.grep(%r{\Abin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "sinatra",              "~> 4.1"
  spec.add_dependency "rackup",               "~> 2.1"
  spec.add_dependency "puma",                 ">= 6.4"
  spec.add_dependency "kramdown",             "~> 2.4"
  spec.add_dependency "kramdown-parser-gfm",  "~> 1.1"
  spec.add_dependency "rouge",                ">= 4.0"
  spec.add_dependency "myway_config",         "~> 0.1"
  spec.add_dependency "logger" # a bundled gem since Ruby 3.5; the session log uses it
end
