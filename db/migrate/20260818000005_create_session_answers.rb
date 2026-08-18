class CreateSessionAnswers < ActiveRecord::Migration[8.1]
  def change
    create_table :session_answers do |t|
      t.references :game_session, null: false, foreign_key: { on_delete: :cascade }
      # Với Escape Room và PROD Roulette, nhiều answer cùng trỏ về một question
      # (mỗi answer là một bước trong kịch bản).
      t.references :question, null: false, foreign_key: { on_delete: :restrict }
      t.integer :position, null: false, unsigned: true
      t.json :answer, null: false
      # unsigned được vì cả 5 game đều dùng mô hình cộng dồn, không bước nào cho điểm âm (BR-31).
      t.integer :score, null: false, default: 0, unsigned: true
      t.integer :elapsed_ms, unsigned: true
      t.datetime :answered_at, null: false

      t.timestamps
    end

    # Chống double-submit cùng một bước.
    add_index :session_answers, [ :game_session_id, :position ],
              unique: true, name: "index_session_answers_on_session_position"
  end
end
