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
  # Thứ tự ưu tiên khi số mục tiêu thiếu đề vượt trần: mục tiêu ĐANG CÓ ÍT ĐỀ NHẤT được bù
  # trước, đo bằng playable tuyệt đối chứ không phải khoảng cách tới goal riêng — xem #call.
  #
  # KHÔNG tự thêm ngôn ngữ mới cho Bug Hunt: chỉ refill ngôn ngữ đã có trong ngân hàng.
  # Ngôn ngữ mới xuất hiện trên UI phải là một quyết định, không phải tác dụng phụ của job.
  class Refiller
    # Ngưỡng "đủ" của MỌI mục tiêu (game, ngôn ngữ). Là số TUYỆT ĐỐI, cố ý KHÔNG nhân theo
    # questions_per_session.
    #
    # Trước 2026-08-28 goal = questions_per_session * 10, nên goal lệch 10 lần giữa các game:
    # bug_hunt và estimate_poker 100, spec_detective 50, hai game kịch bản 10. Hai game kịch
    # bản vì thế bị coi là "đủ đề" ngay khi có 10 câu và rớt khỏi hàng đợi, nhường slot cho
    # bug_hunt vốn đã có 49-57 đề mỗi ngôn ngữ. Đo được ngày 2026-08-28: incident_escape_room
    # chạm 10 đề ở lần chạy đầu thì lần chạy sau bug_hunt/php (49 đề) được chọn thay nó.
    #
    # Goal chung nghĩa là mục tiêu nghèo nhất ở lại hàng đợi tới khi bằng những mục tiêu khác
    # (owner chốt 2026-08-28). questions_per_session = 1 không còn làm một game bị coi là đủ
    # đề sớm hơn game khác 10 lần.
    #
    # Hệ quả phụ: goal đã bằng nhau thì sắp theo playable tăng dần và sắp theo shortfall giảm
    # dần cho ra CÙNG thứ tự (shortfall = GOAL_PER_TARGET - playable). Tiêu chí playable ở
    # #call giữ nguyên vì nó vẫn đúng nếu sau này goal lại khác nhau giữa các mục tiêu.
    GOAL_PER_TARGET = 100
    QUESTIONS_PER_RUN = 10
    # Một mục tiêu tốn nhiều nhất ceil(count/batch_size) + EXTRA_BATCH_ALLOWANCE request, với
    # count = min(shortfall, QUESTIONS_PER_RUN).
    #
    # Game batch_size = 5 (Bug Hunt, Spec Detective, Estimate Poker): ceil(10/5) + 2 = 4.
    # Hai game kịch bản batch_size = 2 (Incident Escape Room, PROD Roulette): goal của chúng
    # là GOAL_PER_TARGET như mọi mục tiêu khác, nên count chạm được QUESTIONS_PER_RUN và chi
    # phí xấu nhất thành ceil(10/2) + 2 = 7 request.
    #
    # Chỉ có ĐÚNG HAI game kịch bản, nên xấu nhất cho một lần chạy là 7 + 7 + 4 = 18 request —
    # vẫn nằm trong hạn mức đo được 20/ngày (spec §20), nhưng chỉ còn dư 2.
    #
    # Từ 2026-08-27 mục tiêu được chọn theo playable tăng dần (#call), và hai game kịch bản
    # luôn là hai mục tiêu ít đề nhất, nên trường hợp 18 request này thành trường hợp THƯỜNG
    # GẶP chứ không còn là ngoại lệ như thời sắp theo shortfall. Trần vẫn đủ, nhưng nếu sau
    # này thêm game kịch bản thứ ba thì phải hạ MAX_TARGETS_PER_RUN hoặc QUESTIONS_PER_RUN —
    # 7 + 7 + 7 = 21 là vượt hạn mức.
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
      all_targets = targets
      shortfalls = all_targets.select { |target| target.shortfall.positive? }
      return [ Outcome.new(label: "-", status: :nothing_to_do, detail: "mọi game đã đủ đề") ] if
        shortfalls.empty?

      # Lọc mục tiêu bị chặn TRƯỚC khi chọn, không phải sau. Chọn trước rồi mới kiểm thì một
      # mục tiêu bị chặn làm cả lần chạy thành vô ích, dù còn mục tiêu khác nạp được ngay —
      # gặp thật trên production: cả 6 mục tiêu thiếu đề đều có lượt đang mở nên lần chạy
      # đầu tiên sinh 0 đề mà vẫn báo xanh.
      blocked, eligible = shortfalls.partition { |target| sessions_open?(target) }

      # Mốc so sánh là mục tiêu ĐANG CÓ NHIỀU ĐỀ NHẤT, tính trên MỌI mục tiêu — kể cả cái đã
      # đủ goal và cái đang bị chặn. Lấy max trên riêng `eligible` thì mốc tụt xuống đúng vào
      # ngày các mục tiêu giàu bị chặn, và số ghi ra log sẽ khác nhau giữa hai ngày dù ngân
      # hàng không đổi.
      richest = all_targets.map(&:playable).max.to_i

      # Ít đề nhất được ưu tiên (owner chốt 2026-08-27). Trước đây sắp theo shortfall giảm
      # dần, tức theo khoảng cách tới GOAL RIÊNG của từng mục tiêu — mà goal khi đó =
      # questions_per_session * 10 nên nó lệch 10 lần giữa các game (bug_hunt và
      # estimate_poker 100, spec_detective 50, hai game kịch bản 10). Hệ quả đo được trên
      # production 2026-08-27: bug_hunt/php còn 49 đề (shortfall 51) luôn xếp trên
      # prod_roulette còn 3 đề (shortfall 7), nên từ 2026-08-25 cả 3 slot mỗi đêm đều về
      # bug_hunt, còn prod_roulette chưa từng được sinh câu nào (ai_generated = 0).
      #
      # Sắp theo playable tăng dần thì mục tiêu nghèo nhất luôn đứng đầu, bất kể goal của nó
      # to nhỏ ra sao. Tie-break: thiếu nhiều hơn trước, rồi tới label để thứ tự ổn định giữa
      # các lần chạy — bằng điểm mà đổi thứ tự thì log hai ngày không đối chiếu được.
      refilled = eligible.sort_by { |target| [ target.playable, -target.shortfall, target.label ] }
                         .first(@max_targets)
                         .map { |target| refill(target, richest: richest) }

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

      Target.new(game: game, language: language, playable: playable, goal: GOAL_PER_TARGET)
    end

    def skipped(target)
      open_count = open_sessions(target).count

      Outcome.new(label: target.label, status: :skipped,
                  detail: "còn #{open_count} lượt đang chơi — nạp đề giữa lượt sẽ chấm sai câu " \
                          "(thiếu #{target.shortfall} đề)")
    end

    def refill(target, richest:)
      count = [ target.shortfall, @per_run ].min
      batch = @generator_builder.call(target.game, target.language).call(count: count)

      if batch.records.empty?
        return Outcome.new(label: target.label, status: :failed,
                           detail: "Gemini không trả đề nào dùng được")
      end

      path = BankFile.write(game: target.game, language: target.language, batch: batch,
                            dir: @bank_dir)
      report = Importer.new(path: path).call

      # Ghi cả playable và khoảng cách tới mục tiêu nhiều đề nhất vào log: đọc log là biết
      # được chọn vì nghèo tới mức nào, không phải mở console query lại DB mới đối chiếu được.
      #
      # Lô lỗi vẫn để status :done vì đề đã vào DB thật — nhưng PHẢI in ra. Job đỏ vì một
      # 503 lẻ thì đỏ gần như mỗi đêm và không ai còn đọc, còn im lặng thì không phân biệt
      # được "hôm nay Gemini chập chờn" với "hôm nay chạy trơn tru".
      Outcome.new(label: target.label, status: :done,
                  detail: "#{report.created} mới, #{report.updated} cập nhật, " \
                          "#{report.rejected.size} bị loại#{failure_note(batch)} — " \
                          "#{path.basename} " \
                          "(đang có #{target.playable} đề, ít hơn mục tiêu nhiều đề nhất " \
                          "#{richest - target.playable} đề)")
    rescue Questions::Error, Gemini::Error => e
      Outcome.new(label: target.label, status: :failed, detail: "#{e.class}: #{e.message}")
    end

    # Lô lỗi lẻ không còn làm mất cả mục tiêu (Generator#call từ 2026-09-03), nhưng vẫn phải
    # thấy được trong log: đề nạp về ít hơn count là do Gemini chập chờn chứ không phải do
    # ngân hàng đã gần đủ.
    def failure_note(batch)
      failures = batch.failures
      return "" if failures.empty?

      # uniq trên message chứ không chỉ lấy cái cuối: một mục tiêu có thể trượt vì hai
      # nguyên nhân khác nhau (503 rồi MAX_TOKENS), in mỗi cái cuối là chẩn đoán sai.
      ", #{failures.size} lô lỗi (#{failures.map(&:message).uniq.join('; ')})"
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
