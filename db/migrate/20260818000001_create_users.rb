class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false, limit: 255
      t.string :password_digest, null: false, limit: 255
      t.string :display_name, null: false, limit: 50
      t.boolean :admin, null: false, default: false
      t.integer :failed_login_count, null: false, default: 0, unsigned: true
      t.datetime :locked_until

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :display_name, unique: true
  end
end
