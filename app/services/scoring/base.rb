module Scoring
  # Điểm luôn được tính ở server (BR-02). Mọi giá trị điểm gửi lên từ client bị bỏ qua.
  class Base
    class InvalidAnswer < StandardError; end
    class GradingUnavailable < StandardError; end

    SCORERS = {
      Game::BUG_HUNT => "Scoring::BugHunt",
      Game::SPEC_DETECTIVE => "Scoring::SpecDetective",
      Game::INCIDENT_ESCAPE_ROOM => "Scoring::IncidentEscapeRoom",
      Game::ESTIMATE_POKER => "Scoring::EstimatePoker",
      Game::PROD_ROULETTE => "Scoring::ProdRoulette"
    }.freeze

    def self.for(game)
      class_name = SCORERS.fetch(game.slug) do
        raise ArgumentError, "no scorer for game #{game.slug}"
      end

      class_name.constantize.new
    end

    # session      — GameSession đang chơi, dùng khi cần trạng thái tích luỹ của lượt
    # question     — Question đang được trả lời
    # answer       — hash người chơi gửi lên (đã qua strong parameters)
    # elapsed_ms   — thời gian trả lời do server đo, đã kẹp trần (BR-21)
    def call(session:, question:, answer:, elapsed_ms:)
      raise NotImplementedError
    end

    private

    def fetch_answer(answer, key)
      value = answer[key] || answer[key.to_s]
      raise InvalidAnswer, "thiếu trường #{key}" if value.nil?

      value
    end
  end
end
