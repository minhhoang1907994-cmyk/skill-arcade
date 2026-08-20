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

    # --- Nhân vật và quái vật JRPG (dùng cho card màn chơi + dải trận đánh) ---

    # Hiệp sĩ: mũ giáp có chùm lông, khiên tròn tay trái, kiếm dựng tay phải.
    # Giáp viền bằng D (tông tối) để lưỡi kiếm sáng không lẫn vào thân.
    knight: [
      ".......PP.......",
      "......PPPP......",
      ".....DAAAAD.....",
      "....DAAAAAAD....",
      "....DAEEEEAD.SS.",
      "....DAAAAAAD.SS.",
      ".....DAAAAD..SS.",
      "...GGGGGGGGG.SS.",
      "..VWWDAAAAAD.SS.",
      ".VWWWDAAAAADGGGG",
      ".VWWWDAAAAAD..H.",
      ".VWWWDAAAAAD..H.",
      "..VWWDAAAAAD....",
      "...VVDAAAAAD....",
      ".....DDD.DDD....",
      "....DDDD.DDDD..."
    ],

    # Cung thủ: mũ trùm xanh, cung bên phải đã lắp tên
    archer: [
      "................",
      ".....HHHH.......",
      "....HHHHHH......",
      "....HFFFFH.TBB..",
      "....FEFFEF.T..B.",
      "....FFFFFF.T...B",
      ".....FFFF..T...B",
      "...GGGGGGG.T...B",
      "..GGGGGGGSST...B",
      "..GGGGGGGG.T...B",
      "...GGGGGGG.T...B",
      "....GGGGGG.T...B",
      "....LL..LL.T..B.",
      "....LL..LL.TBB..",
      "...KK....KK.....",
      "................"
    ],

    # Rồng: đầu hướng phải có sừng, cánh xoè hẳn sang trái với gân cánh màu V,
    # thân dưới bên phải, đuôi gai vắt xuống góc trái
    dragon: [
      "..............H.",
      "...WW........HH.",
      "..WWVW.....DDDD.",
      ".WWWVWW...DDEDDD",
      "WWWVWWWW..DDDDDD",
      "WWVWWWWWW.DDMM..",
      ".WWWWVWWWDDD....",
      "..WWVWWWDDDD....",
      "...WWWWDDDDD....",
      "....DDDDDDDDD...",
      "...DDDDDDDDDDD..",
      "..TDDDDDDDDDD...",
      ".TTDDDDDDDDD....",
      "TT.DDD...DDD....",
      "...CC.....CC....",
      "................"
    ],

    # Dơi — quái bay quen mặt trong hang động JRPG
    bat: [
      "................",
      "................",
      "................",
      "................",
      "..W....BB....W..",
      ".WWW..BBBB..WWW.",
      "WWWWW.EBBE.WWWWW",
      "WWWWWWBBBBWWWWWW",
      ".WWWWWBBBBWWWWW.",
      "..WWW.BBBB.WWW..",
      ".......BB.......",
      "................",
      "................",
      "................",
      "................",
      "................"
    ],

    # Hồn ma — quái lơ lửng, đuôi lượn ba múi
    ghost: [
      "................",
      "....GGGGGGGG....",
      "...GGGGGGGGGG...",
      "..GGGGGGGGGGGG..",
      "..GGEEGGGGEEGG..",
      "..GGEEGGGGEEGG..",
      "..GGGGGGGGGGGG..",
      "..GGGGGMMGGGGG..",
      "..GGGGGGGGGGGG..",
      "..GGGGGGGGGGGG..",
      "..GGGGGGGGGGGG..",
      "..GGGGGGGGGGGG..",
      "..GGGGGGGGGGGG..",
      "..GG..GGGG..GG..",
      "................",
      "................"
    ],

    # Quái mắt: mắt khổng lồ có xúc tu — đại diện Spec Detective (soi chỗ mơ hồ)
    eye: [
      "................",
      ".....SSSSSS.....",
      "...SSSSSSSSSS...",
      "..SSWWWWWWWWSS..",
      ".SSWWWWWWWWWWSS.",
      ".SWWWWIIIIWWWWS.",
      "SSWWWIIIIIIWWWSS",
      "SSWWWIIHIIIWWWSS",
      ".SWWWWIIIIWWWWS.",
      ".SSWWWWWWWWWWSS.",
      "..SSWWWWWWWWSS..",
      "...SSSSSSSSSS...",
      ".....SSSSSS.....",
      "....T..TT..T....",
      "...T...TT...T...",
      "................"
    ],

    # Rương quái: rương báu mọc mắt và răng — đại diện Estimate Poker
    # (cái trông như phần thưởng dễ ước lượng, mở ra mới biết)
    mimic: [
      "................",
      "..WWWWWWWWWWWW..",
      ".WWWWWWWWWWWWWW.",
      ".WEEWWWWWWWWEEW.",
      ".WEEWWWWWWWWEEW.",
      ".WWWWWWWWWWWWWW.",
      ".KMMKKMMKKMMKKK.",
      ".KKKKKKKKKKKKKK.",
      ".KKMMKKMMKKMMKK.",
      ".WWWWWWWWWWWWWW.",
      ".WBBBBBBBBBBBBW.",
      ".WBBBBBCCBBBBBW.",
      ".WBBBBBCCBBBBBW.",
      ".WBBBBBBBBBBBBW.",
      ".WWWWWWWWWWWWWW.",
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
    knight: {
      "P" => "var(--brick)",         # chùm lông trên mũ
      "A" => "#b9c6db",              # giáp, mặt sáng
      "D" => "#7d8ca4",              # giáp, đường viền và mặt tối
      "E" => "var(--ink)",           # khe mắt
      "G" => "var(--coin)",          # nẹp vàng và chắn tay kiếm
      "W" => "var(--sea)",           # mặt khiên
      "V" => "var(--sea-dark)",      # viền khiên
      "S" => "#f2f6ff",              # lưỡi kiếm
      "H" => "#7a4a24"               # cán kiếm
    },
    archer: {
      "H" => "var(--grass-deep)",    # mũ trùm
      "F" => "#ffd8a8",              # da
      "E" => "var(--ink)",           # mắt
      "G" => "var(--grass-dark)",    # áo
      "L" => "#7a4a24",              # quần da
      "K" => "#5b3a1c",              # giày
      "B" => "#a06a30",              # cánh cung
      "T" => "#f4f1e4",              # dây cung
      "S" => "#eef4ff"               # mũi tên
    },
    dragon: {
      "D" => "var(--brick)",         # thân
      "W" => "var(--brick-dark)",    # màng cánh
      "V" => "var(--flame)",         # gân cánh
      "T" => "var(--brick-dark)",    # gai đuôi
      "E" => "var(--coin)",          # mắt
      "M" => "#fff8ee",              # nanh
      "H" => "#f4f1e4",              # sừng
      "C" => "var(--coin-dark)"      # vuốt
    },
    bat: {
      "W" => "var(--berry-dark)",    # cánh
      "B" => "var(--berry)",         # thân
      "E" => "var(--coin)"           # mắt
    },
    ghost: {
      "G" => "#e8ecff",
      "E" => "var(--ink)",           # mắt
      "M" => "var(--ink)"            # miệng
    },
    eye: {
      "S" => "var(--berry-dark)",     # da quanh mắt
      "W" => "#f2f6ff",               # lòng trắng
      "I" => "var(--ink)",            # con ngươi
      "H" => "#ffffff",               # điểm sáng
      "T" => "var(--berry)"           # xúc tu
    },
    mimic: {
      "W" => "#8a5a2b",               # khung gỗ
      "B" => "var(--coin)",           # thân vàng
      "C" => "#8a5a2b",               # ổ khoá
      "K" => "var(--ink)",            # trong miệng
      "M" => "#fff8ee",               # răng
      "E" => "var(--brick)"           # mắt
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
    "spec_detective" => :eye,
    "incident_escape_room" => :dragon,
    "estimate_poker" => :mimic,
    "prod_roulette" => :skull
  }.freeze

  LABELS = {
    hero: "Nhân vật phiêu lưu",
    slime: "Quái slime",
    mage: "Pháp sư",
    knight: "Hiệp sĩ",
    archer: "Cung thủ",
    dragon: "Rồng",
    bat: "Dơi",
    ghost: "Hồn ma",
    eye: "Quái mắt",
    mimic: "Rương quái",
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
    [ :bush,     "l1", "sway",  46 ],
    [ :knight,   "l2", "bob",   42 ],
    [ :coin,     "l3", "flip",  30 ],
    [ :slime,    "l4", "bob",   40 ],
    [ :bat,      "l5", "float", 36 ],
    [ :mushroom, "l6", "sway",  34 ],
    [ :flower,   "r1", "sway",  32 ],
    [ :archer,   "r2", "bob",   42 ],
    [ :sword,    "r3", "bob",   38 ],
    [ :dragon,   "r4", "bob",   46 ],
    [ :ghost,    "r5", "float", 36 ],
    [ :potion,   "r6", "bob",   34 ]
  ].freeze

  # Đội hình người chơi ở dải trận đánh cuối trang chọn màn (games/index): ba nhân vật
  # đứng cùng phía, đối diện là con rồng làm boss. Bề rộng ở đây là giá trị cho màn hình
  # rộng — dưới 560px, `.party .sprite` bên CSS ghi đè lại cho vừa khung.
  PARTY = [
    [ :knight, 56 ],
    [ :mage,   54 ],
    [ :archer, 56 ]
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

  # Hình đại diện người chơi. Tên đi từ cột users.avatar nên phải qua Avatar.resolve:
  # bản ghi cũ có thể trỏ sprite đã đổi tên, và một KeyError ở đây sẽ hạ cả bảng xếp hạng.
  def avatar_sprite(name, size: 40, css_class: nil)
    pixel_sprite(Avatar.resolve(name), size: size, css_class: css_class)
  end

  def sprite_label(name)
    LABELS.fetch(name.to_sym, "nhân vật")
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

  # Ba nhân vật của đội hình. Cả dải trận đánh mang aria-hidden ở view nên aria-label
  # của từng sprite không đọc lên cho screen reader.
  def party_sprites
    safe_join(
      PARTY.map do |name, size|
        pixel_sprite(name, size: size, css_class: "party__member sprite--bounce")
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
