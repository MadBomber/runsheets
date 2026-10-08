# frozen_string_literal: true

require "test_helper"

class TestRenderer < Minitest::Test
  Renderer = Runsheets::Renderer

  def test_executable_block_is_wrapped_with_data_attributes_and_a_run_button
    result = Renderer.render("```bash run\necho hi\n```\n", id_prefix: "010")
    html   = result.html
    assert_equal 1, result.blocks.size
    assert_equal "010-1", result.blocks.first.id
    assert_includes html, 'data-block="010-1"'
    assert_includes html, 'data-kind="run"'
    assert_includes html, 'data-action="execute"'
    assert_includes html, "language-bash"
    assert_includes html, "highlight"
    refute_includes html, "?rs="
  end

  def test_display_block_has_copy_but_no_run_button
    html = Renderer.render("```bash\necho hi\n```\n", id_prefix: "x").html
    assert_includes html, 'data-action="copy"'
    refute_includes html, 'data-action="execute"'
  end

  def test_bare_fence_renders_as_plain_code
    result = Renderer.render("```\nplain\n```\n", id_prefix: "x")
    assert_empty result.blocks
    assert_includes result.html, "<pre><code>plain"
  end

  def test_blocks_are_numbered_in_document_order_including_nested
    md = "```bash run\none\n```\n\n- item\n\n  ```ruby run\n  two\n  ```\n\n```text expect\nthree\n```\n"
    result = Renderer.render(md, id_prefix: "s")
    assert_equal %w[s-1 s-2 s-3], result.blocks.map(&:id)
    assert_equal %w[bash ruby text], result.blocks.map(&:lang)
    assert_equal "two\n", result.blocks[1].code
    assert_equal 3, result.html.scan("rs-block").size
  end

  def test_warnings_show_in_the_toolbar
    html = Renderer.render("```bash run bogus\nx\n```\n", id_prefix: "s").html
    assert_includes html, "rs-warning"
    assert_includes html, "unknown flag: bogus"
  end

  def test_destructive_button_label
    html = Renderer.render("```bash destructive\nx\n```\n", id_prefix: "s").html
    assert_includes html, "Run (destructive)"
    assert_includes html, "rs-danger"
  end

  def test_html_in_code_is_escaped
    html = Renderer.render("```bash run\necho '<b>'\n```\n", id_prefix: "s").html
    refute_includes html, "<b>"
    assert_includes html, "&lt;b&gt;"
  end

  def test_relative_urls_are_rewritten_to_files_route
    html = '<img src="../assets/a.svg"><img src="https://x/y.png"><a href="#top">t</a><a href="notes.md">n</a>'
    out  = Renderer.rewrite_relative_urls(html, "steps")
    assert_includes out, 'src="/files/assets/a.svg"'
    assert_includes out, 'src="https://x/y.png"'
    assert_includes out, 'href="#top"'
    assert_includes out, 'href="/files/steps/notes.md"'
  end

  def test_relative_url_escaping_root_is_left_alone
    out = Renderer.rewrite_relative_urls('<img src="../../etc/passwd">', "steps")
    assert_includes out, 'src="../../etc/passwd"'
  end

  def test_title_of
    assert_equal "Hello", Renderer.title_of("intro\n# Hello #\nmore")
    assert_nil Renderer.title_of("no heading")
  end
end
