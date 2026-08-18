class CreateAiGradings < ActiveRecord::Migration[8.1]
  def change
    # Bản ghi bất biến, không bao giờ xoá (BR-19). Đây là bằng chứng duy nhất
    # để giải trình khi người chơi khiếu nại điểm do AI chấm.
    create_table :ai_gradings do |t|
      t.references :session_answer, null: false, foreign_key: { on_delete: :cascade }
      t.string :model, null: false, limit: 50
      t.text :prompt, null: false
      t.text :response, null: false
      t.integer :score, unsigned: true
      t.integer :latency_ms, unsigned: true
      t.text :error

      # Không có updated_at — bản ghi không bao giờ được sửa.
      t.datetime :created_at, null: false
    end
  end
end
