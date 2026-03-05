# frozen_string_literal: true

require "test_helper"

class GithubEnricherTest < ActiveSupport::TestCase
  def actor_fixture
    JSON.parse(File.read(Rails.root.join("test/fixtures/github_actor.json")))
  end

  def repo_fixture
    JSON.parse(File.read(Rails.root.join("test/fixtures/github_repo.json")))
  end

  def actor_bot_fixture
    JSON.parse(File.read(Rails.root.join("test/fixtures/github_actor_bot.json")))
  end

  test "skips actor fetch when Actor exists" do
    Actor.create!(id: 1, login: "octocat", avatar_url: "x")
    event = {
      "actor" => { "id" => 1, "url" => "https://api.github.com/users/octocat" },
      "repo" => { "id" => 100, "url" => "https://api.github.com/repos/octocat/Hello-World" }
    }

    stub_request(:get, "https://api.github.com/users/octocat").to_raise(StandardError)
    stub_request(:get, %r{avatars\.githubusercontent\.com}).to_return(body: "fake-image", status: 200)
    stub_request(:get, "https://api.github.com/repos/octocat/Hello-World")
      .to_return(body: repo_fixture.to_json, headers: { "Content-Type" => "application/json" })

    enricher = GithubEnricher.new(logger: Logger.new(IO::NULL))
    enricher.enrich_event(event)

    assert Actor.exists?(1)
    assert Repository.exists?(100)
    assert_requested :get, "https://api.github.com/repos/octocat/Hello-World"
    assert_not_requested :get, "https://api.github.com/users/octocat"
  end

  test "normalize_github_url handles bot usernames via enrich_event" do
    event = {
      "actor" => { "id" => 2, "url" => "https://api.github.com/users/github-actions[bot]" },
      "repo" => { "id" => 100, "url" => "https://api.github.com/repos/octocat/Hello-World" }
    }

    stub_request(:get, %r{avatars\.githubusercontent\.com}).to_return(body: "fake-image", status: 200)
    stub_request(:get, "https://api.github.com/users/github-actions%5Bbot%5D")
      .to_return(body: actor_bot_fixture.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://api.github.com/repos/octocat/Hello-World")
      .to_return(body: repo_fixture.to_json, headers: { "Content-Type" => "application/json" })

    enricher = GithubEnricher.new(logger: Logger.new(IO::NULL))
    enricher.enrich_event(event)

    assert Actor.exists?(2)
    assert_equal "github-actions[bot]", Actor.find(2).login
  end

  test "raises RateLimitError on 429" do
    event = {
      "actor" => { "id" => 1, "url" => "https://api.github.com/users/octocat" },
      "repo" => { "id" => 100, "url" => "https://api.github.com/repos/octocat/Hello-World" }
    }

    stub_request(:get, "https://api.github.com/users/octocat")
      .to_return(status: 429, headers: { "x-ratelimit-reset" => (Time.now.to_i + 3600).to_s })

    enricher = GithubEnricher.new(logger: Logger.new(IO::NULL))

    assert_raises(RateLimitError) do
      enricher.enrich_event(event)
    end
  end

  test "parse_time returns nil for invalid string" do
    enricher = GithubEnricher.new(logger: Logger.new(IO::NULL))
    assert_nil enricher.parse_time("not-a-date")
    assert_nil enricher.parse_time("")
    assert_nil enricher.parse_time(nil)
  end

  test "attaches avatar to actor when enriching" do
    event = {
      "actor" => { "id" => 1, "url" => "https://api.github.com/users/octocat" },
      "repo" => { "id" => 100, "url" => "https://api.github.com/repos/octocat/Hello-World" }
    }

    stub_request(:get, "https://api.github.com/users/octocat")
      .to_return(body: actor_fixture.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://api.github.com/repos/octocat/Hello-World")
      .to_return(body: repo_fixture.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://avatars.githubusercontent.com/u/1?v=4")
      .to_return(body: "fake-png-bytes", status: 200, headers: { "Content-Type" => "image/png" })

    enricher = GithubEnricher.new(logger: Logger.new(IO::NULL))
    enricher.enrich_event(event)

    actor = Actor.find(1)
    assert actor.avatar.attached?
  end

  test "parse_time parses valid ISO8601" do
    enricher = GithubEnricher.new(logger: Logger.new(IO::NULL))
    result = enricher.parse_time("2011-01-25T18:44:36Z")
    assert result.is_a?(Time)
    assert_equal 2011, result.year
  end

  test "rate_limiter raises when max_requests exceeded" do
    rate_limiter = GithubRateLimiter.new(logger: Logger.new(IO::NULL), max_requests: 1)
    enricher = GithubEnricher.new(logger: Logger.new(IO::NULL), rate_limiter: rate_limiter)
    event = {
      "actor" => { "id" => 1, "url" => "https://api.github.com/users/octocat" },
      "repo" => { "id" => 100, "url" => "https://api.github.com/repos/octocat/Hello-World" }
    }

    stub_request(:get, "https://api.github.com/users/octocat")
      .to_return(body: actor_fixture.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, %r{avatars\.githubusercontent\.com}).to_return(body: "fake-image", status: 200)
    stub_request(:get, "https://api.github.com/repos/octocat/Hello-World")
      .to_return(body: repo_fixture.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(RateLimitError) do
      enricher.enrich_event(event)
    end
  end
end
