module Questions
  # Job hằng ngày: tìm game (và ngôn ngữ) đang thiếu đề, sinh bù bằng Gemini rồi nạp vào DB.
  #
  # Ba trần bắt buộc, mỗi trần chặn một cách hỏng khác nhau:
  #
  # 1. KHÔNG nạp khi game còn lượt đang mở. Đề KHÔNG được chốt sẵn lúc tạo lượt: mỗi lần
  #    hiển thị bước và mỗi lần chấm đều bốc lại từ pool sống (StepProvider, BR-36). INSERT
  #    câu mới giữa lượt làm pool đổi, thứ tự MD5 trong Questions::Drawer đổi theo, và người
  #    chơi có thể bị chấm theo câu họ chưa từng thấy. Bỏ qua một ngày rẻ hơn nhiều.
  #    Pool là (game, ngôn ngữ) nên chỉ lượt CÙNG ngôn ngữ mới chặn — xem #open_sessions.
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
    # Một mục tiêu tốn nhiều nhất ceil(count/batch_size) + EXTRA_BATCH_ALLOWANCE request. Với
    # QUESTIONS_PER_RUN = 10 và batch_size = 5 thì là 2 + 2 = 4; hai game kịch bản có
    # batch_size = 2 nhưng goal chỉ 3 đề (questions_per_session = 1) nên count không tới 10,
    # vẫn là ceil(3/2) + 2 = 4. Nên 3 mục tiêu = tối đa 12 request, còn dư trong hạn mức đo
    # được 20/ngày cho một lần chạy tay trong cùng ngày.
    #
    # Để 1 là quá chậm khi thiếu ở nhiều mục tiêu cùng lúc: 2026-08-21 tổng thiếu 87 đề trên
    # 6 mục tiêu, với 10 đề mỗi lần chạy thì cần hàng tuần mới bù xong.
    MAX_TARGETS_PER_RUN = 3

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

      # Lọc mục tiêu bị chặn TRƯỚC khi chọn, không phải sau. Chọn trước rồi mới kiểm thì một
      # mục tiêu bị chặn làm cả lần chạy thành vô ích, dù còn mục tiêu khác nạp được ngay —
      # gặp thật trên production: cả 6 mục tiêu thiếu đề đều có lượt đang mở nên lần chạy
      # đầu tiên sinh 0 đề mà vẫn báo xanh.
      blocked, eligible = shortfalls.partition { |target| sessions_open?(target) }

      # Thiếu nhiều nhất được ưu tiên: game nào sắp không chơi được thì bù trước.
      refilled = eligible.sort_by { |target| -target.shortfall }
                         .first(@max_targets)
                         .map { |target| refill(target) }

      # Vẫn báo ra mục tiêu bị chặn: im lặng thì không phân biệt được "hôm nay đủ đề rồi" với
      # "hôm nay không nạp được vì lúc nào cũng có người đang chơi".
      refilled + blocked.map { |target| skipped(target) }
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

    def skipped(target)
      open_count = open_sessions(target).count

      Outcome.new(label: target.label, status: :skipped,
                  detail: "còn #{open_count} lượt đang chơi — nạp đề giữa lượt sẽ chấm sai câu " \
                          "(thiếu #{target.shortfall} đề)")
    end

    def refill(target)
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
    def sessions_open?(target)
      open_sessions(target).exists?
    end

    # PHẢI lọc theo ngôn ngữ: pool của Questions::Drawer là (game, language), nên lượt
    # bug_hunt/java không liên quan gì tới việc nạp thêm đề bug_hunt/php. Chỉ lọc theo game là
    # lỗi đã gặp thật — log 2026-08-21 cho cả 4 mục tiêu bug_hunt cùng báo "5 lượt đang chơi",
    # tức cùng một tập lượt bị đếm 4 lần: một người chơi ở BẤT KỲ ngôn ngữ nào cũng chặn cả 4,
    # job báo xanh mà không nạp được đề nào.
    #
    # Lượt của game phân ngôn ngữ mà language NULL vẫn tính là chặn MỌI ngôn ngữ:
    # GameSessions::Creator luôn set giá trị này, nhưng cột nullable và model không validate,
    # nên bản ghi cũ dạng đó không xác định được thuộc pool nào.
    def open_sessions(target)
      scope = GameSession.where(game: target.game, state: GameSession::IN_PROGRESS)
      return scope unless target.game.language_scoped?

      scope.where(language: [ target.language, nil ])
    end
  end
end
