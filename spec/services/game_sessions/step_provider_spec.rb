require "rails_helper"

RSpec.describe GameSessions::StepProvider do
  let(:user) { create(:user) }

  def content_for(session)
    described_class.new(session).payload[:content]
  end

  # Đề trong ngân hàng để phương án tốt nhất ở vị trí đầu, nên nếu payload giữ nguyên thứ
  # tự đó thì bấm ô đầu tiên là ăn điểm mà không cần đọc đề.
  describe "Spec Detective" do
    let(:game) do
      create(:game, slug: Game::SPEC_DETECTIVE, name: "Spec Detective",
             questions_per_session: 1, steps_per_session: 1)
    end

    let!(:question) do
      create(:question, game: game,
             content: {
               "statements" => [ "Xử lý đơn nhanh.", "Lưu vào bảng orders.",
                                 "Thông báo nếu cần thiết." ],
               "clarifying_options" => [
                 { "key" => "a", "label" => "Nhanh là mấy giây?" },
                 { "key" => "b", "label" => "Lưu ở bảng nào?" },
                 { "key" => "c", "label" => "Báo cáo có cần đẹp không?" },
                 { "key" => "d", "label" => "Dùng framework gì?" }
               ]
             },
             answer_key: { "ambiguous_statement_indexes" => [ 1 ],
                           "best_option_key" => "a", "explanation" => "vì đo được" })
    end

    it "giữ đủ phương án, chỉ đổi thứ tự hiển thị" do
      shown = content_for(create(:game_session, user: user, game: game))["clarifying_options"]

      expect(shown).to match_array(question.content["clarifying_options"])
    end

    it "không đảo thứ tự các câu trong đoạn spec" do
      shown = content_for(create(:game_session, user: user, game: game))

      expect(shown["statements"]).to eq(question.content["statements"])
    end

    it "không để phương án đúng luôn ở vị trí đầu" do
      orders = 10.times.map do
        content_for(create(:game_session, user: user, game: game))["clarifying_options"]
          .map { |o| o["key"] }
      end

      expect(orders.uniq.size).to be > 1
      expect(orders.map(&:first).uniq).not_to eq([ "a" ])
    end

    it "tải lại giữa bước vẫn thấy đúng thứ tự đó" do
      session = create(:game_session, user: user, game: game)
      first = content_for(session)["clarifying_options"]

      expect(content_for(session)["clarifying_options"]).to eq(first)
    end
  end

  describe "game kịch bản" do
    let(:game) { create(:game, :scenario_based, steps_per_session: 2) }

    let!(:question) do
      create(:question, game: game,
             content: {
               "scenario" => "Kịch bản test",
               "nodes" => [
                 { "key" => "n1", "prompt" => "Bước 1",
                   "options" => [ { "key" => "s1a", "label" => "an toàn" },
                                  { "key" => "s1b", "label" => "không thu hồi được" },
                                  { "key" => "s1c", "label" => "nửa vời" } ] },
                 { "key" => "n2", "prompt" => "Bước 2",
                   "options" => [ { "key" => "s2a", "label" => "an toàn" },
                                  { "key" => "s2b", "label" => "không thu hồi được" },
                                  { "key" => "s2c", "label" => "nửa vời" } ] }
               ]
             },
             answer_key: { "option_effects" => {
               "s1a" => { "points" => 10 }, "s1b" => { "points" => 0 },
               "s1c" => { "points" => 3 }, "s2a" => { "points" => 10 },
               "s2b" => { "points" => 0 }, "s2c" => { "points" => 3 }
             } })
    end

    it "giữ nguyên thứ tự node, chỉ đảo thứ tự phương án trong node" do
      nodes = content_for(create(:game_session, user: user, game: game))["nodes"]

      expect(nodes.map { |n| n["key"] }).to eq(%w[n1 n2])
      expect(nodes.first["options"])
        .to match_array(question.content["nodes"].first["options"])
    end

    it "không để phương án đúng luôn ở vị trí đầu" do
      firsts = 10.times.map do
        content_for(create(:game_session, user: user, game: game))["nodes"]
          .first["options"].first["key"]
      end

      expect(firsts.uniq.size).to be > 1
    end

    it "tải lại giữa bước vẫn thấy đúng thứ tự đó" do
      session = create(:game_session, user: user, game: game)
      first = content_for(session)["nodes"]

      expect(content_for(session)["nodes"]).to eq(first)
    end
  end
end
