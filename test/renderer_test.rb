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

  def test_each_kind_of_block_gets_its_own_toolbar
    [
      ["bash", ['data-action="copy"'], ['data-action="execute"']],
      ["bash run bogus", ["rs-warning", "unknown flag: bogus"], []],
      ["bash destructive", ["Run (destructive)", "rs-danger"], []],
      ["bash background", [">Start</button>", 'data-action="stop"'], ["not executable"]],
      ["bash terminal", ['data-action="acknowledge"'], ['data-action="execute"']]
    ].each do |info, present, absent|
      html = Renderer.render("```#{info}\nx\n```\n", id_prefix: "s").html
      present.each { assert_includes html, it, info }
      absent.each { refute_includes html, it, info }
    end
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

  def test_expect_blocks_link_to_the_nearest_executable_block_above
    md = "```text expect\norphan\n```\n```bash run\none\n```\nprose\n```text expect\n1\n```\n```bash\nshown\n```\n```text expect\nalso 1\n```\n```ruby run\ntwo\n```\n```text expect\n2\n```\n"
    result = Renderer.render(md, id_prefix: "s")
    assert_equal [nil, nil, "s-2", nil, "s-2", nil, "s-6"], result.blocks.map(&:expect_for)
    assert_includes result.html, 'data-expect-for="s-2"'
    assert_includes result.html, 'expected output of <a href="#block-s-2">s-2</a>'
    assert_includes result.html, 'data-role="expected"'
  end

  def test_html_in_code_is_escaped
    html = Renderer.render("```bash run\necho '<b>'\n```\n", id_prefix: "s").html
    refute_includes html, "<b>"
    assert_includes html, "&lt;b&gt;"
  end

  def test_relative_urls_are_rewritten_to_files_route
    html = '<img src="../assets/a.svg"><img src="https://x/y.png"><a href="#top">t</a><a href="notes.md">n</a><img src="../../etc/passwd">'
    out  = Renderer.rewrite_relative_urls(html, "steps")
    assert_includes out, 'src="/files/assets/a.svg"'
    assert_includes out, 'src="https://x/y.png"'
    assert_includes out, 'href="#top"'
    assert_includes out, 'href="/docs/steps/notes.md"'
    assert_includes out, 'src="../../etc/passwd"', "a url escaping the root is left alone"
  end

  def test_links_to_markdown_go_to_the_docs_route_and_other_files_to_files
    out = Renderer.rewrite_relative_urls('<a href="../guide.MD#setup">g</a><a href="data.csv">d</a><img src="x.md">', "steps")
    assert_includes out, 'href="/docs/guide.MD#setup"'
    assert_includes out, 'href="/files/steps/data.csv"'
    assert_includes out, 'src="/files/steps/x.md"'
  end

  def test_links_to_plain_documents_open_in_a_new_tab
    Dir.mktmpdir do |root|
      File.write(File.join(root, "notes.md"), "# Notes\n")
      File.write(File.join(root, "deploy.md"), "---\ntitle: Deploy\n---\n")
      html = '<a href="/docs/notes.md#part">n</a><a href="/docs/deploy.md">d</a><a href="/files/x.svg">x</a>'
      out  = Renderer.open_documents_in_new_tab(html, root)
      assert_includes out, '<a href="/docs/notes.md#part" target="_blank" rel="noopener">'
      assert_includes out, '<a href="/docs/deploy.md">', "a runbook stays in the tab"
      assert_includes out, '<a href="/files/x.svg">'
    end
  end

  def test_title_comes_from_prose_not_from_a_comment_in_code
    assert_nil Renderer.title_of("```bash run\n# install deps first\nmake\n```\n")
    assert_equal "Deploy", Renderer.title_of("```bash\n# not this\n```\n\n# Deploy\r\n")
    assert_equal "Upgrade to C#", Renderer.title_of("# Upgrade to C#\n")
    assert_equal "Closed", Renderer.title_of("# Closed ##\n")
    assert_equal "Yes", Renderer.title_of("```bash\n# no\n~~~\n# still code\n```\n\n# Yes\n"), "a fence is closed only by its own kind"
  end

  def test_meta_tags_are_removed_from_rendered_markdown
    html = Renderer.render_plain("hi\n\n<meta http-equiv=\"refresh\" content=\"0;url=/x\">\n")
    refute_includes html, "<meta"
    assert_includes html, "<p>hi</p>"
  end

  def test_title_of
    assert_equal "Hello", Renderer.title_of("intro\n# Hello #\nmore")
    assert_nil Renderer.title_of("no heading")
  end
end
