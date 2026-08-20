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

ActiveRecord::Schema[8.1].define(version: 2026_08_20_000001) do
  create_table "ai_gradings", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.integer "latency_ms", unsigned: true
    t.string "model", limit: 50, null: false
    t.text "prompt", null: false
    t.text "response", null: false
    t.integer "score", unsigned: true
    t.bigint "session_answer_id", null: false
    t.index ["session_answer_id"], name: "index_ai_gradings_on_session_answer_id"
  end

  create_table "game_sessions", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "abandoned_reason", limit: 20
    t.integer "attempt_number", null: false, unsigned: true
    t.datetime "created_at", null: false
    t.integer "current_position", default: 0, null: false, unsigned: true
    t.datetime "finished_at"
    t.bigint "game_id", null: false
    t.string "language", limit: 20
    t.integer "score", default: 0, null: false, unsigned: true
    t.datetime "started_at", null: false
    t.string "state", limit: 20, default: "in_progress", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["game_id", "finished_at", "score"], name: "index_game_sessions_on_game_finished_score"
    t.index ["game_id"], name: "index_game_sessions_on_game_id"
    t.index ["user_id", "game_id", "attempt_number"], name: "index_game_sessions_on_user_game_attempt", unique: true
    t.index ["user_id", "started_at"], name: "index_game_sessions_on_user_started"
    t.index ["user_id"], name: "index_game_sessions_on_user_id"
    t.check_constraint "(`score` >= 0) and (`score` <= 100)", name: "chk_game_sessions_score_range"
  end

  create_table "games", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.integer "max_score", default: 100, null: false, unsigned: true
    t.string "name", limit: 100, null: false
    t.integer "questions_per_session", null: false, unsigned: true
    t.string "slug", limit: 50, null: false
    t.integer "steps_per_session", null: false, unsigned: true
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_games_on_slug", unique: true
  end

  create_table "question_reports", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "handled_at"
    t.bigint "handled_by_id"
    t.bigint "question_id", null: false
    t.text "reason", null: false
    t.string "status", limit: 20, default: "open", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["handled_by_id"], name: "index_question_reports_on_handled_by_id"
    t.index ["question_id"], name: "index_question_reports_on_question_id"
    t.index ["status"], name: "index_question_reports_on_status"
    t.index ["user_id", "question_id"], name: "index_question_reports_on_user_and_question", unique: true
    t.index ["user_id"], name: "index_question_reports_on_user_id"
  end

  create_table "questions", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.json "answer_key", null: false
    t.string "checksum", limit: 64, null: false
    t.json "content", null: false
    t.datetime "created_at", null: false
    t.string "difficulty", limit: 10
    t.bigint "game_id", null: false
    t.datetime "generated_at"
    t.boolean "hidden", default: false, null: false
    t.string "language", limit: 20
    t.string "source", limit: 20, default: "ai_generated", null: false
    t.datetime "updated_at", null: false
    t.index ["checksum"], name: "index_questions_on_checksum", unique: true
    t.index ["game_id", "hidden"], name: "index_questions_on_game_id_and_hidden"
    t.index ["game_id", "language", "hidden"], name: "index_questions_on_game_language_hidden"
    t.index ["game_id"], name: "index_questions_on_game_id"
  end

  create_table "session_answers", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.json "answer", null: false
    t.datetime "answered_at", null: false
    t.datetime "created_at", null: false
    t.integer "elapsed_ms", unsigned: true
    t.bigint "game_session_id", null: false
    t.integer "position", null: false, unsigned: true
    t.bigint "question_id", null: false
    t.integer "score", default: 0, null: false, unsigned: true
    t.datetime "updated_at", null: false
    t.index ["game_session_id", "position"], name: "index_session_answers_on_session_position", unique: true
    t.index ["game_session_id"], name: "index_session_answers_on_game_session_id"
    t.index ["question_id"], name: "index_session_answers_on_question_id"
  end

  create_table "users", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.string "avatar", limit: 20, default: "hero", null: false
    t.datetime "created_at", null: false
    t.string "display_name", limit: 50, null: false
    t.string "email", null: false
    t.integer "failed_login_count", default: 0, null: false, unsigned: true
    t.datetime "locked_until"
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["display_name"], name: "index_users_on_display_name", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "ai_gradings", "session_answers", on_delete: :cascade
  add_foreign_key "game_sessions", "games"
  add_foreign_key "game_sessions", "users", on_delete: :cascade
  add_foreign_key "question_reports", "questions", on_delete: :cascade
  add_foreign_key "question_reports", "users", column: "handled_by_id", on_delete: :nullify
  add_foreign_key "question_reports", "users", on_delete: :cascade
  add_foreign_key "questions", "games"
  add_foreign_key "session_answers", "game_sessions", on_delete: :cascade
  add_foreign_key "session_answers", "questions"
end
