# frozen_string_literal: true

class EnrichmentBackfiller
  def initialize(logger: Rails.logger, rate_limiter: nil)
    @logger = logger
    limiter = rate_limiter || build_rate_limiter
    @enricher = GithubEnricher.new(logger: logger, rate_limiter: limiter)
  end

  def run
    backfill_actors
    backfill_repos
  rescue RateLimitError => e
    @logger.warn "[backfill] Rate limited. Exiting. Run again when limit resets."
    raise
  end

  private

  def build_rate_limiter
    return nil unless ENV["RATE_LIMIT_DELAY"].present? || ENV["MAX_REQUESTS_PER_RUN"].present?
    GithubRateLimiter.new(logger: @logger)
  end

  def backfill_actors
    missing = missing_actor_urls
    @logger.info "[backfill] Found #{missing.size} actors to enrich"

    missing.each do |actor_id, url|
      next if Actor.exists?(actor_id)
      next if url.blank?

      @enricher.fetch_with_rate_limit_retry(url) do |response|
        next unless response.success?

        data = response.body
        Actor.upsert(
          @enricher.actor_attributes_from_api(data, actor_id),
          unique_by: :id
        )
        @enricher.attach_avatar_if_needed(actor_id, data["avatar_url"])
        @logger.info "[backfill] Fetched actor #{actor_id}"
      end
    end
  end

  def backfill_repos
    missing = missing_repo_urls
    @logger.info "[backfill] Found #{missing.size} repos to enrich"

    missing.each do |repo_id, url|
      next if Repository.exists?(repo_id)
      next if url.blank?

      @enricher.fetch_with_rate_limit_retry(url) do |response|
        next unless response.success?

        data = response.body
        Repository.upsert(
          @enricher.repo_attributes_from_api(data, repo_id),
          unique_by: :id
        )
        @logger.info "[backfill] Fetched repo #{repo_id}"
      end
    end
  end

  def missing_actor_urls
    existing = Actor.pluck(:id).to_set
    result = {}

    RawEvent.find_each do |raw|
      actor = raw.payload["actor"]
      next if actor.blank?
      next unless actor["url"].present?

      id = actor["id"]
      next if existing.include?(id)
      next if result.key?(id)

      result[id] = normalize_url(actor["url"])
    end

    result
  end

  def missing_repo_urls
    existing = Repository.pluck(:id).to_set
    result = {}

    RawEvent.find_each do |raw|
      repo = raw.payload["repo"]
      next if repo.blank?
      next unless repo["url"].present?

      id = repo["id"]
      next if existing.include?(id)
      next if result.key?(id)

      result[id] = normalize_url(repo["url"])
    end

    result
  end

  def normalize_url(url)
    return nil if url.blank?
    encoded = url.to_s.gsub("[", "%5B").gsub("]", "%5D")
    URI.parse(encoded).to_s
  rescue URI::InvalidURIError, ArgumentError
    nil
  end
end
