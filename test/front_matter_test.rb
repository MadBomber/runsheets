# frozen_string_literal: true

require "test_helper"

class TestFrontMatter < Minitest::Test
  FM = Runsheets::FrontMatter

  def test_unreadable_yaml_is_a_runbook_error
    assert_raises(Runsheets::RunbookError) { FM.parse("---\ntitle: !ruby/object:Object {}\n---\n") }
    assert_raises(Runsheets::RunbookError) { FM.parse("---\na: &x [1]\nb: *x\n---\n") }
    assert_equal "na�ve", FM.parse("---\ntitle: na\xEFve\n---\n".b.force_encoding("UTF-8")).data["title"], "invalid bytes are replaced, not fatal"
  end

  def test_splits_data_and_body
    result = FM.parse("---\ntitle: Hi\nupdated: 2026-09-12\n---\n# Body\n")
    assert_equal "Hi", result.data["title"]
    assert_equal Date.new(2026, 9, 12), result.data["updated"]
    assert_equal "# Body\n", result.body
    assert_equal "Hi", FM.parse("\uFEFF---\ntitle: Hi\n---\nbody\n").data["title"], "a byte order mark does not hide the front matter"
  end

  def test_no_front_matter
    result = FM.parse("# Just markdown\n")
    assert_equal({}, result.data)
    assert_equal "# Just markdown\n", result.body
    assert_equal({}, FM.parse("intro\n\n---\n\nmore").data, "a rule later in the document is not front matter")
  end

  def test_empty_front_matter
    result = FM.parse("---\n---\nbody")
    assert_equal({}, result.data)
    assert_equal "body", result.body
  end

  def test_malformed_front_matter_raises
    assert_raises(Runsheets::RunbookError, "not a mapping") { FM.parse("---\n- a\n- b\n---\n") }
    assert_raises(Runsheets::RunbookError, "invalid yaml") { FM.parse("---\ntitle: [unclosed\n---\n") }
  end
end
