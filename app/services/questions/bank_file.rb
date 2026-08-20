module Questions
  # Ghi một lô đề vừa sinh ra file YAML trong db/question_banks/<game>/.
  #
  # File này là bản ghi duy nhất cho biết ĐÚNG nội dung gì đã vào DB trong một lần chạy —
  # bảng questions chỉ giữ `source: ai_generated` và `generated_at`, không giữ prompt hay
  # lô nào. Giữ file lại để soát hậu kiểm và để git diff thấy được đề mới.
  #
  # Không ghi đè file đã tồn tại: file cũ có thể đã được sửa tay.
  class BankFile
    HEADER = <<~TEXT
      # Đề do Gemini sinh.
      #
      # Q4 (owner chốt 2026-08-19): không cần người soát tay trước khi import. File này giữ
      # lại làm bản ghi những gì đã vào DB — sửa file rồi import lại sẽ CẬP NHẬT câu cũ nếu
      # content không đổi (dedupe theo checksum), hoặc tạo câu mới nếu content đổi.
    TEXT

    def self.write(game:, language:, batch:, dir: nil)
      new(game: game, language: language, batch: batch, dir: dir).call
    end

    # dir: chỉ test truyền — để không ghi rác vào db/question_banks của repo.
    def initialize(game:, language:, batch:, dir: nil)
      @game = game
      @language = language
      @batch = batch
      @dir = dir || Rails.root.join("db", "question_banks", game.slug)
    end

    def call
      path = next_free_path
      payload = { "game" => @game.slug, "model" => @batch.model,
                  "generated_at" => Time.current.iso8601 }
      payload["language"] = @language if @language
      payload["questions"] = @batch.records

      # deep_dup trước khi dump: nhiều câu dùng chung object Question::BUG_HUNT_TYPES, và
      # Psych sẽ sinh anchor/alias (*id001) cho object trùng — đọc rất khó khi soát tay.
      path.write(HEADER + payload.deep_dup.to_yaml)
      path
    end

    private

    def next_free_path
      dir = Pathname.new(@dir)
      dir.mkpath

      base = [ Date.current.iso8601, @language ].compact.join("-")
      path = dir.join("#{base}.yml")
      suffix = 2
      while path.exist?
        path = dir.join("#{base}-#{suffix}.yml")
        suffix += 1
      end

      path
    end
  end
end
