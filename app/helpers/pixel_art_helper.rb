# Sprite pixel art vẽ tay theo phong cách JRPG 16x16.
#
# Mỗi sprite là một mảng 16 chuỗi, mỗi chuỗi 16 ký tự. Ký tự tra sang màu trong
# PALETTES; dấu chấm là trong suốt. SVG sinh ra dùng shape-rendering="crispEdges"
# nên phóng to bao nhiêu cũng giữ cạnh sắc như pixel art thật.
#
# Màu khai bằng var(--...) để nhân vật đổi theo bảng màu chung của giao diện.
module PixelArtHelper
  SPRITES = {
    # Nhân vật chính: tóc nâu, áo xanh lá (màu chủ đạo)
    hero: [
      "................",
      "......HHHH......",
      ".....HHHHHH.....",
      "....HHHHHHHH....",
      "....HFFFFFFH....",
      "....HFEFFEFH....",
      "....HFFFFFFH....",
      ".....FFFFFF.....",
      "...GGGGGGGGGG...",
      "..GGGGGGGGGGGG..",
      "..GFGGGGGGGGFG..",
      "..GGGGGGGGGGGG..",
      "...GGGGGGGGGG...",
      "....BB....BB....",
      "....BB....BB....",
      "...SSS....SSS..."
    ],

    # Slime — quái vật kinh điển của mọi JRPG
    slime: [
      "................",
      "................",
      "................",
      "......SSSS......",
      "....SSSSSSSS....",
      "...SSSSSSSSSS...",
      "..SSSSSSSSSSSS..",
      "..SSEESSSSEESS..",
      "..SSEESSSSEESS..",
      ".SSSSSSSSSSSSSS.",
      ".SSSSSSMMSSSSSS.",
      ".SSSSSSSSSSSSSS.",
      "SSSSSSSSSSSSSSSS",
      "SSSSSSSSSSSSSSSS",
      ".SSSSSSSSSSSSSS.",
      "................"
    ],

    # Pháp sư mũ nhọn, áo choàng tím
    mage: [
      ".......MM.......",
      "......MMMM......",
      ".....MMMMMM.....",
      "....MMMMMMMM....",
      "...MMMMMMMMMM...",
      "..MMMMMMMMMMMM..",
      "....FFFFFFFF....",
      "....FEFFFFEF....",
      "....FFFFFFFF....",
      ".....FFFFFF.....",
      "...RRRRRRRRRR...",
      "..RRRRRRRRRRRR..",
      "..RRRRRRRRRRRR..",
      "...RRRRRRRRRR...",
      "....RRRRRRRR....",
      "................"
    ],

    # Rương báu — phần thưởng cuối màn
    chest: [
      "................",
      "................",
      "..WWWWWWWWWWWW..",
      ".WWWWWWWWWWWWWW.",
      ".WBBBBBBBBBBBBW.",
      ".WBBBBBBBBBBBBW.",
      ".WWWWWWWWWWWWWW.",
      ".WBBBBBCCBBBBBW.",
      ".WBBBBBCCBBBBBW.",
      ".WBBBBBBBBBBBBW.",
      ".WBBBBBBBBBBBBW.",
      ".WWWWWWWWWWWWWW.",
      "................",
      "................",
      "................",
      "................"
    ],

    # Đầu lâu — cảnh báo nguy hiểm, dùng cho PROD Roulette
    skull: [
      "................",
      "....SSSSSSSS....",
      "...SSSSSSSSSS...",
      "..SSSSSSSSSSSS..",
      "..SSSSSSSSSSSS..",
      "..SEESSSSSSEES..",
      "..SEESSSSSSEES..",
      "..SSSSSSSSSSSS..",
      "..SSSSSEESSSSS..",
      "...SSSSSSSSSS...",
      "....SSSSSSSS....",
      "....S.SS.S.S....",
      "....SSSSSSSS....",
      "................",
      "................",
      "................"
    ]
  }.freeze

  PALETTES = {
    hero: {
      "H" => "#7a4a24",             # tóc nâu
      "F" => "#ffd8a8",             # da
      "E" => "var(--ink)",          # mắt
      "G" => "var(--grass)",        # áo — màu chủ đạo
      "B" => "#4a3a86",             # quần
      "S" => "#5b3a1c"              # giày
    },
    slime: {
      "S" => "var(--grass)",
      "E" => "var(--ink)",
      "M" => "var(--ink)"           # miệng
    },
    mage: {
      "M" => "var(--berry)",        # mũ
      "F" => "#ffd8a8",
      "E" => "var(--ink)",
      "R" => "var(--berry-dark)"    # áo choàng
    },
    chest: {
      "W" => "#8a5a2b",             # khung gỗ
      "B" => "var(--coin)",         # thân vàng
      "C" => "#8a5a2b"              # ổ khoá
    },
    skull: {
      "S" => "#f4f1e4",
      "E" => "var(--ink)"
    }
  }.freeze

  # Mỗi màn chơi có một nhân vật đại diện.
  GAME_SPRITES = {
    "bug_hunt" => :slime,
    "spec_detective" => :mage,
    "incident_escape_room" => :hero,
    "estimate_poker" => :chest,
    "prod_roulette" => :skull
  }.freeze

  LABELS = {
    hero: "Nhân vật phiêu lưu",
    slime: "Quái slime",
    mage: "Pháp sư",
    chest: "Rương báu",
    skull: "Đầu lâu cảnh báo"
  }.freeze

  def pixel_sprite(name, size: 64, css_class: nil)
    rows = SPRITES.fetch(name.to_sym)
    palette = PALETTES.fetch(name.to_sym)

    tag.svg(
      rects(rows, palette),
      viewBox: "0 0 16 16",
      width: size,
      height: size,
      class: [ "sprite", css_class ].compact.join(" "),
      role: "img",
      "aria-label": LABELS.fetch(name.to_sym, "nhân vật"),
      "shape-rendering": "crispEdges",
      focusable: "false"
    )
  end

  def game_sprite(game, size: 64, css_class: nil)
    pixel_sprite(GAME_SPRITES.fetch(game.slug, :hero), size: size, css_class: css_class)
  end

  private

  # Gộp các pixel liền nhau cùng màu trong một hàng thành một rect,
  # giảm từ 256 phần tử xuống còn vài chục.
  def rects(rows, palette)
    safe_join(
      rows.each_with_index.flat_map do |row, y|
        row_rects(row, y, palette)
      end
    )
  end

  def row_rects(row, y, palette)
    result = []
    x = 0

    while x < row.length
      char = row[x]
      run = 1
      run += 1 while row[x + run] == char
      result << tag.rect(x: x, y: y, width: run, height: 1, fill: palette[char]) if palette.key?(char)
      x += run
    end

    result
  end
end
