# frozen_string_literal: true

module RunsheetsTest
  # Builders for the block and renderer tests.
  module RenderFixtures
    # A block with +info+ as its fence info string.
    def block(info, code = "echo\n") = Runsheets::Block.new(id: "s-1", index: 0, info:, code:)
  end
end
