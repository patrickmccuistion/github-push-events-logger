# frozen_string_literal: true

require "faraday"

class GithubEnricher
  ACCEPT_HEADER = "application/vnd.github+json"

  def initialize(logger: Rails.logger)
    @logger = logger
    @conn = Faraday.new do |f|
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
    end
  end

  def enrich_event(event)
    repo = event["repo"] || {}
    actor = event["actor"] || {}

    fetch_and_store_actor(actor) if actor["id"].present? && !Actor.exists?(actor["id"])
    fetch_and_store_repo(repo) if repo["id"].present? && !Repository.exists?(repo["id"])
  end

  def fetch_and_store_actor(actor)
    url = normalize_github_url(actor["url"])
    return if url.blank?

    fetch_with_rate_limit_retry(url) do |response|
      return unless response.success?

      data = response.body
      Actor.upsert(
        actor_attributes_from_api(data, actor["id"]),
        unique_by: :id
      )
      @logger.info "[enrich] Fetched actor #{actor["id"]}"
    end
  end

  def fetch_and_store_repo(repo)
    url = normalize_github_url(repo["url"])
    return if url.blank?

    fetch_with_rate_limit_retry(url) do |response|
      return unless response.success?

      data = response.body
      Repository.upsert(
        repo_attributes_from_api(data, repo["id"]),
        unique_by: :id
      )
      @logger.info "[enrich] Fetched repo #{repo["id"]}"
    end
  end

  def fetch_with_rate_limit_retry(url)
    response = @conn.get(url) { |req| req.headers["Accept"] = ACCEPT_HEADER }

    if response.success?
      yield response
    elsif [403, 429].include?(response.status)
      reset_at = response.headers["x-ratelimit-reset"]&.to_i
      msg = reset_at ? "resets at #{Time.at(reset_at)}" : "no reset time"
      @logger.warn "[enrich] Rate limited (403/429). Exiting. #{msg}"
      raise RateLimitError.new("Rate limited", reset_at: reset_at)
    else
      @logger.warn "[enrich] Failed to fetch #{url}: #{response.status}"
    end
  rescue Faraday::Error => e
    @logger.error "[enrich] Error fetching #{url}: #{e.message}"
  end

  def actor_attributes_from_api(data, id)
    {
      id: id,
      login: data["login"],
      avatar_url: data["avatar_url"],
      name: data["name"],
      company: data["company"],
      bio: data["bio"],
      followers: data["followers"],
      public_repos: data["public_repos"],
      account_created_at: parse_time(data["created_at"]),
      raw_json: data.to_json,
      fetched_at: Time.current,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  def repo_attributes_from_api(data, id)
    {
      id: id,
      name: data["name"],
      full_name: data["full_name"],
      description: data["description"],
      language: data["language"],
      stargazers_count: data["stargazers_count"],
      forks_count: data["forks_count"],
      repo_created_at: parse_time(data["created_at"]),
      pushed_at: parse_time(data["pushed_at"]),
      raw_json: data.to_json,
      fetched_at: Time.current,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  def parse_time(str)
    return nil if str.blank?
    Time.zone.parse(str.to_s)
  rescue ArgumentError
    nil
  end

  private

  def normalize_github_url(url)
    return nil if url.blank?
    encoded = url.gsub("[", "%5B").gsub("]", "%5D")
    URI.parse(encoded).to_s
  rescue URI::InvalidURIError, ArgumentError
    nil
  end
end
