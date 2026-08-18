class CreateGameSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :game_sessions do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :game, null: false, foreign_key: { on_delete: :restrict }
      t.integer :attempt_number, null: false, unsigned: true
      t.integer :score, null: false, default: 0, unsigned: true
      t.string :state, null: false, limit: 20, default: "in_progress"
      # Chỉ 'system_error' được miễn trừ khỏi bộ đếm rate limit (BR-33).
      t.string :abandoned_reason, limit: 20
      t.integer :current_position, null: false, default: 0, unsigned: true
      t.datetime :started_at, null: false
      # NULL nghĩa là lượt chưa hoàn thành — bị loại khỏi mọi tính toán điểm (BR-08).
      t.datetime :finished_at

      t.timestamps
    end

    # Chống tạo trùng số lượt khi hai request đến cùng lúc.
    add_index :game_sessions, [ :user_id, :game_id, :attempt_number ],
              unique: true, name: "index_game_sessions_on_user_game_attempt"
    # Truy vấn leaderboard theo chu kỳ.
    add_index :game_sessions, [ :game_id, :finished_at, :score ],
              name: "index_game_sessions_on_game_finished_score"
    # Đếm lượt cho rate limit.
    add_index :game_sessions, [ :user_id, :started_at ],
              name: "index_game_sessions_on_user_started"

    # MySQL chỉ thực thi CHECK từ 8.0.16 trở lên. Validation ở model là bắt buộc,
    # không phải tuỳ chọn (spec section 4.2).
    add_check_constraint :game_sessions, "score >= 0 AND score <= 100",
                         name: "chk_game_sessions_score_range"
  end
end
