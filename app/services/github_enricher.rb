# frozen_string_literal: true

require "faraday"
require "open-uri"

class GithubEnricher
  ACCEPT_HEADER = "application/vnd.github+json"

  def initialize(logger: Rails.logger, rate_limiter: nil)
    @logger = logger
    @rate_limiter = rate_limiter
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
      actor_id = actor["id"]
      Actor.upsert(
        actor_attributes_from_api(data, actor_id),
        unique_by: :id
      )
      attach_avatar_if_needed(actor_id, data["avatar_url"])
      @logger.info "[enrich] Fetched actor #{actor_id}"
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
    @rate_limiter&.before_request
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

  def attach_avatar_if_needed(actor_id, avatar_url)
    return if avatar_url.blank?

    actor_record = Actor.find_by(id: actor_id)
    return unless actor_record
    return if actor_record.avatar.attached?

    uri = URI.parse(avatar_url)
    ext = File.extname(uri.path).presence || ".png"
    actor_record.avatar.attach(
      io: URI.open(uri),
      filename: "avatar_#{actor_id}#{ext}"
    )
    @logger.info "[enrich] Attached avatar for actor #{actor_id}"
  rescue OpenURI::HTTPError, SocketError, Errno::ECONNREFUSED => e
    @logger.warn "[enrich] Failed to fetch avatar for actor #{actor_id}: #{e.message}"
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
