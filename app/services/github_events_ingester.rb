# frozen_string_literal: true

require "faraday"
require "ostruct"

class GithubEventsIngester
  EVENTS_URL = "https://api.github.com/events"
  ACCEPT_HEADER = "application/vnd.github+json"

  def initialize(logger: Rails.logger, enrich: true, rate_limiter: nil)
    @logger = logger
    limiter = rate_limiter || (build_rate_limiter if enrich)
    @enricher = enrich ? GithubEnricher.new(logger: logger, rate_limiter: limiter) : nil
    @etag = nil
    @poll_interval = 60
  end

  def run(continuous: false)
    loop do
      result = poll_once
      break if !continuous && result
      break if result == :rate_limited

      sleep(@poll_interval) if continuous
    end
  end

  def poll_once
    response = fetch_events

    case response.status
    when 200
      process_events(response)
      @etag = response.headers["etag"]
      @poll_interval = (response.headers["x-poll-interval"] || 60).to_i
      true
    when 403, 429
      handle_rate_limit(response)
      :rate_limited
    when 304
      @logger.info "[ingest] No new events (304 Not Modified)"
      true
    else
      @logger.error "[ingest] Unexpected response: #{response.status}"
      false
    end
  rescue Faraday::Error => e
    @logger.error "[ingest] Network error: #{e.message}"
    false
  rescue RateLimitError => e
    @logger.warn "[ingest] Rate limited during enrichment. Exiting. Run backfill to complete."
    :rate_limited
  end

  private

  def fetch_events
    fixture_path = ENV["INGEST_FIXTURE_PATH"]
    if fixture_path.present?
      path = Pathname.new(fixture_path).absolute? ? fixture_path : Rails.root.join(fixture_path)
      body = JSON.parse(File.read(path))
      return OpenStruct.new(
        status: 200,
        body: body,
        headers: { "etag" => '"fixture"', "x-poll-interval" => "60" }
      )
    end

    conn = Faraday.new(url: EVENTS_URL) do |f|
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
    end

    headers = { "Accept" => ACCEPT_HEADER }
    headers["If-None-Match"] = @etag if @etag

    conn.get do |req|
      req.headers = headers
    end
  end

  def process_events(response)
    events = response.body
    push_events = Array(events).select { |e| e.is_a?(Hash) && e["type"] == "PushEvent" }

    @logger.info "[ingest] Fetched #{events.size} events, #{push_events.size} PushEvents"

    # Prioritize: persist all events first (events over enrichment)
    push_events.each do |event|
      persist_event(event)
    rescue StandardError => e
      @logger.error "[ingest] Failed to persist event #{event["id"]}: #{e.message}"
    end

    # Then enrich; exit on rate limit (backfill can complete later)
    push_events.each do |event|
      @enricher&.enrich_event(event)
    rescue RateLimitError
      raise
    rescue StandardError => e
      @logger.warn "[ingest] Enrichment skipped for event #{event["id"]}: #{e.message}"
    end
  end

  def persist_event(event)
    event_id = event["id"]&.to_s
    return if event_id.blank?

    payload = event["payload"] || {}
    repo = event["repo"] || {}
    actor = event["actor"] || {}

    RawEvent.upsert(
      { id: event_id, payload: event.to_json, created_at: Time.current, updated_at: Time.current },
      unique_by: :id
    )

    head_sha = payload["head"] || payload["after"]

    PushEvent.upsert(
      {
        event_id: event_id,
        repo_id: repo["id"],
        actor_id: actor["id"],
        ref: payload["ref"],
        head: head_sha,
        before: payload["before"],
        created_at: Time.current,
        updated_at: Time.current
      },
      unique_by: :event_id
    )

    @logger.info "[ingest] Persisted PushEvent #{event_id}"
  end

  def build_rate_limiter
    return nil unless ENV["RATE_LIMIT_DELAY"].present? || ENV["MAX_REQUESTS_PER_RUN"].present?
    GithubRateLimiter.new(logger: @logger)
  end

  def handle_rate_limit(response)
    reset_at = response.headers["x-ratelimit-reset"]&.to_i
    msg = reset_at ? "resets at #{Time.at(reset_at)}" : "no reset time"
    @logger.warn "[ingest] Rate limited (403/429). Exiting. #{msg}"
  end
end
