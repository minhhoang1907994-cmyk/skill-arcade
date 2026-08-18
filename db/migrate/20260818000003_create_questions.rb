class CreateQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :questions do |t|
      t.references :game, null: false, foreign_key: { on_delete: :restrict }
      # content: dữ liệu hiển thị cho người chơi.
      # answer_key: đáp án và rubric chấm — không bao giờ được trả về client (BR-03).
      t.json :content, null: false
      t.json :answer_key, null: false
      t.string :difficulty, limit: 10
      t.string :checksum, null: false, limit: 64
      t.boolean :hidden, null: false, default: false
      t.string :source, null: false, limit: 20, default: "ai_generated"
      t.datetime :generated_at

      t.timestamps
    end

    add_index :questions, :checksum, unique: true
    add_index :questions, [ :game_id, :hidden ]
  end
end
