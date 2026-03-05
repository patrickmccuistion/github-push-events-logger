class AddActorEnrichmentColumns < ActiveRecord::Migration[7.1]
  def change
    add_column :actors, :name, :string
    add_column :actors, :company, :string
    add_column :actors, :bio, :text
    add_column :actors, :followers, :integer
    add_column :actors, :public_repos, :integer
    add_column :actors, :account_created_at, :datetime

    add_index :actors, :followers
    add_index :actors, :company
  end
end
