class CreateRepositories < ActiveRecord::Migration[7.1]
  def change
    create_table :repositories, id: false do |t|
      t.bigint :id, primary_key: true, null: false
      t.string :name
      t.string :full_name
      t.jsonb :raw_json
      t.datetime :fetched_at
      t.timestamps
    end
  end
end
