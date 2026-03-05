class AddRepositoryEnrichmentColumns < ActiveRecord::Migration[7.1]
  def change
    add_column :repositories, :description, :text
    add_column :repositories, :language, :string
    add_column :repositories, :stargazers_count, :integer
    add_column :repositories, :forks_count, :integer
    add_column :repositories, :repo_created_at, :datetime
    add_column :repositories, :pushed_at, :datetime

    add_index :repositories, :language
    add_index :repositories, :stargazers_count
  end
end
