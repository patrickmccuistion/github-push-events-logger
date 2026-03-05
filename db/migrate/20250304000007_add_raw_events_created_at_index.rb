# frozen_string_literal: true

class AddRawEventsCreatedAtIndex < ActiveRecord::Migration[7.1]
  def change
    add_index :raw_events, :created_at, if_not_exists: true
  end
end
