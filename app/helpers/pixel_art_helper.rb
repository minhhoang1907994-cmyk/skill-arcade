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
    ],

    # --- Item trang trí đồng cỏ hai bên trang (PixelArtHelper#scenery_items) ---

    # Bụi cây
    bush: [
      "................",
      "................",
      "................",
      "......DDDD......",
      "....DDGGGGDD....",
      "...DGGGGGGGGD...",
      "..DGGGGGGGGGGD..",
      "..DGGGGGGGGGGD..",
      ".DGGGGGGGGGGGGD.",
      ".DGGGGGGGGGGGGD.",
      ".DDGGGGGGGGGGDD.",
      "..DDDDDDDDDDDD..",
      ".....BB..BB.....",
      ".....BB..BB.....",
      "................",
      "................"
    ],

    # Hoa cúc
    flower: [
      "................",
      "................",
      ".....PP.PP......",
      "....PPPPPPP.....",
      "....PPCCCPP.....",
      "....PPCCCPP.....",
      "....PPPPPPP.....",
      ".....PP.PP......",
      ".......GG.......",
      ".......GG.......",
      "....LL.GG.......",
      "...LLL.GG.......",
      ".......GGLLL....",
      ".......GG.LL....",
      ".......GG.......",
      "................"
    ],

    # Đồng xu
    coin: [
      "................",
      "................",
      ".....DDDDDD.....",
      "...DDCCCCCCDD...",
      "..DCCCCCCCCCCD..",
      "..DCCHHCCCCCCD..",
      ".DCCHHCCCCCCCCD.",
      ".DCCCCCCCCCCCCD.",
      ".DCCCCCCCCCCCCD.",
      ".DCCCCCCCCCCCCD.",
      ".DCCCCCCCCCCCCD.",
      "..DCCCCCCCCCCD..",
      "..DCCCCCCCCCCD..",
      "...DDCCCCCCDD...",
      ".....DDDDDD.....",
      "................"
    ],

    # Bình thuốc hồi phục
    potion: [
      "................",
      "......WWWW......",
      "......W..W......",
      "......W..W......",
      ".....WW..WW.....",
      "....WW....WW....",
      "...WW..PP..WW...",
      "..WW..PPPP..WW..",
      "..W..PPPPPP..W..",
      "..W.PPPPPPPP.W..",
      "..W.PPPPPPPP.W..",
      "..WW.PPPPPP.WW..",
      "...WW.PPPP.WW...",
      "....WWWWWWWW....",
      "................",
      "................"
    ],

    # Thanh kiếm
    sword: [
      ".......SS.......",
      "......SBBS......",
      "......SBBS......",
      "......SBBS......",
      "......SBBS......",
      "......SBBS......",
      "......SBBS......",
      "......SBBS......",
      "...GGGGGGGGGG...",
      "...GGGGGGGGGG...",
      "......HHHH......",
      "......HHHH......",
      "......HHHH......",
      ".....HHHHHH.....",
      "......PPPP......",
      "................"
    ],

    # Nấm
    mushroom: [
      "................",
      "................",
      ".....RRRRRR.....",
      "...RRRRRRRRRR...",
      "..RRWWRRRRWWRR..",
      "..RRWWRRRRWWRR..",
      ".RRRRRRRRRRRRRR.",
      ".RRRRWWRRWWRRRR.",
      "..RRRRRRRRRRRR..",
      "....SSSSSSSS....",
      "....SSSSSSSS....",
      "....SSSSSSSS....",
      "....SSSSSSSS....",
      ".....SSSSSS.....",
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
    },
    bush: {
      "D" => "var(--grass-deep)",    # viền và phần bóng
      "G" => "var(--grass)",
      "B" => "#7a4a24"               # thân gỗ
    },
    flower: {
      "P" => "#fff3f6",              # cánh
      "C" => "var(--coin)",          # nhị
      "G" => "var(--grass-deep)",    # thân
      "L" => "var(--grass-dark)"     # lá
    },
    coin: {
      "D" => "var(--coin-dark)",
      "C" => "var(--coin)",
      "H" => "#fffdf0"               # điểm sáng
    },
    potion: {
      "W" => "#e8f6ff",              # thuỷ tinh
      "P" => "var(--brick)"          # thuốc
    },
    sword: {
      "S" => "#eef4ff",              # lưỡi, mặt sáng
      "B" => "#b3c4e0",              # lưỡi, mặt tối
      "G" => "var(--coin-dark)",     # chắn tay
      "H" => "#7a4a24",              # cán
      "P" => "var(--coin)"           # núm cán
    },
    mushroom: {
      "R" => "var(--brick)",
      "W" => "#fff8ee",              # đốm
      "S" => "#f3e6cf"               # cuống
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
    skull: "Đầu lâu cảnh báo",
    bush: "Bụi cây",
    flower: "Hoa",
    coin: "Đồng xu",
    potion: "Bình thuốc",
    sword: "Thanh kiếm",
    mushroom: "Nấm"
  }.freeze

  # Item trang trí ở hai lề trang: [sprite, slot vị trí, kiểu chuyển động, bề rộng px].
  #
  # Bề rộng ở đây gắn với khoảng lệch của đúng slot đó trong application.css
  # (.scenery__item--l1 ...) — đổi số ở đây thì phải tính lại khoảng lệch bên CSS,
  # không thì sprite đè lên khối main hoặc bị cắt ở mép màn hình.
  SCENERY = [
    [ :bush,     "l1", "sway", 46 ],
    [ :flower,   "l2", "sway", 34 ],
    [ :coin,     "l3", "flip", 30 ],
    [ :slime,    "l4", "bob",  40 ],
    [ :mushroom, "l5", "sway", 34 ],
    [ :flower,   "r1", "sway", 32 ],
    [ :potion,   "r2", "bob",  34 ],
    [ :sword,    "r3", "bob",  38 ],
    [ :chest,    "r4", "sway", 42 ],
    [ :coin,     "r5", "flip", 28 ]
  ].freeze

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

  # Thuần trang trí — layout bọc trong container aria-hidden nên aria-label của từng
  # sprite không đọc lên cho screen reader.
  def scenery_sprites
    safe_join(
      SCENERY.map do |name, slot, motion, size|
        pixel_sprite(
          name, size: size,
          css_class: "scenery__item scenery__item--#{slot} scenery__item--#{motion}"
        )
      end
    )
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
