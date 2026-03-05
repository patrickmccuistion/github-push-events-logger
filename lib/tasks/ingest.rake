# frozen_string_literal: true

namespace :ingest do
  desc "Run GitHub push events ingestion (single poll)"
  task run: :environment do
    enrich = ENV["INGEST_FIXTURE_PATH"].blank?
    ingester = GithubEventsIngester.new(enrich: enrich)
    ingester.run(continuous: ENV["CONTINUOUS"] == "1")
  end
end

namespace :enrich do
  desc "Backfill missing actor and repository data (waits on rate limit)"
  task backfill: :environment do
    EnrichmentBackfiller.new.run
  end
end
