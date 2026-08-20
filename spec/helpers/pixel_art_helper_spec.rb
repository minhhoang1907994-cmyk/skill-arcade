require "rails_helper"

RSpec.describe PixelArtHelper, type: :helper do
  describe "SPRITES" do
    PixelArtHelper::SPRITES.each do |name, rows|
      context "sprite #{name}" do
        it "là lưới 16x16" do
          expect(rows.size).to eq(16)
          expect(rows.map(&:length).uniq).to eq([ 16 ])
        end

        it "có màu cho mọi ký tự đã dùng, và không khai màu thừa" do
          palette = PixelArtHelper::PALETTES.fetch(name)
          used = rows.join.chars.uniq - [ "." ]

          expect(used - palette.keys).to be_empty
          expect(palette.keys - used).to be_empty
        end

        it "có nhãn cho screen reader" do
          expect(PixelArtHelper::LABELS[name]).to be_present
        end
      end
    end
  end

  describe "khai báo tham chiếu sprite" do
    it "SCENERY, PARTY và GAME_SPRITES chỉ dùng sprite đã định nghĩa" do
      referenced = PixelArtHelper::SCENERY.map(&:first) +
        PixelArtHelper::PARTY.map(&:first) +
        PixelArtHelper::GAME_SPRITES.values

      expect(referenced.uniq - PixelArtHelper::SPRITES.keys).to be_empty
    end

    it "mỗi slot và kiểu chuyển động của SCENERY đều có rule trong application.css" do
      css = Rails.root.join("app/assets/stylesheets/application.css").read

      PixelArtHelper::SCENERY.each do |_name, slot, motion, _size|
        expect(css).to include(".scenery__item--#{slot} ")
        expect(css).to include(".scenery__item--#{motion} ")
      end
    end
  end

  describe "#pixel_sprite" do
    it "sinh SVG giữ cạnh pixel kèm aria-label" do
      svg = helper.pixel_sprite(:knight, size: 48)

      expect(svg).to include('viewBox="0 0 16 16"', 'width="48"', 'shape-rendering="crispEdges"')
      expect(svg).to include(%(aria-label="#{PixelArtHelper::LABELS[:knight]}"))
    end

    it "gộp pixel liền nhau cùng màu thành một rect" do
      # Hàng 2 của ghost là 10 pixel liền nhau cùng màu -> đúng một rect rộng 10.
      expect(helper.pixel_sprite(:ghost)).to include('<rect x="3" y="2" width="10" height="1"')
    end
  end

  describe "#party_sprites" do
    it "sinh đúng số nhân vật của đội hình, mỗi con một sprite nhún" do
      html = helper.party_sprites

      expect(html.scan("party__member").size).to eq(PixelArtHelper::PARTY.size)
      expect(html.scan("sprite--bounce").size).to eq(PixelArtHelper::PARTY.size)
    end
  end

  describe "#scenery_sprites" do
    it "sinh đủ item trang trí hai lề" do
      expect(helper.scenery_sprites.scan("scenery__item ").size).to eq(PixelArtHelper::SCENERY.size)
    end
  end
end
