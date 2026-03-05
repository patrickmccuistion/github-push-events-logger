class CreateActors < ActiveRecord::Migration[7.1]
  def change
    create_table :actors, id: false do |t|
      t.bigint :id, primary_key: true, null: false
      t.string :login
      t.string :avatar_url
      t.jsonb :raw_json
      t.datetime :fetched_at
      t.timestamps
    end
  end
end
