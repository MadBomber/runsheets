# frozen_string_literal: true

require "test_helper"

# Regression tests for the problems a review found: each test names the
# failure it guards against.
class TestHardening < Minitest::Test
  include RunsheetsTest::HardeningFixtures

  LONG_OUTPUT = {
    "runbook.md" => "---\ntitle: T\n---\n",
    "steps/010-a.md" => "```bash run\nfor i in $(seq 1 20000); do echo héllo; done\n```\n"
  }.freeze

  SECRET_AND_TWO_BLOCKS = {
    "runbook.md" => "---\ntitle: T\ninputs:\n  - name: SECRET\n    secret: true\n---\n",
    "steps/010-a.md" => "```bash run\nprintf %s hunt; sleep 0.3; printf %s er2-end\n```\n```bash run\necho B-out\n```\n"
  }.freeze

  # --- records ------------------------------------------------------------

  def test_run_md_keeps_output_notes_and_values_as_text
    with_runs_dir do |root|
      s   = open_session(root, inputs: { "NAME" => "<b>bold</b>" })
      run = s.current
      step = s.runbook.step("010-say-hello")
      run.mark_step(step.slug, status: "done", note: "<meta http-equiv=refresh content=0> *not em*")
      md = File.read(File.join(s.run.dir, "run.md"))
      html = Runsheets::Renderer.render(md, id_prefix: "run").html
      refute_includes md, "<meta"
      refute_includes html, "<meta"
      refute_includes html, "<em>not em</em>"
      refute_includes html, "<b>bold</b>", "the value is code, shown as text"
    end
  end

  def test_output_fence_cannot_be_closed_by_the_output
    assert_equal "````", Runsheets::RunRecord.fence_for("a ``` b")
    assert_equal "```", Runsheets::RunRecord.fence_for("plain")
    assert_equal("`` a`b ``", Runsheets::RunRecord.code_span("a`b").then { "`` #{it[2..-3].strip} ``" })
  end

  def test_large_non_ascii_output_keeps_the_record_writable
    with_session_on(LONG_OUTPUT) do |s|
      ran = s.execute("010-a-1").wait
      s.mark_step("010-a", status: "done")
      md = File.read(File.join(s.run.dir, "run.md"))
      s.end!("test")
      assert ran.success?
      assert_includes md, "earlier bytes omitted"
      assert s.ended?
      assert_equal "completed", s.current.record.status
    end
  end

  def test_input_values_are_valid_text_without_nul
    assert_equal "a�b", Runsheets::Run.clean("a\xFFb".b)
    assert_equal "ab", Runsheets::Run.clean("a\u0000b")
  end

  # --- runs and sessions ----------------------------------------------------

  def test_each_execution_gets_its_own_redactor
    with_session_on(SECRET_AND_TWO_BLOCKS, inputs: { "SECRET" => "hunter2" }) do |s|
      a = s.execute("010-a-1")
      sleep 0.1
      b = s.execute("010-a-2").wait
      a.wait
      assert_equal "B-out\n", b.output, "nothing of the other execution's output"
      assert_equal "[redacted SECRET]-end", a.output
    end
  end

  def test_a_closing_run_refuses_new_executions
    with_runs_dir do |root|
      s = open_session(root)
      bg = s.execute("035-keep-a-clock-running-1")
      closer = end_in_background(s)
      error = assert_raises(Runsheets::RunError) { s.execute("010-say-hello-1") }
      closer.join
      assert_match(/ended/, error.message)
      assert bg.stopped?
      assert_empty s.running
    end
  end

  def test_selecting_a_runbook_twice_at_once_opens_one_run
    with_runs_dir do |root|
      s    = start_session(root)
      runs = Array.new(5) { Thread.new { s.open(example_runbook) } }.map(&:value)
      assert_equal 1, runs.uniq.size
      assert_equal [s.id], Dir.children(File.join(root, "hello"))
    end
  end

  def test_interrupted_sessions_only_touch_runs_under_the_runs_directory
    with_runs_dir do |root|
      Dir.mktmpdir do |elsewhere|
        outside = Runsheets::RunRecord.start(elsewhere, example_runbook, session_id: "X")
        dir = File.join(root, "sessions", "old")
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, "session.json"), JSON.generate("id" => "old", "status" => "running", "pid" => 999_999_999,
                                                                 "runs" => [{ "dir" => outside.dir }]))
        assert_equal ["old"], Runsheets::Session.close_interrupted(root)
        assert_equal "running", Runsheets::RunRecord.load(outside.dir).status
      end
    end
  end

  def test_malformed_session_records_do_not_stop_a_start
    with_runs_dir do |root|
      %w[a b c].each { FileUtils.mkdir_p(File.join(root, "sessions", it)) }
      File.write(File.join(root, "sessions", "a", "session.json"), "[]")
      File.write(File.join(root, "sessions", "b", "session.json"), JSON.generate("status" => "running", "pid" => 1, "host" => "x", "runs" => "nope"))
      File.write(File.join(root, "sessions", "c", "session.json"), "{not json")
      assert start_session(root)
    end
  end
