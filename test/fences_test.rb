# frozen_string_literal: true

require "test_helper"

class TestFences < Minitest::Test
  Fences = Runsheets::Fences

  def test_rewrites_info_strings_with_a_marker
    md = "```bash run\necho hi\n```\n"
    rewritten, fences = Fences.extract(md)
    assert_equal "```bash?rs=0\necho hi\n```\n", rewritten
    assert_equal 1, fences.size
    assert_equal "bash run", fences.first.info
    assert_equal "echo hi\n", fences.first.code
    assert_equal 1, fences.first.line
  end

  def test_bare_fences_are_tracked_but_not_returned
    md = "```\n```bash run\n```\n\n```ruby run\nputs 1\n```\n"
    rewritten, fences = Fences.extract(md)
    assert_equal 1, fences.size
    assert_equal "ruby run", fences.first.info
    assert_includes rewritten, "```ruby?rs=0"
    refute_includes rewritten, "bash?rs"
  end

  def test_tilde_fences_and_longer_fences
    md = "~~~~bash run\n```\nstill code\n~~~\n~~~~\n"
    _, fences = Fences.extract(md)
    assert_equal 1, fences.size
    assert_equal "```\nstill code\n~~~\n", fences.first.code
  end

  def test_indented_fences_are_dedented
    md = "- item\n\n  ```bash run\n  echo one\n    echo nested\n  ```\n"
    rewritten, fences = Fences.extract(md)
    assert_equal "echo one\n  echo nested\n", fences.first.code
    assert_includes rewritten, "  ```bash?rs=0"
  end

  def test_unclosed_fence_is_still_returned
    _, fences = Fences.extract("```bash run\necho hi")
    assert_equal ["echo hi\n"], fences.map(&:code)
  end

  def test_output_always_ends_with_newline
    rewritten, = Fences.extract("text")
    assert_equal "text\n", rewritten
  end
end
