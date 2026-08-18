class CreateGames < ActiveRecord::Migration[8.1]
  def change
    create_table :games do |t|
      t.string :slug, null: false, limit: 50
      t.string :name, null: false, limit: 100
      t.text :description, null: false
      # questions_per_session: số câu hỏi bốc từ ngân hàng cho một lượt.
      # steps_per_session: số bước trả lời trong lượt — quyết định điều kiện kết thúc (BR-30).
      # Hai giá trị khác nhau ở game dạng kịch bản (Escape Room, PROD Roulette).
      t.integer :questions_per_session, null: false, unsigned: true
      t.integer :steps_per_session, null: false, unsigned: true
      t.integer :max_score, null: false, default: 100, unsigned: true
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :games, :slug, unique: true
  end
end
