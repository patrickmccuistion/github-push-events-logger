# frozen_string_literal: true

class GithubRateLimiter
  def initialize(logger: Rails.logger, delay_seconds: nil, max_requests: nil)
    @logger = logger
    @delay_seconds = (delay_seconds || ENV["RATE_LIMIT_DELAY"]&.to_i) || 0
    @max_requests = (max_requests || ENV["MAX_REQUESTS_PER_RUN"]&.to_i)
    @request_count = 0
  end

  def before_request
    @request_count += 1

    if @max_requests && @request_count > @max_requests
      raise RateLimitError.new("Max requests per run (#{@max_requests}) exceeded", reset_at: nil)
    end

    remaining = @max_requests ? (@max_requests - @request_count) : nil
    msg = "[rate] Request #{@request_count}"
    msg += "/#{@max_requests} (remaining: #{remaining})" if @max_requests
    @logger.info msg

    sleep(@delay_seconds) if @delay_seconds.positive?
  end

  def record_request
    # Optional: track for metrics; currently before_request handles everything
  end
end
