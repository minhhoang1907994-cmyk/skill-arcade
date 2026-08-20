class AddStepServedAtToGameSessions < ActiveRecord::Migration[8.1]
  def change
    # BR-21: mốc thời gian câu hỏi đang chờ trả lời được PHÁT RA cho client.
    #
    # Trước cột này `elapsed_ms` phía server được đo từ `answered_at` của câu TRƯỚC. Nhưng
    # client giữ phần giải thích trên màn hình cho tới khi người chơi bấm "Câu tiếp theo",
    # nên thời gian đọc giải thích bị cộng vào đồng hồ của câu sau — cùng một đáp án đúng
    # nhận 10đ hay 8đ tuỳ người chơi đọc giải thích nhanh hay chậm.
    #
    # Nullable: null nghĩa là câu đang chờ chưa được phát ra lần nào. Lượt đang chơi dở
    # lúc migration chạy sẽ có null và rơi về mốc cũ (xem AnswerSubmitter#step_started_at).
    add_column :game_sessions, :step_served_at, :datetime
  end
end
