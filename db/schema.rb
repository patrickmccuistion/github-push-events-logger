# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2025_03_04_000006) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "actors", force: :cascade do |t|
    t.string "login"
    t.string "avatar_url"
    t.jsonb "raw_json"
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.string "company"
    t.text "bio"
    t.integer "followers"
    t.integer "public_repos"
    t.datetime "account_created_at"
    t.index ["company"], name: "index_actors_on_company"
    t.index ["followers"], name: "index_actors_on_followers"
  end

  create_table "push_events", force: :cascade do |t|
    t.string "event_id", null: false
    t.bigint "repo_id", null: false
    t.bigint "actor_id"
    t.string "ref"
    t.string "head"
    t.string "before"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_push_events_on_actor_id"
    t.index ["event_id"], name: "index_push_events_on_event_id", unique: true
    t.index ["repo_id"], name: "index_push_events_on_repo_id"
  end

  create_table "raw_events", id: :string, force: :cascade do |t|
    t.jsonb "payload", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "repositories", force: :cascade do |t|
    t.string "name"
    t.string "full_name"
    t.jsonb "raw_json"
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "description"
    t.string "language"
    t.integer "stargazers_count"
    t.integer "forks_count"
    t.datetime "repo_created_at"
    t.datetime "pushed_at"
    t.index ["language"], name: "index_repositories_on_language"
    t.index ["stargazers_count"], name: "index_repositories_on_stargazers_count"
  end

end
