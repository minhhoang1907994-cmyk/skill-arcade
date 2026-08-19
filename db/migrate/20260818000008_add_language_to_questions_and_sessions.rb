class AddLanguageToQuestionsAndSessions < ActiveRecord::Migration[8.1]
  def change
    # Ngôn ngữ lập trình của snippet. Chỉ Bug Hunt dùng; các game khác để NULL.
    # Tách khỏi cột content (JSON) để lọc được bằng index khi bốc đề.
    add_column :questions, :language, :string, limit: 20
    add_index :questions, [ :game_id, :language, :hidden ],
              name: "index_questions_on_game_language_hidden"

    # Câu đã có sinh trước cột này: nhân ngôn ngữ từ content ra cột riêng, nếu
    # không thì chúng mang language NULL và không bao giờ được bốc nữa.
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE questions
          SET language = LEFT(JSON_UNQUOTE(JSON_EXTRACT(content, '$.language')), 20)
          WHERE JSON_TYPE(JSON_EXTRACT(content, '$.language')) = 'STRING'
        SQL
      end
    end

    # Ngôn ngữ người chơi đã chọn cho lượt này. Cần lưu vì đề được bốc theo từng
    # bước, nên mọi bước sau phải biết lượt đang giới hạn ở ngôn ngữ nào.
    add_column :game_sessions, :language, :string, limit: 20
  end
end