end

# The web layer's share of the review.
class TestWebHardening < Minitest::Test
  include RunsheetsTest::WebFixtures

  BROWSER = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"

  def setup = serve_web

  def teardown = stop_web

  def test_served_files_cannot_run_script
    serve_files("runbook.md" => "---\ntitle: T\n---\n", "steps/010-a.md" => "a\n", "pwn.html" => "<script>alert(1)</script>", "pic.svg" => "<svg/>")
    html = get "/files/pwn.html"
    svg  = get "/files/pic.svg"
    assert_includes html.headers["Content-Security-Policy"], "sandbox"
    assert_equal "nosniff", html.headers["X-Content-Type-Options"]
    assert_match(/\Aattachment/, html.headers["Content-Disposition"])
    assert_match(/\Ainline/, svg.headers["Content-Disposition"])
    assert_includes svg.headers["Content-Security-Policy"], "default-src 'none'"
  end

  def test_secret_fields_never_carry_a_value
    with_env("SECRET_WORD" => "from-the-environment") do
      get "/"
      refute_includes last_response.body, "from-the-environment"
      refute_includes last_response.body, "hunter2", "nor the default"
      assert_includes last_response.body, "leave blank to use $SECRET_WORD from the environment"
    end
  end

  def test_a_browser_gets_an_error_page_with_the_specific_message
    header "Accept", BROWSER
    page = get "/steps/nope"
    header "Accept", "application/json"
    api = get "/steps/nope"
    assert_equal 404, page.status
    assert_equal "text/html", page.media_type
    assert_includes page.body, "<h1>Not found</h1>"
    assert_includes page.body, "no step named nope"
    assert_equal({ "error" => "no step named nope" }, json(api))
  end

  def test_a_page_acts_on_its_own_runbook_after_another_tab_switched
    start_run
    @session.open(Runsheets::Runbook.load(File.expand_path("../examples/disk-space-triage.md", __dir__)))
    own   = execute("010-say-hello-1", "runbook" => "hello")
    owner = @session.runs.find { it.execution(json(own)["id"]) }
    other = execute("010-say-hello-1", "runbook" => "nope")
    assert_equal 202, own.status, "the hello page still runs hello's block"
    assert_equal "hello", owner.slug
    assert_equal 409, other.status
  end

  def test_embedded_json_cannot_break_out_of_its_script
    start_run
    @session.open(runbook_from("runbook.md" => "---\ntitle: T\n---\n", "steps/010-a.md" => "```bash run\necho '<!--<script>'\n```\n"))
    @session.execute("010-a-1").wait
    prior = get("/steps/010-a").body[%r{<script type="application/json" id="rs-prior">(.*?)</script>}m, 1]
    refute_nil prior
    refute_includes prior, "<"
  end

  def test_end_session_asks_first
    get "/session"
    assert_match(%r{<form method="post" action="/session/end" data-confirm="End the session and stop runsheets\?}, last_response.body)
  end
end
