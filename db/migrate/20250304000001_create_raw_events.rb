class CreateRawEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :raw_events, id: false do |t|
      t.string :id, primary_key: true, null: false
      t.jsonb :payload, null: false
      t.timestamps
    end
  end
end
