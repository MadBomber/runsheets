# frozen_string_literal: true

require "test_helper"

# `runsheets --run STEP`: one step of a runbook run at the terminal.
class TestStepRunner < Minitest::Test
  include RunsheetsTest
  include RunsheetsTest::SessionFixtures
  include RunsheetsTest::StepRunnerFixtures

  StepRunner = Runsheets::StepRunner

  def test_find_step_by_slug_number_name_or_role
    rb = example_runbook
    assert_equal "010-say-hello", StepRunner.find_step(rb, "010-say-hello").slug
    assert_equal "010-say-hello", StepRunner.find_step(rb, "010").slug
    assert_equal "010-say-hello", StepRunner.find_step(rb, "10").slug
    assert_equal "020-inspect-ruby", StepRunner.find_step(rb, " inspect-ruby ").slug
    assert_equal "verify", StepRunner.find_step(rb, "verify").slug
    assert_equal "runbook", StepRunner.find_step(rb, "runbook").slug
  end

  def test_find_step_names_the_steps_when_nothing_matches
    error = assert_raises(Runsheets::RunbookError) { StepRunner.find_step(example_runbook, "nope") }
    assert_match(/no step "nope" in Hello, runsheets; steps: runbook, 010-say-hello/, error.message)
  end

  def test_find_step_refuses_a_name_that_matches_two_steps
    with_runbook("runbook.md" => "---\ntitle: Twins\n---\n", "steps/010-a.md" => "A\n", "steps/010-b.md" => "B\n") do |rb|
      error = assert_raises(Runsheets::RunbookError) { StepRunner.find_step(rb, "10") }
      assert_match(/"10" matches 010-a, 010-b/, error.message)
    end
  end

  def test_choices_are_the_steps_then_verify_and_rollback
    assert_equal %w[010-say-hello 020-inspect-ruby 030-take-a-breath 035-keep-a-clock-running 040-exercise-failure 045-check-the-greeting verify rollback],
                 StepRunner.choices(example_runbook).map(&:slug)
  end

  def test_choices_start_with_a_landing_page_that_has_blocks
    with_runbook("runbook.md" => "---\ntitle: T\n---\n\n```bash run\necho hi\n```\n", "steps/010-a.md" => "A\n") do |rb|
      assert_equal %w[runbook 010-a], StepRunner.choices(rb).map(&:slug)
    end
  end

  def test_choice_lines_number_the_steps_and_mark_those_for_the_page_only
    lines = StepRunner.choice_lines(StepRunner.choices(example_runbook))
    assert_equal "   1) 010-say-hello             Say hello", lines.first
    assert_equal "   4) 035-keep-a-clock-running  Keep a clock running  (page only)", lines[3]
  end

  def test_pick_step_takes_a_place_in_the_list_or_a_name
    rb      = example_runbook
    choices = StepRunner.choices(rb)
    assert_equal "020-inspect-ruby", StepRunner.pick_step(rb, choices, "2").slug
    assert_equal "verify", StepRunner.pick_step(rb, choices, "7").slug
    assert_equal "045-check-the-greeting", StepRunner.pick_step(rb, choices, "045").slug, "a leading zero is a step number"
    assert_equal "030-take-a-breath", StepRunner.pick_step(rb, choices, "take-a-breath").slug
    assert_nil StepRunner.pick_step(rb, choices, "")
    assert_nil StepRunner.pick_step(rb, choices, "99")
    assert_nil StepRunner.pick_step(rb, choices, "nope")
  end

  def test_choose_step_lists_the_steps_and_asks_again_after_a_wrong_answer
    out  = StringIO.new
    step = StepRunner.choose_step(example_runbook, input: StringIO.new("nope\n3\n"), output: out)
    assert_equal "030-take-a-breath", step.slug
    assert_includes out.string, "Steps in Hello, runsheets:\n   1) 010-say-hello"
    assert_includes out.string, "\"nope\" is not one of the steps\nWhich step? "
  end

  def test_choose_step_with_no_answer_is_an_error
    error = assert_raises(Runsheets::RunError) { StepRunner.choose_step(example_runbook, input: StringIO.new(""), output: StringIO.new) }
    assert_equal "no step chosen", error.message
  end

  def test_refusal_is_for_a_step_with_a_background_block
    rb = example_runbook
    assert_match(/035-keep-a-clock-running has a background block .* start it from the page/, StepRunner.refusal(rb.step("035-keep-a-clock-running")))
    assert_nil StepRunner.refusal(rb.step("010-say-hello"))
  end

  def test_blank_inputs_are_the_declared_inputs_the_step_uses_without_a_value
    text = fixture_runbook({ "Use" => "```bash run\necho $TARGET $OTHER\n```" },
                           front: "inputs:\n  - name: TARGET\n  - name: UNUSED\n")
    with_single_file(text) do |rb, _|
      step = rb.step("010-use")
      assert_equal ["TARGET"], StepRunner.blank_inputs(rb, step, {}).map(&:name)
      assert_empty StepRunner.blank_inputs(rb, step, { "TARGET" => "x" })
    end
  end

  def test_mismatch_lines_mark_expected_and_actual
    result = Runsheets::Expectation.compare("same\nwanted\n", "same\ngot\n")
    assert_equal ["- wanted", "+ got"], StepRunner.mismatch_lines(result)
  end

  def test_a_step_that_succeeds_is_marked_done
    outcome = run_step(fixture_runbook({ "Greet" => "```bash run\necho hi\n```" }), "greet")
    assert_equal 0, outcome.status
    assert_includes outcome.out, "Greet [010-greet]"
    assert_equal "done", outcome.step_status("010-greet")
  end

  def test_a_failing_block_stops_the_step
    body = "```bash run\nexit 3\n```\n\n```bash run\necho never\n```"
    outcome = run_step(fixture_runbook({ "Fail" => body }), "010")
    assert_equal 1, outcome.status
    assert_includes outcome.out, "010-fail-1: finished exit 3"
    assert_equal 1, outcome.executions.size, "the block after the failure did not run"
    assert_nil outcome.step_status("010-fail")
  end

  def test_output_is_checked_against_the_expect_block
    good = run_step(fixture_runbook({ "Echo" => "```bash run\necho hello 42\n```\n\n```text expect\nhello {{any}}\n```" }), "echo")
    bad  = run_step(fixture_runbook({ "Echo" => "```bash run\necho goodbye\n```\n\n```text expect\nhello\n```" }), "echo")
    assert_equal 0, good.status
    assert_equal 1, bad.status
    assert_includes bad.out, "the output is not what the expect block says:\n  - hello\n  + goodbye"
  end

  def test_a_destructive_block_runs_once_its_code_is_typed
    outcome = run_step(fixture_runbook({ "Drop" => "```bash destructive\necho dropped\n```" }), "drop", input: ->(out) { CodeTyper.new(out) })
    assert_equal 0, outcome.status
    assert_match(/010-drop-1 is destructive. Type \h{4} to run it: /, outcome.out)
    assert outcome.executions.first.success?
  end

  def test_a_destructive_block_does_not_run_without_its_code
    outcome = run_step(fixture_runbook({ "Drop" => "```bash destructive\necho dropped\n```" }), "drop", input: "wrong\n")
    assert_equal 1, outcome.status
    assert_includes outcome.out, "010-drop-1: not confirmed"
    assert_empty outcome.executions
  end

  def test_a_terminal_block_is_acknowledged_with_a_note
    outcome = run_step(fixture_runbook({ "Look" => "```bash terminal\nless /etc/hosts\n```" }), "look", input: "y\nall fine\n")
    assert_equal 0, outcome.status
    assert_includes outcome.out, "Run this yourself:\n  less /etc/hosts\nDid you run it? [y/N]: "
    assert_equal "all fine", outcome.acks["010-look-1"][:note]
  end

  def test_a_terminal_block_not_run_fails_the_step
    outcome = run_step(fixture_runbook({ "Look" => "```bash terminal\nless /etc/hosts\n```" }), "look")
    assert_equal 1, outcome.status
    assert_includes outcome.out, "010-look-1: not confirmed"
  end

  def test_a_manual_step_is_shown_and_marked_done_when_the_operator_says_so
    text = fixture_runbook({ "Think" => "Have a think." })
    done = run_step(text, "think", input: "yes\n")
    not_done = run_step(text, "think")
    assert_equal 0, done.status
    assert_includes done.out, "Have a think.\n\nDone? [y/N]: "
    assert_equal "done", done.step_status("010-think")
    assert_equal 1, not_done.status
    assert_includes not_done.out, "010-think: not done"
  end

  def test_a_blank_input_the_step_uses_must_be_given
    text = fixture_runbook({ "Use" => "```bash run\necho \"target=$TARGET\"\n```" }, front: "inputs:\n  - name: TARGET\n    prompt: Which host?\n")
    with_env("TARGET" => nil) do
      outcome = run_step(text, "use", input: "db1\n")
      assert_equal 0, outcome.status
      assert_includes outcome.out, "Which host? (TARGET): "
      assert_includes outcome.outputs.first, "target=db1"
      error = assert_raises(Runsheets::RunError) { run_step(text, "use") }
      assert_match(/TARGET has no value; the step needs it/, error.message)
    end
  end

  def test_every_input_of_the_runbook_is_asked_for_with_its_value_as_the_default
    text = fixture_runbook({ "Greet" => "```bash run\necho \"$NAME $COLOR $TOKEN\"\n```" },
                           front: "inputs:\n  - name: NAME\n    default: world\n  - name: COLOR\n    prompt: Which colour?\n    default: red\n  " \
                                  "- name: TOKEN\n    default: s3cret\n    secret: true\n  - name: UNUSED\n")
    with_env("NAME" => nil, "COLOR" => nil, "TOKEN" => nil, "UNUSED" => nil) do
      outcome = run_step(text, "greet", input: "\nblue\n\n\n")
      assert_equal 0, outcome.status
      assert_includes outcome.out, "NAME (NAME) [world]: Which colour? (COLOR) [red]: TOKEN (TOKEN) [set]: UNUSED (UNUSED): "
      assert_includes outcome.outputs.first, "world blue [redacted TOKEN]"
    end
  end

  def test_once_input_runs_out_the_inputs_keep_their_values_unasked
    text = fixture_runbook({ "Greet" => "```bash run\necho \"$A $B $C\"\n```" },
                           front: "inputs:\n  - name: A\n    default: one\n  - name: B\n    default: two\n  - name: C\n    default: three\n")
    with_env("A" => nil, "B" => nil, "C" => nil) do
      outcome = run_step(text, "greet", input: "uno\n")
      assert_equal 0, outcome.status
      refute_includes outcome.out, "C (C)", "B found the end of input; C is not asked"
      assert_includes outcome.outputs.first, "uno two three"
    end
  end

  def test_shown_never_shows_a_secret
    plain  = Runsheets::Runbook::Input.new(name: "A", prompt: nil, default: nil, secret: false)
    secret = plain.with(secret: true)
    assert_equal " [x]", StepRunner.shown(plain, "x")
    assert_equal " [set]", StepRunner.shown(secret, "x")
    assert_equal "", StepRunner.shown(secret, "")
  end

  def test_a_background_block_is_refused_before_anything_runs
    text = fixture_runbook({ "Tail" => "```bash background\nsleep 5\n```" })
    error = assert_raises(Runsheets::RunError) { run_step(text, "tail") }
    assert_match(/has a background block/, error.message)
  end
end
