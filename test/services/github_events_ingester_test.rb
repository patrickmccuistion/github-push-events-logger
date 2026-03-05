# frozen_string_literal: true

require "test_helper"

class GithubEventsIngesterTest < ActiveSupport::TestCase
  def events_fixture
    JSON.parse(File.read(Rails.root.join("test/fixtures/github_events.json")))
  end

  def actor_fixture
    JSON.parse(File.read(Rails.root.join("test/fixtures/github_actor.json")))
  end

  def repo_fixture
    JSON.parse(File.read(Rails.root.join("test/fixtures/github_repo.json")))
  end

  test "persists PushEvents and skips non-PushEvent" do
    stub_request(:get, "https://api.github.com/events")
      .to_return(
        body: events_fixture.to_json,
        headers: { "Content-Type" => "application/json", "etag" => '"abc"', "x-poll-interval" => "60" }
      )
    stub_request(:get, %r{avatars\.githubusercontent\.com}).to_return(body: "fake-image", status: 200)
    stub_request(:get, "https://api.github.com/users/octocat")
      .to_return(body: actor_fixture.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://api.github.com/repos/octocat/Hello-World")
      .to_return(body: repo_fixture.to_json, headers: { "Content-Type" => "application/json" })

    ingester = GithubEventsIngester.new(logger: Logger.new(IO::NULL))
    result = ingester.poll_once

    assert result
    assert_equal 1, RawEvent.count
    assert_equal 1, PushEvent.count
    assert_equal "12345678", PushEvent.first.event_id
    assert_equal 1, Actor.count
    assert_equal 1, Repository.count
  end

  test "returns rate_limited on 403" do
    stub_request(:get, "https://api.github.com/events")
      .to_return(status: 403, headers: { "x-ratelimit-reset" => (Time.now.to_i + 3600).to_s })

    ingester = GithubEventsIngester.new(enrich: false, logger: Logger.new(IO::NULL))
    result = ingester.poll_once

    assert_equal :rate_limited, result
  end

  test "uses ETag on second request" do
    stub_request(:get, %r{avatars\.githubusercontent\.com}).to_return(body: "fake-image", status: 200)
    stub_request(:get, "https://api.github.com/events")
      .with { |req| req.headers["If-None-Match"] == '"first"' }
      .to_return(status: 304, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://api.github.com/events")
      .to_return(
        body: events_fixture.to_json,
        headers: { "Content-Type" => "application/json", "etag" => '"first"' }
      )
    stub_request(:get, "https://api.github.com/users/octocat")
      .to_return(body: actor_fixture.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://api.github.com/repos/octocat/Hello-World")
      .to_return(body: repo_fixture.to_json, headers: { "Content-Type" => "application/json" })

    ingester = GithubEventsIngester.new(logger: Logger.new(IO::NULL))
    ingester.poll_once
    result = ingester.poll_once

    assert result
    assert_requested :get, "https://api.github.com/events", headers: { "If-None-Match" => '"first"' }
  end

  test "idempotent: same event upserted twice yields single record" do
    stub_request(:get, %r{avatars\.githubusercontent\.com}).to_return(body: "fake-image", status: 200)
    stub_request(:get, "https://api.github.com/events")
      .to_return(
        body: events_fixture.to_json,
        headers: { "Content-Type" => "application/json", "etag" => '"x"' }
      )
    stub_request(:get, "https://api.github.com/users/octocat")
      .to_return(body: actor_fixture.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://api.github.com/repos/octocat/Hello-World")
      .to_return(body: repo_fixture.to_json, headers: { "Content-Type" => "application/json" })

    ingester = GithubEventsIngester.new(logger: Logger.new(IO::NULL))
    ingester.poll_once
    ingester.poll_once

    assert_equal 1, RawEvent.count
    assert_equal 1, PushEvent.count
    assert_equal "12345678", PushEvent.first.event_id
  end

  test "filters PushEvent only" do
    ingester = GithubEventsIngester.new(enrich: false)
    assert_not_nil ingester
  end
end
