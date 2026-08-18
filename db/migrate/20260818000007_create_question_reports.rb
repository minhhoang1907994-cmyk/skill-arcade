class CreateQuestionReports < ActiveRecord::Migration[8.1]
  def change
    create_table :question_reports do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :question, null: false, foreign_key: { on_delete: :cascade }
      t.text :reason, null: false
      t.string :status, null: false, limit: 20, default: "open"
      t.references :handled_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :handled_at

      t.timestamps
    end

    # Mỗi người báo mỗi câu tối đa một lần (BR-17).
    add_index :question_reports, [ :user_id, :question_id ],
              unique: true, name: "index_question_reports_on_user_and_question"
    add_index :question_reports, :status
  end
end
