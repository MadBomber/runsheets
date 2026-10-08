# frozen_string_literal: true

require "test_helper"

class TestFrontMatter < Minitest::Test
  FM = Runsheets::FrontMatter

  def test_splits_data_and_body
    result = FM.parse("---\ntitle: Hi\nlast_verified: 2026-09-12\n---\n# Body\n")
    assert_equal "Hi", result.data["title"]
    assert_equal Date.new(2026, 9, 12), result.data["last_verified"]
    assert_equal "# Body\n", result.body
  end

  def test_no_front_matter
    result = FM.parse("# Just markdown\n")
    assert_equal({}, result.data)
    assert_equal "# Just markdown\n", result.body
  end

  def test_empty_front_matter
    result = FM.parse("---\n---\nbody")
    assert_equal({}, result.data)
    assert_equal "body", result.body
  end

  def test_a_rule_later_in_the_document_is_not_front_matter
    result = FM.parse("intro\n\n---\n\nmore")
    assert_equal({}, result.data)
  end

  def test_non_mapping_raises
    assert_raises(Runsheets::RunbookError) { FM.parse("---\n- a\n- b\n---\n") }
  end

  def test_invalid_yaml_raises
    assert_raises(Runsheets::RunbookError) { FM.parse("---\ntitle: [unclosed\n---\n") }
  end
end
