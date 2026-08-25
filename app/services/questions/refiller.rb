module Questions
  # Job hằng ngày: tìm game (và ngôn ngữ) đang thiếu đề, sinh bù bằng Gemini rồi nạp vào DB.
  #
  # Ba trần bắt buộc, mỗi trần chặn một cách hỏng khác nhau:
  #
  # 1. KHÔNG nạp khi game còn lượt đang mở. Đề KHÔNG được chốt sẵn lúc tạo lượt: mỗi lần
  #    hiển thị bước và mỗi lần chấm đều bốc lại từ pool sống (StepProvider, BR-36). INSERT
  #    câu mới giữa lượt làm pool đổi, thứ tự MD5 trong Questions::Drawer đổi theo, và người
  #    chơi có thể bị chấm theo câu họ chưa từng thấy. Bỏ qua một ngày rẻ hơn nhiều.
  #    Pool là (game, ngôn ngữ) nên chỉ lượt CÙNG ngôn ngữ mới chặn, và chỉ lượt đã hiển thị
  #    ít nhất một câu mới chặn — xem #open_sessions.
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
    #
    # Nâng 3 -> 10 (owner chốt 2026-08-25): với multiplier 3, Bug Hunt và Estimate Poker
    # (questions_per_session = 10) dừng ở 30 đề và ngân hàng đứng yên từ 2026-08-22 — job
    # chạy xanh mỗi đêm nhưng báo nothing_to_do vì mọi mục tiêu đã chạm trần. 10 lượt đề cho
    # mỗi lượt chơi để người chơi lại nhiều lần vẫn gặp đề mới.
    TARGET_MULTIPLIER = 10
    QUESTIONS_PER_RUN = 10
    # Một mục tiêu tốn nhiều nhất ceil(count/batch_size) + EXTRA_BATCH_ALLOWANCE request, với
    # count = min(shortfall, QUESTIONS_PER_RUN).
    #
    # Game batch_size = 5 (Bug Hunt, Spec Detective, Estimate Poker): ceil(10/5) + 2 = 4.
    # Hai game kịch bản batch_size = 2 (Incident Escape Room, PROD Roulette): từ khi
    # TARGET_MULTIPLIER = 10 thì goal của chúng là 10 chứ không còn 3, nên count chạm được
    # QUESTIONS_PER_RUN và chi phí xấu nhất thành ceil(10/2) + 2 = 7 request.
    #
    # Chỉ có ĐÚNG HAI game kịch bản, nên xấu nhất cho một lần chạy là 7 + 7 + 4 = 18 request —
    # vẫn nằm trong hạn mức đo được 20/ngày (spec §20), nhưng chỉ còn dư 2. Trường hợp đó chỉ
    # xảy ra khi hai game kịch bản đang thiếu nhiều hơn mọi mục tiêu Bug Hunt, vì mục tiêu
    # được chọn theo shortfall giảm dần. Nếu sau này thêm game kịch bản thứ ba thì phải hạ
    # MAX_TARGETS_PER_RUN hoặc QUESTIONS_PER_RUN, không thì lần chạy sẽ vượt hạn mức.
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
    # question_served: lượt chưa hiển thị câu nào KHÔNG chặn. Rủi ro của việc nạp giữa lượt là
    # câu ĐÃ hiển thị khác câu được chấm, vì StepProvider bốc lại từ pool sống bằng seed
    # "#{session.id}:#{position}" cho cả hai lần (step_provider.rb). Lượt chưa hiển thị gì thì
    # không có câu nào để lệch: insert xong, cả lần hiển thị và lần chấm đều đọc pool mới.
    # Đây là thứ mở được cửa refill trong thực tế — 2026-08-21 cả 5 lượt đang chặn đều ở vị
    # trí 0 và chưa phát câu nào, tức người chơi bấm "Bắt đầu lượt" rồi rời đi.
    #
    # Còn một race hẹp: người chơi gọi GET current đúng lúc import đang chạy. Cùng loại race
    # đã có sẵn (người chơi mở lượt mới ngay sau khi kiểm tra), không tệ hơn về bản chất.
    #
    # Lượt của game phân ngôn ngữ mà language NULL vẫn tính là chặn MỌI ngôn ngữ:
    # GameSessions::Creator luôn set giá trị này, nhưng cột nullable và model không validate,
    # nên bản ghi cũ dạng đó không xác định được thuộc pool nào.
    def open_sessions(target)
      scope = GameSession.question_served
                         .where(game: target.game, state: GameSession::IN_PROGRESS)
      return scope unless target.game.language_scoped?

      scope.where(language: [ target.language, nil ])
    end
  end
end
