# frozen_string_literal: true

# Only the test tasks live here. Build, install and release come from the
# shared asgard gem tasks (see .loki); the shared quality gate runs
# `rake test`, and `asgard test_verbose` runs `rake test_verbose`.
require "minitest/test_task"

Minitest::TestTask.create
Minitest::TestTask.create(:test_verbose) { it.extra_args << "-v" }

task default: :test
