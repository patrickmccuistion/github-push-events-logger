# frozen_string_literal: true

class RateLimitError < StandardError
  attr_reader :reset_at

  def initialize(message = "Rate limited (403/429)", reset_at: nil)
    super(message)
    @reset_at = reset_at
  end
end
