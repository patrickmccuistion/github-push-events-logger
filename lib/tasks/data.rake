# frozen_string_literal: true

namespace :data do
  desc "Prune raw_events older than N days (DAYS=90). Backfill cannot re-enrich from pruned events."
  task prune_old_raw_events: :environment do
    days = (ENV["DAYS"] || 90).to_i
    cutoff = days.days.ago
    count = RawEvent.where("created_at < ?", cutoff).delete_all
    Rails.logger.info "[data] Pruned #{count} raw_events older than #{days} days"
  end
end
