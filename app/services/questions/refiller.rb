module Questions
  # Job hằng ngày: tìm game (và ngôn ngữ) đang thiếu đề, sinh bù bằng Gemini rồi nạp vào DB.
  #
  # Ba trần bắt buộc, mỗi trần chặn một cách hỏng khác nhau:
  #
  # 1. KHÔNG nạp khi game còn lượt đang mở. Đề KHÔNG được chốt sẵn lúc tạo lượt: mỗi lần
  #    hiển thị bước và mỗi lần chấm đều bốc lại từ pool sống (StepProvider, BR-36). INSERT
  #    câu mới giữa lượt làm pool đổi, thứ tự MD5 trong Questions::Drawer đổi theo, và người
  #    chơi có thể bị chấm theo câu họ chưa từng thấy. Bỏ qua một ngày rẻ hơn nhiều.
  # 2. CHỈ sinh khi thiếu. Đủ đề thì tốn 0 request — không thì ngân hàng phình vô hạn và
  #    hạn mức Gemini bị đốt mỗi ngày để lấy đề không ai cần.
  # 3. MỖI LẦN CHẠY chỉ xử lý MAX_TARGETS_PER_RUN mục tiêu. Generator gọi tối đa
  #    ceil(count/batch_size) + EXTRA_BATCH_ALLOWANCE request cho một mục tiêu, nên trần này
  #    là thứ giữ tổng request trong hạn mức đo được (20/ngày, spec §20).
  #
  # KHÔNG tự thêm ngôn ngữ mới cho Bug Hunt: chỉ refill ngôn ngữ đã có trong ngân hàng.
  # Ngôn ngữ mới xuất hiện trên UI phải là một quyết định, không phải tác dụng phụ của job.
  class Refiller
    # Ngưỡng "đủ": bao nhiêu lượt đề so với một lượt chơi. Đúng questions_per_session là vừa
    # đủ MỘT lượt, tức chơi lại là gặp lại toàn bộ câu cũ (BR-32 phải fallback).
    TARGET_MULTIPLIER = 3
    QUESTIONS_PER_RUN = 10
    MAX_TARGETS_PER_RUN = 1

    Target = Struct.new(:game, :language, :playable, :goal, keyword_init: true) do
      def shortfall
        goal - playable
      end

      def label
        [ game.slug, language ].compact.join("/")
      end
    end

    Outcome = Struct.new(:label, :status, :detail, keyword_init: true)

    def initialize(per_run: QUESTIONS_PER_RUN, max_targets: MAX_TARGETS_PER_RUN,
                   generator_builder: nil, bank_dir: nil)
      @per_run = per_run
      @max_targets = max_targets
      @bank_dir = bank_dir
      @generator_builder = generator_builder ||
                           ->(game, language) { Generator.new(game: game, language: language) }
    end

    def call
      shortfalls = targets.select { |target| target.shortfall.positive? }
      return [ Outcome.new(label: "-", status: :nothing_to_do, detail: "mọi game đã đủ đề") ] if
        shortfalls.empty?

      # Thiếu nhiều nhất được ưu tiên: game nào sắp không chơi được thì bù trước.
      shortfalls.sort_by { |target| -target.shortfall }
                .first(@max_targets)
                .map { |target| refill(target) }
    end

    # Mục tiêu = một (game, ngôn ngữ). Game không phân ngôn ngữ thì language = nil.
    def targets
      Game.active.order(:id).flat_map do |game|
        languages = game.language_scoped? ? game.available_languages : [ nil ]
        languages.map { |language| build_target(game, language) }
      end
    end

    private

    def build_target(game, language)
      playable = Question.playable.where(game: game).in_language(language).count

      Target.new(game: game, language: language, playable: playable,
                 goal: game.questions_per_session * TARGET_MULTIPLIER)
    end

    def refill(target)
      if sessions_open?(target.game)
        return Outcome.new(label: target.label, status: :skipped,
                           detail: "còn lượt đang chơi — nạp đề giữa lượt sẽ chấm sai câu")
      end

      count = [ target.shortfall, @per_run ].min
      batch = @generator_builder.call(target.game, target.language).call(count: count)

      if batch.records.empty?
        return Outcome.new(label: target.label, status: :failed,
                           detail: "Gemini không trả đề nào dùng được")
      end

      path = BankFile.write(game: target.game, language: target.language, batch: batch,
                            dir: @bank_dir)
      report = Importer.new(path: path).call

      Outcome.new(label: target.label, status: :done,
                  detail: "#{report.created} mới, #{report.updated} cập nhật, " \
                          "#{report.rejected.size} bị loại — #{path.basename}")
    rescue Generator::UnsupportedGame, Gemini::Error, Importer::InvalidFile => e
      Outcome.new(label: target.label, status: :failed, detail: "#{e.class}: #{e.message}")
    end

    # Kiểm tra SAU khi game_sessions:expire_stale đã chạy, không thì lượt treo vĩnh viễn ở
    # in_progress (BR-24 chưa từng có scheduler) sẽ chặn refill mãi mãi.
    def sessions_open?(game)
      GameSession.where(game: game, state: GameSession::IN_PROGRESS).exists?
    end
  end
end
