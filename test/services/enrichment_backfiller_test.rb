# frozen_string_literal: true

require "test_helper"

class EnrichmentBackfillerTest < ActiveSupport::TestCase
  def actor_fixture
    JSON.parse(File.read(Rails.root.join("test/fixtures/github_actor.json")))
  end

  def repo_fixture
    JSON.parse(File.read(Rails.root.join("test/fixtures/github_repo.json")))
  end

  test "finds missing actors from raw_events and enriches them" do
    RawEvent.create!(
      id: "ev1",
      payload: {
        "actor" => { "id" => 1, "url" => "https://api.github.com/users/octocat" },
        "repo" => { "id" => 100, "url" => "https://api.github.com/repos/octocat/Hello-World" }
      }
    )

    stub_request(:get, %r{avatars\.githubusercontent\.com}).to_return(body: "fake-image", status: 200)
    stub_request(:get, "https://api.github.com/users/octocat")
      .to_return(body: actor_fixture.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://api.github.com/repos/octocat/Hello-World")
      .to_return(body: repo_fixture.to_json, headers: { "Content-Type" => "application/json" })

    backfiller = EnrichmentBackfiller.new(logger: Logger.new(IO::NULL))
    backfiller.run

    assert Actor.exists?(1)
    assert Repository.exists?(100)
    assert_equal "octocat", Actor.find(1).login
  end

  test "skips actors that already exist" do
    Actor.create!(id: 1, login: "octocat")
    RawEvent.create!(
      id: "ev1",
      payload: {
        "actor" => { "id" => 1, "url" => "https://api.github.com/users/octocat" },
        "repo" => { "id" => 100, "url" => "https://api.github.com/repos/octocat/Hello-World" }
      }
    )

    stub_request(:get, "https://api.github.com/users/octocat").to_raise(StandardError)
    stub_request(:get, "https://api.github.com/repos/octocat/Hello-World")
      .to_return(body: repo_fixture.to_json, headers: { "Content-Type" => "application/json" })

    backfiller = EnrichmentBackfiller.new(logger: Logger.new(IO::NULL))
    backfiller.run

    assert_not_requested :get, "https://api.github.com/users/octocat"
    assert Repository.exists?(100)
  end
end
