class CreatePushEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :push_events do |t|
      t.string :event_id, null: false, index: { unique: true }
      t.bigint :repo_id, null: false
      t.bigint :actor_id
      t.string :ref
      t.string :head
      t.string :before
      t.timestamps
    end

    add_index :push_events, :repo_id
    add_index :push_events, :actor_id
  end
end
