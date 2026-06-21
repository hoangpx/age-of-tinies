extends Node2D
# Tiny Swords — Godot 4.6, dựng bằng CODE.
# Đảo tự nhiên + autotile cỏ + foam + CAO NGUYÊN (color3: cỏ cao + vách đá + lip + dốc) + lính 2 phe TỰ ĐÁNH.
# HeightMap (level/walkable/ramp) cho pathfinding 8 hướng; Y-sort theo chân.

const ART := "res://art/"
const PPU := 64
const SEED := 20260617
const _CAPTURE := false   # bật để tự chụp res://shot.png rồi thoát (debug)

var rng := RandomNumberGenerator.new()
var _cam: Camera2D               # camera fit động theo đảo (chừa lề nước)
var _selected: Array = []        # các lính đang được chọn (viền trắng) — hỗ trợ chọn nhiều
var _last_sel_ms := 0            # thời điểm click lính lần trước (phát hiện double-click cảm ứng)
var _last_sel_f: Fighter = null  # lính click lần trước
var _dn: DebugNumbers            # overlay số tile (ẩn/hiện bằng nút Debug)
var _show_debug := false         # số tile (trong menu Debug)
var _show_fps := true            # FPS label (mặc định BẬT)
var _fog_dim_on := true          # SƯƠNG MÙ — BẬT mặc định (đế chế)
var _fog_black_on := true        # BÓNG ĐEN — BẬT mặc định
var _foam_on := true             # bật/tắt SÓNG/foam (để soi FPS)
var _kb := 1.0                   # hệ số lớp ĐEN (0 nếu tắt bóng đen)
var _kd := FOG_DIM               # hệ số lớp MỜ (0 nếu tắt sương mù)
var _fps_label: Label            # hiển thị FPS
var _menu: Control               # bảng Debug (các toggle)
var _res := {"Wood": 0, "Gold": 0, "Meat": 0}   # 3 loại resource
var _res_labels := {}            # "Wood"/"Gold"/"Meat" -> Label trên HUD
var _unit_cap := 10              # sức chứa unit (mỗi nhà dân +5, tối đa 50)
var _unit_label: Label           # HUD: số unit / cap
# ===== AI quân ĐỎ + trạng thái trận =====
var _ai_res := {"Wood": 10, "Gold": 0, "Meat": 10}   # kho resource của AI
var _ai_t := 0.0                 # nhịp suy nghĩ AI
var _ai_train_t := 3.0           # đếm lùi tới lượt huấn luyện lính kế tiếp
var _ai_income_t := 5.0          # đếm lùi tới đợt +1 gỗ +1 thịt (mỗi 5s)
var _ai_tgt := {}                # instance_id lính đỏ -> mục tiêu hiện tại (tránh ra lệnh lặp gây giật)
var _ai_pawn_tool := {}          # instance_id nông dân đỏ -> "nghề" cố định (Axe/Pickaxe/Knife) để chia đều 3 loại
var _ai_chase_t := {}            # id lính đỏ -> mốc giờ (ms) bắt đầu đuổi 1 dân/lính
var _ai_nochase_until := {}      # id lính đỏ -> tới khi nào thì THÔI đuổi (đã bỏ vì đuổi lâu) → đánh nhà
var _match_over := false         # trận đã kết thúc (thắng/thua) → dừng AI, tắt fog
var _match_t := 0.0              # thời gian trận (giây) — hiện cạnh nút Settings
var _time_label: Label
var _world: Node2D               # node chứa lính + công trình (để add khi xây)
var _build_panel: Control        # bảng nút XÂY (hiện khi chọn nông dân)
var _lose_label: Label
var _castle_placed := false
# ----- âm thanh + cài đặt -----
var _music: AudioStreamPlayer
var _music_start_ms := 0
var _music_vol := 1.0   # âm lượng nhạc (0..1, người dùng chỉnh) — áp THẲNG lên player, KHÔNG dùng bus phụ (bus runtime phá audio web)
var _sfx_vol := 1.0     # âm lượng sfx  (0..1)
var _settings_panel: Control
var _modal_dim: ColorRect        # nền mờ phủ toàn màn hình khi mở Settings (che mọi banner)
var _info_btn: Button            # nút info (góc dưới-phải) — hiện khi mở Settings
var _credits_panel: Control      # tờ giấy credit asset
# Công trình xây được (TRỪ Castle). Giá = GỖ. sheet=tên file (house chọn random sau).
const BUILD_INFO := {
	"house":    {"label": "House", "cost": 10, "w": 128, "h": 192, "hp": 100, "time": 20.0},
	"barracks": {"label": "Barracks", "cost": 30, "sheet": "Barracks", "w": 192, "h": 256, "hp": 300, "time": 50.0},
	"archer":   {"label": "Archery", "cost": 30, "sheet": "Archery", "w": 192, "h": 256, "hp": 300, "time": 50.0},
	"monk":     {"label": "Monastery", "cost": 40, "sheet": "Monastery", "w": 192, "h": 320, "hp": 300, "time": 50.0},
	"tower":    {"label": "Tower", "cost": 30, "sheet": "Tower", "w": 128, "h": 256, "hp": 200, "time": 30.0},
	"castle":   {"label": "Castle", "cost": 0, "sheet": "Castle", "w": 320, "h": 256, "hp": 1000, "time": 1.0},
}
# Sản xuất unit (click nhà → menu mua). Giá theo resource, thời gian giây.
const UNIT_INFO := {
	"Pawn":    {"label": "Pawn", "cost": {"Meat": 5}, "time": 10.0, "avatar": "Avatars_05"},
	"Warrior": {"label": "Warrior", "cost": {"Gold": 5, "Meat": 10}, "time": 20.0, "avatar": "Avatars_01"},
	"Lancer":  {"label": "Lancer", "cost": {"Gold": 10, "Meat": 10}, "time": 20.0, "avatar": "Avatars_02"},
	"Archer":  {"label": "Archer", "cost": {"Meat": 10, "Wood": 10}, "time": 20.0, "avatar": "Avatars_03"},
	"Monk":    {"label": "Monk", "cost": {"Wood": 10, "Gold": 10, "Meat": 10}, "time": 20.0, "avatar": "Avatars_04"},
}
const PROD_BY_BUILDING := {"house": ["Pawn"], "castle": ["Pawn"], "barracks": ["Warrior", "Lancer"], "archer": ["Archer"], "monk": ["Monk"], "tower": []}
const RES_VN := {"Wood": "Wood", "Gold": "Gold", "Meat": "Meat"}
var _prod_panel: Control
var _prod_hb: HBoxContainer
var _prod_bg: NinePatchRect       # nền banner sản xuất (co giãn theo số slot)
var _sel_building = null          # nhà đang chọn (xem menu sản xuất)
var _prod_cards := {}            # kind -> {count: Label, bar: ProgressBar}
var _build_mode := ""            # đang đặt loại nhà nào ("" = ko)
var _build_x := {}               # type -> nút X ở góc slot (chỉ hiện ở nhà đang chọn xây)
var _ghost: Sprite2D             # nhà mờ xem trước khi đặt
var _msg_label: Label            # thông báo giữa màn (ko đủ gỗ / chọn vị trí…)
var _msg_t := 0.0
var _foam_root: Node2D           # gốc foam (để ẩn/hiện)
var _shadow_root: Node2D         # gốc bóng đổ (để ẩn/hiện)
var _gen: Node2D                 # node cha chứa TOÀN BỘ map hiện tại — free để gen map mới
var _gen_count := 0              # đếm số lần gen → seed khác nhau mỗi lần bấm

# ----- SƯƠNG MÙ (fog of war) kiểu đế chế -----
const SIGHT := 9.0               # bán kính NHÌN của lính (ô) — rộng hơn
const HOUSE_SIGHT := 7.0         # bán kính LUÔN SÁNG quanh nhà (ô)
const FOG_DIM := 0.55            # alpha vùng ĐÃ khám phá nhưng ko thấy (sương mù mờ)
const FOG_SUB := 1               # độ phân giải fog = 1 điểm / ô (nhẹ nhất; mịn nhờ lọc tuyến tính)
var _fog: Sprite2D               # overlay đen phủ map
var _fog_img: Image
var _fog_tex: ImageTexture
var _seenf: PackedFloat32Array   # độ ĐÃ-khám-phá mỗi điểm (0..1, mép MỀM) — tồn tại cả ván
var _vis: PackedFloat32Array     # độ sáng ĐANG thấy mỗi frame (0..1, mép mềm)
const LIT_THRESH := 0.4          # _vis ≥ ngưỡng này = "đang trong vùng sáng" (hiện quân địch/cừu)
var _fogbytes: PackedByteArray   # buffer RGBA tồn tại (chỉ sửa vùng sáng → ko quét cả mảng)
var _lit_idx: PackedInt32Array   # các điểm SÁNG frame này (để frame sau trả về mờ)
var _prev_lit: PackedInt32Array  # các điểm sáng frame TRƯỚC
var _brush_cache := {}           # sd -> brush template (tính 1 lần, hình méo cố định → blit lại nhanh)
var _perm: PackedByteArray       # điểm SÁNG vĩnh viễn (quanh NHÀ — bake 1 lần, ko stamp lại mỗi frame)
var _last_sig := 9999999         # chữ ký ô của quân XANH → ko ai đổi ô thì BỎ QUA cập nhật fog (đứng yên = miễn phí)
var _fox0 := 0; var _foy0 := 0   # góc lưới fog (ô)
var _fpw := 1; var _fph := 1     # kích thước fog (điểm sub)
var _fog_t := 0.0                # nhịp cập nhật fog
var _cull_t := 0.0               # nhịp cull theo khung nhìn

# ----- ĐIỀU KHIỂN CAMERA (pan/zoom 2 ngón) -----
const VIEW_CELLS := 14.0         # số ô CAO nhìn thấy lúc đầu (view nhỏ → zoom vào)
var _touches := {}               # index ngón -> vị trí (touch); ≥2 ngón = pan/zoom
var _zoom_min := 0.15; var _zoom_max := 2.5
var _pan_drag := false           # desktop: giữ chuột GIỮA kéo để pan
var _pinch_dist := -1.0          # khoảng cách 2 ngón lần trước (pinch zoom)
var _using_touch := false        # đang dùng cảm ứng → bỏ qua chuột giả lập, xử lệnh ở lúc NHẢ ngón
var _multi := false              # cử chỉ hiện tại đã từng có ≥2 ngón (pan/zoom) → KO coi là tap lệnh
var _tap_moved := false          # ngón đã kéo đi (swipe) → KO coi là tap lệnh
var land := {}          # Vector2i -> true
var plateau := {}       # Vector2i -> true (ô thuộc cao nguyên/vách — né cây/lính)
var hmap := TSHeight.new()
var _dbg: Array = []     # debug: nhãn PHỤ (back-rock "[..]" ở đỉnh ô)
var _cells := {}         # debug: nhãn CHÍNH theo ô (Vector2i -> {idx,c,s}) — ghi đè, chỉ giữ tile CUỐI → ko chồng số

func dbg(cell: Vector2i, idx: int, col: Color, sz: int) -> void:
	_cells[cell] = {"idx": idx, "c": col, "s": sz}   # last-write-wins: mỗi ô 1 số (tile đang hiện)

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.16, 0.44, 0.62))

	_cam = Camera2D.new()
	add_child(_cam); _cam.make_current()   # zoom/vị trí set động trong build_map (fit đảo + chừa nước)

	_setup_audio()
	_setup_sfx()
	_build_ui()
	build_map()

# Bus Music/SFX lấy từ default_bus_layout.tres (KHÔNG add_bus runtime — runtime add_bus PHÁ audio web!).
func _setup_audio() -> void:
	_music = AudioStreamPlayer.new()
	_music.stream = load("res://audio/bg.wav")
	_music.bus = "Master"
	_music.autoplay = true
	add_child(_music)
	_music.finished.connect(func(): if _music != null: _music_start_ms = Time.get_ticks_msec(); _music.play())   # lặp
	_load_volumes()   # nhớ âm lượng lần trước
	_music_start_ms = Time.get_ticks_msec()
	_music.play()

# ---- ÂM THANH game (SFX): mỗi loại 1..n biến thể, phát random; bỏ qua nếu quá xa camera ----
var _sfx := {}                # category -> Array[AudioStream]
var _sfx_players: Array = []  # pool player (xoay vòng)
var _sfx_idx := 0

func _setup_sfx() -> void:
	var groups := {
		"sword": ["sword_1", "sword_2"], "spear": ["spear_1", "spear_2"],
		"bow": ["bow_1"], "arrow_hit": ["arrow_hit_1"],
		"axe": ["axe_1"], "pickaxe": ["pickaxe_1"], "meat": ["meat_1"],
		"hammer": ["hammer_1", "hammer_2"], "build_done": ["build_done_1"],
		"explode": ["explode_1"], "fire": ["fire_1"], "spawn": ["spawn_1"],
		"death": ["death_1"], "coin": ["coin_1"], "click": ["click_1"], "sheep": ["sheep_1"],
		"victory": ["victory_1", "victory_2", "victory_3", "victory_4"],
		"defeat": ["defeat_1", "defeat_2", "defeat_3", "defeat_4"],
	}
	for cat in groups:
		var arr: Array = []
		for fn in groups[cat]:
			var s = load("res://audio/sfx/%s.wav" % fn)
			if s != null: arr.append(s)
		_sfx[cat] = arr
	for i in range(16):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"; p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p); _sfx_players.append(p)

var _sfx_t := {}              # cat -> mốc giờ (ms) phát gần nhất → giãn nhịp, đỡ chói
const SFX_GAP := 110          # ms tối thiểu giữa 2 lần CÙNG loại (mặc định)
const SFX_GAP_CAT := {"meat": 450, "axe": 200, "pickaxe": 200, "hammer": 200}   # loại lặp nhiều → giãn thêm
const SFX_VOL := {"meat": -14.0, "axe": -4.0, "pickaxe": -4.0, "hammer": -4.0}   # nhỏ tiếng chói

# Phát 1 sfx (random biến thể). pos != null & NGOÀI màn hình → bỏ; cùng loại quá dồn → bỏ.
func play_sfx(cat: String, pos = null, vol_db := 0.0) -> void:
	var arr: Array = _sfx.get(cat, [])
	if arr.is_empty(): return
	if pos != null and _cam != null:                       # CHỈ kêu nếu vật đang TRÊN màn hình
		var half: Vector2 = get_viewport().get_visible_rect().size * 0.5 / _cam.zoom.x
		var d: Vector2 = (pos as Vector2) - _cam.position
		if absf(d.x) > half.x or absf(d.y) > half.y: return
	var now: int = Time.get_ticks_msec()
	if now - int(_sfx_t.get(cat, -99999)) < int(SFX_GAP_CAT.get(cat, SFX_GAP)): return   # giãn nhịp từng loại
	_sfx_t[cat] = now
	var p: AudioStreamPlayer = _sfx_players[_sfx_idx]
	_sfx_idx = (_sfx_idx + 1) % _sfx_players.size()
	p.stream = arr[randi() % arr.size()]
	p.volume_db = vol_db + float(SFX_VOL.get(cat, 0.0)) + linear_to_db(maxf(_sfx_vol, 0.0001))   # áp âm lượng user thẳng lên player
	p.play()

const SETTINGS_PATH := "user://settings.cfg"

func _load_volumes() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		_music_vol = clampf(cfg.get_value("audio", "music", 1.0), 0.0, 1.0)
		_sfx_vol = clampf(cfg.get_value("audio", "sfx", 1.0), 0.0, 1.0)

func _save_volumes() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", _music_vol)
	cfg.set_value("audio", "sfx", _sfx_vol)
	cfg.save(SETTINGS_PATH)

# Fit camera để THẤY HẾT đảo + chừa lề nước quanh (đảo ko chạm viền màn hình).
func _fit_camera() -> void:
	var minx := 9999; var maxx := -9999; var miny := 9999; var maxy := -9999
	for c in land.keys():
		minx = min(minx, c.x); maxx = max(maxx, c.x); miny = min(miny, c.y); maxy = max(maxy, c.y)
	for c in _coast_rock.keys():
		minx = min(minx, c.x); maxx = max(maxx, c.x); miny = min(miny, c.y); maxy = max(maxy, c.y)
	var m := 2   # lề: 2 ô nước quanh đảo (≥1 ô nước thấy rõ + foam)
	var x0 := minx - m; var x1 := maxx + m; var y0 := miny - m; var y1 := maxy + m
	var cw := float((x1 - x0 + 1) * PPU); var ch := float((y1 - y0 + 1) * PPU)
	var vp := get_viewport().get_visible_rect().size
	var z: float = min(vp.x / cw, vp.y / ch)
	_cam.zoom = Vector2(z, z)
	_cam.position = Vector2((x0 + x1 + 1) * 0.5 * PPU, (y0 + y1 + 1) * 0.5 * PPU)

# ---------- camera view nhỏ + pan/zoom 2 ngón ----------
# View NHỎ lúc đầu, căn vào trung bình vị trí quân XANH.
func _init_camera(_world: Node2D) -> void:
	var sum := Vector2.ZERO; var n := 0
	for f in get_tree().get_nodes_in_group("fighter"):
		if is_instance_valid(f) and f.team == 0:
			sum += f.position; n += 1
	var center: Vector2 = (sum / n) if n > 0 else Vector2.ZERO
	var vp := get_viewport().get_visible_rect().size
	var z: float = vp.y / (VIEW_CELLS * PPU)
	_zoom_min = z * 0.4    # cho zoom OUT (xem rộng hơn)
	_zoom_max = z * 2.5    # và zoom IN
	_cam.zoom = Vector2(z, z)
	_cam.position = center

func _set_zoom(z: float) -> void:
	z = clampf(z, _zoom_min, _zoom_max)
	_cam.zoom = Vector2(z, z)

# Cảm ứng: 1 ngón TAP (nhả ra, ko kéo) = lệnh lính; ≥2 ngón = PAN (kéo) + ZOOM (chụm/xòe).
# Lệnh chỉ phát khi NHẢ ngón cuối & cử chỉ ko hề có ngón thứ 2 & ko kéo → 2 tay zoom/pan KO bị hiểu là lệnh.
func _handle_touch(event: InputEvent) -> void:
	_using_touch = true
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() >= 2: _multi = true     # đã có 2 ngón → cử chỉ này là pan/zoom
		else:
			_touches.erase(event.index)
			if _touches.size() < 2: _pinch_dist = -1.0
			if _touches.is_empty():                     # NHẢ ngón cuối → kết thúc cử chỉ
				if not _multi and not _tap_moved:        # 1 ngón, ko kéo → TAP lệnh
					_handle_tap(get_global_mouse_position(), false)
				_multi = false; _tap_moved = false
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if event.relative.length() > 12.0: _tap_moved = true   # kéo > ngưỡng → swipe, ko phải tap
		if _touches.size() >= 2:
			_multi = true
			var ks := _touches.keys()
			var a: Vector2 = _touches[ks[0]]; var b: Vector2 = _touches[ks[1]]
			var d: float = a.distance_to(b)
			if _pinch_dist > 0.0:
				_set_zoom(_cam.zoom.x * (d / _pinch_dist))   # xòe ra → zoom in
			_pinch_dist = d
			_cam.position -= event.relative / _cam.zoom.x    # kéo map theo ngón

# ===== SƯƠNG MÙ (fog of war) — phân giải sub + brush mép MỀM =====
func _setup_fog(x0: int, y0: int, w: int, h: int) -> void:
	_fox0 = x0; _foy0 = y0
	_fpw = w * FOG_SUB; _fph = h * FOG_SUB; _fog_t = 0.0
	var n := _fpw * _fph
	_seenf = PackedFloat32Array(); _seenf.resize(n)       # 0 = chưa khám phá
	_vis = PackedFloat32Array(); _vis.resize(n)
	_lit_idx = PackedInt32Array(); _prev_lit = PackedInt32Array(); _brush_cache = {}
	_perm = PackedByteArray(); _perm.resize(n); _last_sig = 9999999
	_fogbytes = PackedByteArray(); _fogbytes.resize(n * 4)
	var ua := int(_kb * 255.0)                             # alpha vùng chưa khám phá (tùy toggle bóng đen)
	for i in range(n): _fogbytes[i * 4 + 3] = ua           # mặc định: ĐEN ĐẶC; chỉ sửa vùng sáng sau
	_fog_img = Image.create(_fpw, _fph, false, Image.FORMAT_RGBA8)
	_fog_tex = ImageTexture.create_from_image(_fog_img)
	_fog = Sprite2D.new()
	_fog.texture = _fog_tex
	_fog.centered = false
	_fog.position = Vector2(x0 * PPU, y0 * PPU)
	_fog.scale = Vector2(float(PPU) / FOG_SUB, float(PPU) / FOG_SUB)   # mỗi điểm sub = PPU/SUB px
	_fog.z_index = 1000
	_fog.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR    # nội suy → mép sương mịn
	_gen.add_child(_fog)
	# BAKE NHÀ 1 lần: vùng quanh nhà CỦA MÌNH (team 0) luôn sáng (căn cứ địch giữ nguyên bóng đêm)
	for r in get_tree().get_nodes_in_group("building"):
		if is_instance_valid(r) and r.team == 0:
			_stamp(r.global_position, HOUSE_SIGHT, int(r.get_instance_id()), true)
	_update_fog()

# Nhà MÌNH xây xong → bake vùng sáng vĩnh viễn quanh nó (gọi từ Building khi built).
func bake_light(pos: Vector2) -> void:
	if _fog == null or not is_instance_valid(_fog): return
	_stamp(pos, HOUSE_SIGHT, int(pos.x) * 13 + int(pos.y) * 7, true)
	_fog_img.set_data(_fpw, _fph, false, Image.FORMAT_RGBA8, _fogbytes)
	_fog_tex.update(_fog_img)

# Vẽ 1 "vệt sáng" gần-tròn MỀM (méo ngẫu nhiên theo góc nhưng vẫn khuôn tròn) vào _vis + _seenf.
# sd = seed ổn định theo nguồn (instance id) → hình méo cố định, ko rung khi cập nhật.
# Tính 1 LẦN brush méo của nguồn sd (hình cố định) → cache. Frame sau chỉ BLIT lại (ko sqrt/trig).
func _get_brush(sd: int, rad_cells: float) -> Dictionary:
	if _brush_cache.has(sd): return _brush_cache[sd]
	var r := rad_cells * FOG_SUB
	var hw := int(ceil(r * 1.3))
	var p1 := float(sd % 628) / 100.0; var p2 := float((sd * 3) % 628) / 100.0
	var cp1 := cos(p1); var sp1 := sin(p1); var cp2 := cos(p2); var sp2 := sin(p2)
	var a1 := 0.16; var a2 := 0.10
	var size := 2 * hw + 1
	var vals := PackedFloat32Array(); vals.resize(size * size)
	for dy in range(-hw, hw + 1):
		for dx in range(-hw, hw + 1):
			var dist := sqrt(float(dx * dx + dy * dy))
			var v := 0.0
			if dist < 0.001:
				v = 1.0
			else:
				var c := dx / dist; var s := dy / dist
				var s2 := 2.0 * s * c; var c2 := c * c - s * s
				var s3 := s * (3.0 - 4.0 * s * s); var c3 := c * (4.0 * c * c - 3.0)
				var wob := 1.0 + a1 * (s2 * cp1 + c2 * sp1) + a2 * (s3 * cp2 + c3 * sp2)
				var dd := dist / (r * wob)
				if dd < 1.0: v = 1.0 - smoothstep(0.5, 1.0, dd)
			vals[(dy + hw) * size + (dx + hw)] = v
	var b := {"hw": hw, "size": size, "vals": vals}
	_brush_cache[sd] = b
	return b

func _stamp(wpos: Vector2, rad_cells: float, sd: int, perm := false) -> void:
	var b := _get_brush(sd, rad_cells)
	var hw: int = b["hw"]; var size: int = b["size"]
	var vals: PackedFloat32Array = b["vals"]
	var fxi := int(round((wpos.x / PPU - _fox0) * FOG_SUB))
	var fyi := int(round((wpos.y / PPU - _foy0) * FOG_SUB))
	for dy in range(-hw, hw + 1):
		var py := fyi + dy
		if py < 0 or py >= _fph: continue
		var rowt := (dy + hw) * size
		var rowf := py * _fpw
		for dx in range(-hw, hw + 1):
			var v: float = vals[rowt + dx + hw]
			if v <= 0.0: continue
			var px := fxi + dx
			if px < 0 or px >= _fpw: continue
			var idx := rowf + px
			if v > _vis[idx]:
				var was: float = _vis[idx]
				_vis[idx] = v
				if v > _seenf[idx]: _seenf[idx] = v
				var sn: float = _seenf[idx]
				_fogbytes[idx * 4 + 3] = int(((1.0 - sn) * _kb + sn * _kd) * (1.0 - v) * 255.0)
				if perm: _perm[idx] = 1                       # NHÀ: sáng vĩnh viễn, ko reset
				elif was == 0.0 and _perm[idx] == 0: _lit_idx.append(idx)

# Chữ ký vị trí Ô của quân XANH → đổi mới cập nhật fog (đứng yên = bỏ qua, miễn phí).
func _unit_sig() -> int:
	var sig := 0
	for f in get_tree().get_nodes_in_group("fighter"):
		if is_instance_valid(f) and f.team == 0 and not f.is_dead():
			var c := hmap.cell_of(f.position)
			sig = sig * 131071 + c.x * 8191 + c.y
	return sig

func _update_fog() -> void:
	if _fog == null or not is_instance_valid(_fog): return
	var sig := _unit_sig()
	if sig == _last_sig: return        # KHÔNG quân nào đổi ô → fog y nguyên → bỏ qua (hết spike khi đứng yên)
	_last_sig = sig
	# 1) trả vùng SÁNG frame trước về MỜ (chỉ đụng các điểm đó, ko quét cả mảng)
	for idx in _prev_lit:
		_vis[idx] = 0.0
		var sn: float = _seenf[idx]
		_fogbytes[idx * 4 + 3] = int(((1.0 - sn) * _kb + sn * _kd) * 255.0)
	_lit_idx.clear()
	# 2) vén sương quanh quân XANH (NHÀ đã bake sẵn 1 lần, ko cần stamp lại)
	for f in get_tree().get_nodes_in_group("fighter"):
		if is_instance_valid(f) and f.team == 0 and not f.is_dead():
			_stamp(f.position, SIGHT, int(f.get_instance_id()))
	_prev_lit = _lit_idx.duplicate()
	_fog_img.set_data(_fpw, _fph, false, Image.FORMAT_RGBA8, _fogbytes)
	_fog_tex.update(_fog_img)
	_hide_in_fog()

# Khung nhìn camera (world) + lề, để cull ngoài màn.
func _view_rect() -> Rect2:
	var vp := get_viewport().get_visible_rect().size
	var half: Vector2 = vp * 0.5 / _cam.zoom.x
	var m := 140.0   # lề rộng (cây cao) → ko bị pop ở mép
	return Rect2(_cam.position - half - Vector2(m, m), half * 2.0 + Vector2(m * 2.0, m * 2.0))

# CHỈ "gen" vật trong KHUNG NHÌN: ngoài màn → ẩn+dừng. Trong màn: theo sương (đen=ẩn, sương=đóng băng, sáng=chạy).
func _cull_view() -> void:
	var vr := _view_rect()
	var fog: bool = _fog_active()
	for s in get_tree().get_nodes_in_group("fog_anim"):
		if not is_instance_valid(s): continue
		var p: Vector2 = s.global_position
		if not vr.has_point(p):                      # NGOÀI khung nhìn → ẩn + TẮT XỬ LÝ hẳn (ko tốn CPU)
			_set_decor(s, false, false)
		elif fog and _seen_at(p) <= 0.01:            # CHƯA thấy (đen) → ẩn + tắt xử lý
			_set_decor(s, false, false)
		elif fog and _lit_at(p) < LIT_THRESH:        # sương (đã thấy, ko sáng) → hiện TĨNH (tắt anim)
			_set_decor(s, true, false)
		else:                                        # trong màn + sáng (hoặc tắt fog) → chạy anim
			_set_decor(s, true, true)

# Bật/tắt 1 decor: vis = hiện?, anim = chạy animation?. anim=false → PROCESS_MODE_DISABLED (ko advance frame, ko tốn CPU).
func _set_decor(s: Node, vis: bool, anim: bool) -> void:
	if s.visible != vis: s.visible = vis
	if anim:
		if s.process_mode != Node.PROCESS_MODE_INHERIT: s.process_mode = Node.PROCESS_MODE_INHERIT
		if not s.is_playing(): s.play()
	elif s.process_mode != Node.PROCESS_MODE_DISABLED:
		s.process_mode = Node.PROCESS_MODE_DISABLED

# Vật ĐỘNG (quân ĐỊCH, cừu) chỉ hiện khi ĐANG trong vùng sáng; quân mình & vật tĩnh (cây/đá/nhà) luôn hiện.
func _hide_in_fog() -> void:
	var active: bool = _fog_active()
	for f in get_tree().get_nodes_in_group("fighter"):
		if not is_instance_valid(f): continue
		f.visible = (not active) or (f.team == 0) or (_lit_at(f.position) >= LIT_THRESH)
	for b in get_tree().get_nodes_in_group("building"):   # NHÀ ĐỊCH: chỉ hiện khi đang SÁNG (fog → ẩn)
		if not is_instance_valid(b): continue
		b.visible = (not active) or (b.team == 0) or (_lit_at(b.global_position) >= LIT_THRESH)
	for r in get_tree().get_nodes_in_group("resource"):
		if is_instance_valid(r) and str(r.get_meta("tool", "")) == "Knife":   # CỪU (động)
			r.visible = (not active) or (_lit_at(r.global_position) >= LIT_THRESH)

func _lit_at(wpos: Vector2) -> float:
	var fx := int(round((wpos.x / PPU - _fox0) * FOG_SUB))
	var fy := int(round((wpos.y / PPU - _foy0) * FOG_SUB))
	if fx < 0 or fy < 0 or fx >= _fpw or fy >= _fph: return 0.0
	return _vis[fy * _fpw + fx]

func _seen_at(wpos: Vector2) -> float:
	var fx := int(round((wpos.x / PPU - _fox0) * FOG_SUB))
	var fy := int(round((wpos.y / PPU - _foy0) * FOG_SUB))
	if fx < 0 or fy < 0 or fx >= _fpw or fy >= _fph: return 0.0
	return _seenf[fy * _fpw + fx]

# ---------- điều khiển lính ----------
func _unhandled_input(event: InputEvent) -> void:
	# --- CAMERA: cảm ứng 2 ngón (pan + pinch zoom) ---
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_handle_touch(event)
		return
	# --- CAMERA desktop: lăn chuột = zoom, giữ chuột GIỮA kéo = pan ---
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_set_zoom(_cam.zoom.x * 1.12); return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_set_zoom(_cam.zoom.x * 0.89); return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_pan_drag = event.pressed; return
	if event is InputEventMouseMotion and _pan_drag:
		_cam.position -= event.relative / _cam.zoom.x; return
	if event is InputEventMouseMotion and _build_mode != "" and _ghost != null:   # ghost theo chuột (desktop)
		var gc := hmap.cell_of(get_global_mouse_position())
		_ghost.position = Vector2(gc.x + 0.5, gc.y + 0.5) * PPU
		_ghost.modulate = Color(0.4, 1.0, 0.4, 0.5) if _can_build(gc) else Color(1.0, 0.3, 0.3, 0.5)
		return
	# --- LỆNH LÍNH (chuột desktop): bỏ qua nếu đang dùng cảm ứng (cảm ứng xử ở lúc nhả ngón) ---
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _using_touch: return
		_handle_tap(get_global_mouse_position(), event.double_click)

# Xử 1 lần TAP/click tại điểm w (dùng chung cho chuột desktop & tap cảm ứng 1 ngón).
func _handle_tap(w: Vector2, dbl_hint: bool) -> void:
	if _match_over: return                   # trận đã kết thúc → khóa thao tác
	# ĐANG ĐẶT NHÀ → chạm chọn vị trí xây
	if _build_mode != "":
		var bc := hmap.cell_of(w)
		if _can_build(bc): _place_building_at(bc)
		else: _show_msg("Can't build here!")
		return
	var f := _fighter_at(w)
	var enemy := _enemy_at(w)
	var have: bool = not _selected.is_empty()
	# 0) DOUBLE-TAP lên quân MÌNH → chọn cả nhóm (xét TRƯỚC, kể cả khi con đó đang được chọn)
	if f != null:
		var now := Time.get_ticks_msec()
		var dbl: bool = dbl_hint or (now - _last_sel_ms < 350 and is_instance_valid(_last_sel_f) and _last_sel_f == f)
		_last_sel_ms = now; _last_sel_f = f
		if dbl:
			_select_group(f); return
		_set_selected(f); return       # tap 1 lính (kể cả con TRONG nhóm) → bỏ nhóm, chọn RIÊNG con đó
	# 1) ĐÃ CHỌN + chạm vùng có ĐỊCH → ưu tiên ĐÁNH (dù đè quân mình) → hết nhầm khi hỗn chiến
	if have and enemy != null:
		for u in _selected:
			if is_instance_valid(u): u.command_attack(enemy)
		_spawn_move_marker(w, "attack")
		return
	# 2) Chạm trúng NHÀ
	var bld := _building_at(w)
	if bld != null:
		if bld.team != 0:                       # nhà ĐỊCH → cả nhóm đánh
			if have:
				for u in _selected:
					if is_instance_valid(u): u.command_attack(bld)
				_spawn_move_marker(w, "attack")
			return
		if dbl_hint:                            # DOUBLE-CLICK → mở menu (kể cả nhà ĐANG XÂY) để Phá dỡ
			_select_building(bld); return
		if bld.btype == "tower" and bld.is_built() and have:   # CHÒI CANH + có cung đang chọn → trèo lên (≤2)
			var archers: Array = []
			for u in _selected:
				if is_instance_valid(u) and u.kind == "Archer": archers.append(u)
			if not archers.is_empty():
				bld.garrison = bld.garrison.filter(func(a): return is_instance_valid(a) and not a.is_dead())
				for a in archers:
					if bld.garrison.size() >= 2: break
					if a in bld.garrison: continue
					bld.garrison.append(a)
					a.command_garrison(bld, bld.garrison_slot(bld.garrison.size() - 1))
				return
		if have and _has_pawn_selected() and bld.needs_work():   # nhà mình cần thợ → xây/sửa
			for u in _selected:
				if is_instance_valid(u) and u.kind == "Pawn": u.command_build(bld)
			return
		_select_building(bld)                   # nhà mình đã xây → menu sản xuất
		return
	# 3) ĐÃ CHỌN → ra lệnh đi / lấy resource (kể cả khi chạm trúng chính quân đã chọn → coi là đi, KO chọn lại)
	if have:
		var res := _resource_at(w)
		if res != null and _has_pawn_selected():
			for u in _selected:
				if is_instance_valid(u) and u.kind == "Pawn": u.command_gather(res)
			_spawn_move_marker(res.global_position, "tool", str(res.get_meta("tool")))
		else:
			_command_move_group(w)                         # cả nhóm đi (đội hình lệch nhau)
			_spawn_move_marker(w)

# Hiệu ứng ra-lệnh-đi (move marker): vẽ bằng code (MoveMarker) — vòng tròn loang + chevron chỉ xuống.
func _spawn_move_marker(p: Vector2, mode := "move", tool := "") -> void:
	var m: Node2D = load("res://MoveMarker.gd").new()
	m.mode = mode
	m.tool = tool
	m.position = p
	m.z_index = 1100   # TRÊN tấm fog (z=1000) → chỉ vào vùng bóng đen vẫn thấy marker
	_gen.add_child(m)

func _resource_at(w: Vector2) -> Node2D:
	var best: Node2D = null; var bd := 1e9
	for r in get_tree().get_nodes_in_group("resource"):
		if not is_instance_valid(r): continue
		var p: Vector2 = r.global_position
		var dx: float = abs(w.x - p.x)
		var dy: float = w.y - p.y                               # thân resource ở TRÊN chân
		if dx < 45.0 and dy < 20.0 and dy > -110.0:
			var d: float = dx + abs(dy + 40.0)
			if d < bd: bd = d; best = r
	return best

func _fighter_at(w: Vector2) -> Fighter:
	var best: Fighter = null; var bd := 1e9
	for f in get_tree().get_nodes_in_group("fighter"):
		if not is_instance_valid(f) or f.team != 0: continue    # chỉ chọn được quân XANH (người chơi)
		var dx: float = abs(w.x - f.position.x)
		var dy: float = w.y - f.position.y                      # thân ở TRÊN chân
		if dx < 30.0 and dy < 12.0 and dy > -78.0:
			var d: float = dx + abs(dy + 33.0)
			if d < bd: bd = d; best = f
	return best

func _construction_at(w: Vector2) -> Node2D:                  # nhà CẦN THỢ (đang xây / hư cần sửa): click trúng hình
	for b in get_tree().get_nodes_in_group("building"):
		if is_instance_valid(b) and b.has_method("needs_work") and b.needs_work() and b.contains_point(w): return b
	return null

func _building_at(w: Vector2) -> Node2D:                      # bất kỳ nhà nào (để chọn → menu sản xuất)
	for b in get_tree().get_nodes_in_group("building"):
		if is_instance_valid(b) and b.contains_point(w): return b
	return null

func _enemy_at(w: Vector2) -> Fighter:                        # tìm lính ĐỊCH (đỏ, team 1) tại điểm click
	var best: Fighter = null; var bd := 1e9
	for f in get_tree().get_nodes_in_group("fighter"):
		if not is_instance_valid(f) or f.team == 0 or f.is_dead(): continue
		var dx: float = abs(w.x - f.position.x)
		var dy: float = w.y - f.position.y                      # thân ở TRÊN chân
		if dx < 30.0 and dy < 12.0 and dy > -78.0:
			var d: float = dx + abs(dy + 33.0)
			if d < bd: bd = d; best = f
	return best

func _clear_selection() -> void:
	for u in _selected:
		if is_instance_valid(u): u.set_selected(false)
	_selected = []
	_update_build_panel()

func _set_selected(f: Fighter) -> void:         # chọn 1 lính
	_clear_selection()
	_selected = [f]
	f.set_selected(true)
	_update_build_panel()

# Double click: chọn HẾT lính CÙNG LOẠI (kind) của mình trong bán kính = khoảng sáng (SIGHT ô) quanh f.
func _select_group(f: Fighter) -> void:
	_clear_selection()
	var r2: float = (SIGHT * PPU) * (SIGHT * PPU)
	for o in get_tree().get_nodes_in_group("fighter"):
		if not is_instance_valid(o) or o.team != 0 or o.is_dead(): continue
		if o.kind != f.kind: continue
		if f.position.distance_squared_to(o.position) <= r2:
			_selected.append(o); o.set_selected(true)
	if _selected.is_empty():                     # phòng hờ (luôn có ít nhất f)
		_selected = [f]; f.set_selected(true)
	_update_build_panel()

func _has_pawn_selected() -> bool:
	for u in _selected:
		if is_instance_valid(u) and u.kind == "Pawn": return true
	return false

# Cả nhóm đi tới quanh điểm w theo ĐỘI HÌNH lưới (lệch nhau ~0.9 ô) để ko dồn 1 chỗ.
func _command_move_group(w: Vector2) -> void:
	var units: Array = []
	for u in _selected:
		if is_instance_valid(u): units.append(u)
	if units.is_empty(): return
	var cols: int = int(ceil(sqrt(float(units.size()))))
	var rows: int = int(ceil(float(units.size()) / cols))
	for i in range(units.size()):
		var col := i % cols; var row := i / cols
		var off := Vector2(col - (cols - 1) * 0.5, row - (rows - 1) * 0.5) * 0.9 * PPU
		units[i].command_move(w + off)

# Nút điều khiển trên màn hình (CanvasLayer → cố định, ko bị camera zoom).
const GAME_VERSION := "v0.1 build 7"

func _build_ui() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	_build_menu(cl)
	# Version nhỏ góc dưới-trái (để kiểm tra bản web có phải mới nhất)
	var vlbl := Label.new()
	vlbl.text = GAME_VERSION
	vlbl.add_theme_font_size_override("font_size", 30)
	vlbl.modulate = Color(1, 1, 1, 0.55)
	var vp0 := get_viewport().get_visible_rect().size
	vlbl.position = Vector2(24, vp0.y - 52); vlbl.size = Vector2(420, 44)
	cl.add_child(vlbl)
	_fps_label = Label.new()
	_fps_label.add_theme_font_size_override("font_size", 44)
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.position = Vector2(get_viewport().get_visible_rect().size.x - 240, 24)
	_fps_label.size = Vector2(210, 50)
	_fps_label.visible = _show_fps
	cl.add_child(_fps_label)
	# Đồng hồ thời gian trận — cạnh nút Settings (gear ở 30,30 cỡ 110)
	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", 52)
	_time_label.position = Vector2(160, 44); _time_label.size = Vector2(260, 60)
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cl.add_child(_time_label)
	# HUD: 3 loại resource (Gỗ / Vàng / Thịt), icon + số, ở GIỮA-TRÊN màn hình
	var vp := get_viewport().get_visible_rect().size
	var defs := [
		["Wood", "Pawn and Resources/Wood/Wood Resource/Wood Resource.png"],
		["Gold", "UI Elements/Icons/Icon_03.png"],
		["Meat", "Pawn and Resources/Meat/Meat Resource/Meat Resource.png"],
	]
	var isz := 150.0; var gap := 320.0   # icon TO gấp ~3
	var x0: float = vp.x * 0.5 - gap * 1.5 - 40.0
	for i in range(defs.size()):
		var key: String = defs[i][0]
		var icon := TextureRect.new()
		icon.texture = load(ART + defs[i][1])
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var s: float = isz * (0.85 if key == "Gold" else 1.0)   # icon tiền hơi to → thu nhỏ 1 chút
		icon.custom_minimum_size = Vector2(s, s); icon.size = Vector2(s, s)
		icon.position = Vector2(x0 + i * gap + (isz - s) * 0.5, 16 + (isz - s) * 0.5)
		cl.add_child(icon)
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 64)
		lbl.text = str(_res[key])
		lbl.position = Vector2(x0 + i * gap + isz - 4, 48)
		cl.add_child(lbl)
		_res_labels[key] = lbl
	# HUD UNIT: icon DÂN (avatar) + số unit / cap
	var uicon := TextureRect.new()
	uicon.texture = load(ART + "UI Elements/Human Avatars/Avatars_05.png")
	uicon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	uicon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	uicon.custom_minimum_size = Vector2(isz, isz); uicon.size = Vector2(isz, isz)
	uicon.position = Vector2(x0 + 3 * gap, 16)
	cl.add_child(uicon)
	_unit_label = Label.new()
	_unit_label.add_theme_font_size_override("font_size", 64)
	_unit_label.position = Vector2(x0 + 3 * gap + isz - 4, 48)
	cl.add_child(_unit_label)
	# Nút CÀI ĐẶT: CHỈ icon bánh răng, KHÔNG nền nút
	var sbtn := Button.new(); sbtn.flat = true
	sbtn.icon = load(ART + "UI Elements/Icons/Icon_10.png"); sbtn.expand_icon = true
	sbtn.position = Vector2(30, 30); sbtn.custom_minimum_size = Vector2(110, 110); sbtn.size = Vector2(110, 110)
	sbtn.focus_mode = Control.FOCUS_NONE
	sbtn.process_mode = Node.PROCESS_MODE_ALWAYS   # bấm được kể cả sau GAME OVER / khi pause
	sbtn.pressed.connect(func(): play_sfx("click"); _on_settings())
	cl.add_child(sbtn)
	_build_settings(cl)
	# Bảng XÂY (nền Banner TO +30%, kéo dài, mỗi nhà 1 slot) — hiện khi chọn nông dân
	_build_panel = Control.new()
	# Banner.png 320²: vùng cream THẬT = tex x48..276, y64..268 (ngoài là biên+trong suốt).
	# bw co giãn theo SỐ slot: cream = n*300 + (n+1)*24, + biên trái48/phải44.
	var build_types := ["house", "barracks", "archer", "monk", "tower"]
	var bn: int = build_types.size()
	var bw: float = bn * 300.0 + (bn + 1) * 24.0 + 92.0
	var bh := 404.0
	_build_panel.position = Vector2(vp.x * 0.5 - bw * 0.5, vp.y - bh + 24)
	var bbg := NinePatchRect.new()
	bbg.texture = load(ART + "UI Elements/Banners/Banner.png")
	bbg.patch_margin_left = 48; bbg.patch_margin_right = 44
	bbg.patch_margin_top = 64; bbg.patch_margin_bottom = 52
	bbg.size = Vector2(bw, bh)
	_build_panel.add_child(bbg)
	# lề ĐỀU 4 phía = khe giữa slot = 24; căn từ TRÁI (1 slot → sát lề trái)
	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 24)
	hb.position = Vector2(72, 88); hb.size = Vector2(bw - 144, 240)
	_build_panel.add_child(hb)
	_build_x = {}
	for t in build_types:
		hb.add_child(_mk_build_slot(t, BUILD_INFO[t]))
	_build_panel.visible = false
	cl.add_child(_build_panel)
	# Bảng SẢN XUẤT unit (click nhà) — nền Banner, nội dung dựng lại theo nhà
	_prod_panel = Control.new()
	_prod_panel.position = Vector2(vp.x * 0.5 - bw * 0.5, vp.y - bh + 24)
	var pbg := NinePatchRect.new()
	pbg.texture = load(ART + "UI Elements/Banners/Banner.png")
	pbg.patch_margin_left = 48; pbg.patch_margin_right = 44; pbg.patch_margin_top = 64; pbg.patch_margin_bottom = 52
	pbg.size = Vector2(bw, bh)
	_prod_bg = pbg
	_prod_panel.add_child(pbg)
	_prod_hb = HBoxContainer.new(); _prod_hb.add_theme_constant_override("separation", 24)
	_prod_hb.position = Vector2(72, 88); _prod_hb.size = Vector2(bw - 144, 240)
	_prod_panel.add_child(_prod_hb)
	_prod_panel.visible = false
	cl.add_child(_prod_panel)
	_lose_label = Label.new()
	_lose_label.add_theme_font_size_override("font_size", 120)
	_lose_label.text = "GAME OVER"
	_lose_label.position = Vector2(vp.x * 0.5 - 160, vp.y * 0.5 - 60)
	_lose_label.visible = false
	cl.add_child(_lose_label)
	_msg_label = Label.new()
	_msg_label.add_theme_font_size_override("font_size", 56)
	_msg_label.position = Vector2(vp.x * 0.5 - 300, vp.y * 0.32)
	_msg_label.size = Vector2(600, 70)
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_label.visible = false
	cl.add_child(_msg_label)

func _show_msg(t: String, dur := 1.5) -> void:
	if _msg_label == null: return
	_msg_label.text = t; _msg_label.visible = true; _msg_t = dur

# 1 slot công trình trong bảng XÂY: nền Banner_Slots + hình nhà + tên + giá (giống ảnh mẫu).
func _mk_build_slot(t: String, info: Dictionary) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(300, 240)
	var bg := NinePatchRect.new()
	bg.texture = load(ART + "UI Elements/Banners/Banner_Slots.png")
	bg.patch_margin_left = 24; bg.patch_margin_right = 24; bg.patch_margin_top = 24; bg.patch_margin_bottom = 24
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.add_child(bg)
	var bsheet: String = info.get("sheet", "House1")
	var img := TextureRect.new()
	img.texture = load(ART + "Buildings/Blue Buildings/%s.png" % bsheet)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.position = Vector2(18, 6); img.size = Vector2(264, 128)
	slot.add_child(img)
	var nm := Label.new(); nm.text = str(info["label"])
	nm.add_theme_font_size_override("font_size", 32)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.position = Vector2(0, 142); nm.size = Vector2(300, 36)
	slot.add_child(nm)
	# GIÁ nhà = SỐ + icon GỖ (như slot mua lính), to & căn giữa
	_add_cost_row(slot, {"Wood": int(info["cost"])}, 150.0, 184.0, 272.0)
	var btn := Button.new(); btn.flat = true; btn.focus_mode = Control.FOCUS_NONE
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ty := t
	btn.pressed.connect(func(): play_sfx("click"); build_building(ty))
	slot.add_child(btn)
	# Nút X ở GÓC trên-phải slot — chỉ hiện khi nhà này đang được chọn để xây (hủy đặt)
	var xb := Button.new(); xb.flat = true; xb.focus_mode = Control.FOCUS_NONE
	xb.icon = load(ART + "UI Elements/Icons/Icon_09.png"); xb.expand_icon = true
	xb.position = Vector2(244, 8); xb.custom_minimum_size = Vector2(52, 52); xb.size = Vector2(52, 52)
	xb.visible = false
	xb.pressed.connect(_cancel_build)
	slot.add_child(xb)
	_build_x[t] = xb
	return slot

func _cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for k in cost: parts.append("%d %s" % [int(cost[k]), str(RES_VN.get(k, k))])
	return " ".join(parts)

# Click nhà → mở menu mua unit của nhà đó (nhà ko sản xuất gì thì ko mở).
func _select_building(b) -> void:
	_clear_selection()
	_sel_building = b; _prod_cards = {}
	for c in _prod_hb.get_children(): c.queue_free()
	var kinds: Array = PROD_BY_BUILDING.get(b.btype, []) if b.is_built() else []
	for kind in kinds:
		_prod_hb.add_child(_mk_unit_slot(kind, b))
	var has_destroy: bool = b.btype != "castle"   # Castle (nhà chính) KO phá được
	if has_destroy:
		_prod_hb.add_child(_mk_destroy_slot(b))
	var n: int = kinds.size() + (1 if has_destroy else 0)
	if n == 0:
		_prod_panel.visible = false; _sel_building = null; return
	# banner CO GIÃN vừa khít số slot: cream = n*300 + (n+1)*24, + biên trái48/phải44
	var bw: float = n * 300.0 + (n + 1) * 24.0 + 92.0
	var vp := get_viewport().get_visible_rect().size
	_prod_bg.size.x = bw
	_prod_hb.size.x = bw - 144
	_prod_panel.position.x = vp.x * 0.5 - bw * 0.5
	_build_panel.visible = false
	_prod_panel.visible = true

# Slot PHÁ DỠ nhà (đỏ). Nhà đang xây → hoàn lại gỗ.
func _mk_destroy_slot(b) -> Control:
	var slot := Control.new(); slot.custom_minimum_size = Vector2(300, 240)
	var bg := NinePatchRect.new()
	bg.texture = load(ART + "UI Elements/Banners/Banner_Slots.png")
	bg.patch_margin_left = 24; bg.patch_margin_right = 24; bg.patch_margin_top = 24; bg.patch_margin_bottom = 24
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.add_child(bg)
	var ic := TextureRect.new(); ic.texture = load(ART + "UI Elements/Icons/Icon_09.png")
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.position = Vector2(96, 20); ic.size = Vector2(108, 108)
	ic.modulate = Color(1.0, 0.45, 0.45)
	slot.add_child(ic)
	var nm := Label.new(); nm.text = "Destroy"; nm.add_theme_font_size_override("font_size", 34)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	nm.position = Vector2(0, 152); nm.size = Vector2(300, 40)
	slot.add_child(nm)
	var bb = b
	var btn := Button.new(); btn.flat = true; btn.focus_mode = Control.FOCUS_NONE
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.pressed.connect(func(): play_sfx("click"); _destroy_building(bb))
	slot.add_child(btn)
	return slot

# Phá nhà mình: đang xây → HOÀN gỗ; rồi cho nổ (nhả ô đi được).
func _destroy_building(b) -> void:
	if not is_instance_valid(b) or b.btype == "castle": return
	if not b.is_built():                              # đang xây → hoàn lại gỗ đã bỏ
		add_resource("Wood", int(BUILD_INFO[b.btype]["cost"]))
	b.take_damage(b.max_hp * 2.0)                     # giết → nổ + trả ô đi được
	_prod_panel.visible = false; _sel_building = null
	_clear_selection()

func _mk_unit_slot(kind: String, b) -> Control:
	var info: Dictionary = UNIT_INFO[kind]
	var slot := Control.new(); slot.custom_minimum_size = Vector2(300, 240)
	var bg := NinePatchRect.new()
	bg.texture = load(ART + "UI Elements/Banners/Banner_Slots.png")
	bg.patch_margin_left = 24; bg.patch_margin_right = 24; bg.patch_margin_top = 24; bg.patch_margin_bottom = 24
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.add_child(bg)
	# AVATAR (bấm để xếp hàng tạo) — trái-trên
	var img := TextureRect.new(); img.texture = load(ART + "UI Elements/Human Avatars/%s.png" % str(info["avatar"]))
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.position = Vector2(16, 10); img.size = Vector2(140, 140)
	slot.add_child(img)
	var k := kind; var bb = b
	var abtn := Button.new(); abtn.flat = true; abtn.focus_mode = Control.FOCUS_NONE
	abtn.position = Vector2(16, 10); abtn.custom_minimum_size = Vector2(140, 140); abtn.size = Vector2(140, 140)
	abtn.pressed.connect(func(): play_sfx("click"); _buy_unit(bb, k))
	slot.add_child(abtn)
	# Số đang/đợi tạo (xN) — góc trái-trên avatar
	var cnt := Label.new(); cnt.add_theme_font_size_override("font_size", 44); cnt.position = Vector2(22, 8)
	cnt.add_theme_color_override("font_color", Color(1, 0.95, 0.4))
	slot.add_child(cnt)
	# Progress bar BÊN PHẢI (dọc) — thấp hơn (ngang avatar), ko quá cao
	var bar := ProgressBar.new(); bar.min_value = 0; bar.max_value = 100; bar.value = 0; bar.show_percentage = false
	bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	bar.position = Vector2(228, 14); bar.custom_minimum_size = Vector2(38, 112); bar.size = Vector2(38, 112)
	slot.add_child(bar)
	# Nút CANCEL (icon X) — dưới progress bar, hủy 1 & trả resource
	var cancel := Button.new(); cancel.flat = true; cancel.focus_mode = Control.FOCUS_NONE
	cancel.icon = load(ART + "UI Elements/Icons/Icon_09.png"); cancel.expand_icon = true
	cancel.position = Vector2(222, 136); cancel.custom_minimum_size = Vector2(50, 50); cancel.size = Vector2(50, 50)
	cancel.pressed.connect(func(): _cancel_unit(bb, k))
	slot.add_child(cancel)
	# GIÁ = SỐ + icon resource, to & căn giữa vùng dưới avatar (x 12..204)
	_add_cost_row(slot, info["cost"], 108.0, 168.0, 192.0)
	_prod_cards[kind] = {"count": cnt, "bar": bar}
	return slot

# Hàng GIÁ: cặp [số + icon] căn giữa quanh cx (rộng tối đa region_w), số & icon TO.
func _add_cost_row(slot: Control, cost: Dictionary, cx: float, y: float, region_w: float) -> void:
	var n: int = cost.size()
	var isz := 44.0; var fs := 42; var gap := 6.0; var pgap := 18.0
	if n == 2: isz = 40.0; fs = 36
	elif n >= 3: isz = 26.0; fs = 24; pgap = 10.0
	var fnt := ThemeDB.fallback_font
	var items: Array = []; var total := 0.0
	for res in cost:
		var txt := str(int(cost[res]))
		var tw: float = fnt.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		items.append({"txt": txt, "tw": tw, "res": res})
		total += tw + gap + isz
	total += pgap * max(0, n - 1)
	var x: float = cx - min(total, region_w) * 0.5
	for it in items:
		var num := Label.new(); num.text = it["txt"]; num.add_theme_font_size_override("font_size", fs)
		num.position = Vector2(x, y); num.size = Vector2(it["tw"] + 4, isz)
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.add_child(num)
		x += it["tw"] + gap
		var ric := TextureRect.new(); ric.texture = load(ART + str(_RES_ICON.get(it["res"], _RES_ICON["Wood"])))
		ric.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ric.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ric.position = Vector2(x, y); ric.size = Vector2(isz, isz)
		slot.add_child(ric)
		x += isz + pgap

func _update_prod_cards() -> void:
	if _prod_panel == null or not _prod_panel.visible: return
	if not is_instance_valid(_sel_building):
		_prod_panel.visible = false; return
	for kind in _prod_cards:
		var card: Dictionary = _prod_cards[kind]
		var c: int = _sel_building.queue_count(kind)
		card["count"].text = ("x%d" % c) if c > 0 else ""
		card["bar"].value = _sel_building.progress_of(kind) * 100.0

func _unit_count() -> int:
	var n := 0
	for f in get_tree().get_nodes_in_group("fighter"):
		if is_instance_valid(f) and f.team == 0 and not f.is_dead(): n += 1
	return n

func _total_queued() -> int:   # CHỈ đếm hàng đợi của NGƯỜI CHƠI (team 0), ko tính nhà AI
	var n := 0
	for b in get_tree().get_nodes_in_group("building"):
		if is_instance_valid(b) and b.team == 0 and b.has_method("queue_count"): n += b.queue.size()
	return n

func _buy_unit(b, kind: String) -> void:
	if not is_instance_valid(b): return
	var info: Dictionary = UNIT_INFO[kind]
	if _unit_count() + _total_queued() >= _unit_cap:
		_show_msg("Population full! (build more Houses)"); return
	for k in info["cost"]:
		if _res.get(k, 0) < int(info["cost"][k]):
			_show_msg("Not enough %s!" % str(RES_VN.get(k, k))); return
	for k in info["cost"]:
		_res[k] -= int(info["cost"][k])
		if _res_labels.has(k): _res_labels[k].text = str(_res[k])
	b.enqueue(kind, float(info["time"]))

func _cancel_unit(b, kind: String) -> void:
	if not is_instance_valid(b): return
	if b.cancel_one(kind):                       # hủy 1 → TRẢ resource
		var info: Dictionary = UNIT_INFO[kind]
		for k in info["cost"]:
			_res[k] = _res.get(k, 0) + int(info["cost"][k])
			if _res_labels.has(k): _res_labels[k].text = str(_res[k])

func spawn_unit_front(b, kind: String) -> void:   # unit ĐI RA TỪ cửa nhà rồi dừng ở ô trống phía trước
	if not is_instance_valid(b): return
	var cell := nearest_free(b.cell.x, b.cell.y + b.foot + 1)
	var f := _make_fighter(_world, b.team, ("Blue" if b.team == 0 else "Red"), kind, cell)
	# sinh ra ở CHÂN nhà (cửa) rồi tự đi xuống ô trống → trông như bước ra khỏi nhà
	f.position = b.global_position + Vector2(0, b.foot * PPU)
	f.command_move(Vector2(cell.x + 0.5, cell.y + 0.5) * PPU)
	play_sfx("spawn", f.position)
	if b.team == 0: _update_unit_hud()

# Cạn resource → mọc lại 1 cái cùng loại ở ô cỏ trống NGẪU NHIÊN khác.
func respawn_resource(kind: String) -> void:
	if _world == null: return
	var pool: Array = _interior_cells if kind == "tree" else _grass_cells
	if pool.is_empty(): return
	for _t in range(40):
		var c: Vector2i = pool[rng.randi() % pool.size()]
		if not hmap.walkable.get(c, false) or near_plateau(c) or _coastal(c): continue
		match kind:
			"tree":
				var tr := make_tree(c); _tag_res(tr, "Axe"); tr.add_to_group("clearable"); _world.add_child(tr)
				hmap.walkable[c] = false
			"gold":
				var g := make_gold(c); _tag_res(g, "Pickaxe"); _world.add_child(g)
				hmap.walkable[c] = false
			"sheep":
				var s := Sheep.new(); s.position = Vector2(c.x + 0.5, c.y + 0.5) * PPU; s.builder = self
				_tag_res(s, "Knife"); s.add_to_group("clearable"); _world.add_child(s)
				s.setup(_grass_set, SEED + c.x * 7 + c.y * 31 + _gen_count)
		return

# Bảng CÀI ĐẶT: nền SpecialPaper + thanh âm lượng Nhạc & Âm thanh.
func _build_settings(cl: CanvasLayer) -> void:
	var vp := get_viewport().get_visible_rect().size
	var w := 1160.0; var h := 940.0   # GẤP ĐÔI (nhìn trên điện thoại cho rõ)
	# Nền mờ phủ TOÀN màn hình (che mọi banner) khi mở Settings
	_modal_dim = ColorRect.new()
	_modal_dim.color = Color(0, 0, 0, 0.55)
	_modal_dim.position = Vector2.ZERO; _modal_dim.size = vp
	_modal_dim.z_index = 190; _modal_dim.process_mode = Node.PROCESS_MODE_ALWAYS
	_modal_dim.mouse_filter = Control.MOUSE_FILTER_STOP   # chặn chạm xuyên xuống game
	_modal_dim.visible = false
	cl.add_child(_modal_dim)
	_settings_panel = Control.new()
	_settings_panel.process_mode = Node.PROCESS_MODE_ALWAYS   # vẫn bấm được khi game PAUSE
	_settings_panel.z_index = 200   # đè lên mọi banner (mua dân / xây nhà)
	_settings_panel.position = Vector2(vp.x * 0.5 - w * 0.5, vp.y * 0.5 - h * 0.5)
	var bg := NinePatchRect.new()
	bg.texture = load(ART + "UI Elements/Papers/SpecialPaper.png")
	bg.patch_margin_left = 56; bg.patch_margin_right = 56; bg.patch_margin_top = 56; bg.patch_margin_bottom = 56
	bg.size = Vector2(w, h)
	_settings_panel.add_child(bg)
	# Nút ĐÓNG = icon X (Icon_09), góc trên-phải, ko chữ
	var close := Button.new(); close.flat = true; close.focus_mode = Control.FOCUS_NONE
	close.icon = load(ART + "UI Elements/Icons/Icon_09.png"); close.expand_icon = true
	close.position = Vector2(w - 208, 72); close.custom_minimum_size = Vector2(160, 160); close.size = Vector2(160, 160)
	close.pressed.connect(_close_settings)
	_settings_panel.add_child(close)
	# Nút BẮT ĐẦU MÀN MỚI → ở TRÊN CÙNG
	var ng := Button.new(); ng.text = "New Game"; ng.add_theme_font_size_override("font_size", 72)
	ng.position = Vector2(w * 0.5 - 320, 72); ng.custom_minimum_size = Vector2(640, 192); ng.size = Vector2(640, 192)
	ng.focus_mode = Control.FOCUS_NONE; _style_btn(ng)
	ng.pressed.connect(_on_new_game)
	_settings_panel.add_child(ng)
	# 2 thanh âm lượng (gấp đôi)
	_settings_panel.add_child(_mk_vol_row("UI Elements/Icons/Icon_12.png", 380.0, 128.0, linear_to_db(maxf(_music_vol, 0.0001)), _set_music_vol))
	_settings_panel.add_child(_mk_vol_row("UI Elements/Icons/volume.png", 540.0, 192.0, linear_to_db(maxf(_sfx_vol, 0.0001)), _set_sfx_vol))
	# Nút INFO (Icon_11) ở góc DƯỚI-PHẢI bên trong panel Settings
	_info_btn = Button.new(); _info_btn.flat = true; _info_btn.focus_mode = Control.FOCUS_NONE
	_info_btn.icon = load(ART + "UI Elements/Icons/Icon_11.png"); _info_btn.expand_icon = true
	_info_btn.position = Vector2(w - 176, h - 176); _info_btn.custom_minimum_size = Vector2(116, 116); _info_btn.size = Vector2(116, 116)
	_info_btn.pressed.connect(func(): if _credits_panel != null: _credits_panel.visible = true)
	_settings_panel.add_child(_info_btn)
	_settings_panel.visible = false
	cl.add_child(_settings_panel)
	_build_credits(cl)
	_build_confirm(cl)

# Tờ giấy CREDIT tác giả asset Tiny Swords.
func _build_credits(cl: CanvasLayer) -> void:
	var vp := get_viewport().get_visible_rect().size
	var w := 1200.0; var h := 820.0
	_credits_panel = Control.new()
	_credits_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_credits_panel.z_index = 210
	_credits_panel.position = Vector2(vp.x * 0.5 - w * 0.5, vp.y * 0.5 - h * 0.5)
	var bg := NinePatchRect.new()
	bg.texture = load(ART + "UI Elements/Papers/SpecialPaper.png")
	bg.patch_margin_left = 56; bg.patch_margin_right = 56; bg.patch_margin_top = 56; bg.patch_margin_bottom = 56
	bg.size = Vector2(w, h)
	_credits_panel.add_child(bg)
	var close := Button.new(); close.flat = true; close.focus_mode = Control.FOCUS_NONE
	close.icon = load(ART + "UI Elements/Icons/Icon_09.png"); close.expand_icon = true
	close.position = Vector2(w - 188, 64); close.custom_minimum_size = Vector2(140, 140); close.size = Vector2(140, 140)
	close.pressed.connect(func(): _credits_panel.visible = false)
	_credits_panel.add_child(close)
	var txt := Label.new()
	txt.add_theme_font_size_override("font_size", 46)
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.text = "Credits\n\nAll art assets are from the\n\"Tiny Swords\" pack by Pixel Frog.\n\nassetstore.unity.com/packages/2d/\nenvironments/tiny-swords-352566\n\nHuge thanks to the author for\nthis wonderful artwork!"
	txt.position = Vector2(80, 150); txt.size = Vector2(w - 160, h - 240)
	_credits_panel.add_child(txt)
	_credits_panel.visible = false
	cl.add_child(_credits_panel)

func _mk_vol_row(icon_path: String, y: float, isize: float, vol_db: float, cb: Callable) -> Control:
	var row := Control.new()
	var icon := TextureRect.new(); icon.texture = load(ART + icon_path)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(100 - (isize - 128) * 0.5, y - (isize - 128) * 0.5); icon.size = Vector2(isize, isize)
	row.add_child(icon)
	var sl := HSlider.new()
	sl.min_value = 0.0; sl.max_value = 1.0; sl.step = 0.01
	sl.value = db_to_linear(vol_db)
	sl.position = Vector2(300, y - 6); sl.custom_minimum_size = Vector2(720, 112); sl.size = Vector2(720, 112)   # CAO → dễ chạm trên ĐT
	# thanh DÀY + nút kéo TO (chạm bằng ngón tay)
	var track := StyleBoxFlat.new(); track.bg_color = Color(0, 0, 0, 0.35); track.set_corner_radius_all(12)
	track.content_margin_top = 22; track.content_margin_bottom = 22
	sl.add_theme_stylebox_override("slider", track)
	var fillsb := StyleBoxFlat.new(); fillsb.bg_color = Color(0.55, 0.78, 0.45); fillsb.set_corner_radius_all(12)
	fillsb.content_margin_top = 22; fillsb.content_margin_bottom = 22
	sl.add_theme_stylebox_override("grabber_area", fillsb)
	sl.add_theme_stylebox_override("grabber_area_highlight", fillsb)
	var knob := _circle_tex(72, Color(0.98, 0.9, 0.55))
	sl.add_theme_icon_override("grabber", knob)
	sl.add_theme_icon_override("grabber_highlight", _circle_tex(72, Color(1, 0.97, 0.75)))
	sl.value_changed.connect(cb)
	row.add_child(sl)
	return row

# Texture hình tròn (cho nút kéo slider to).
func _circle_tex(d: int, col: Color) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := d * 0.5
	for yy in range(d):
		for xx in range(d):
			var dx := xx - r + 0.5; var dy := yy - r + 0.5
			if dx * dx + dy * dy <= r * r: img.set_pixel(xx, yy, col)
	return ImageTexture.create_from_image(img)

var _confirm_panel: Control

func _build_confirm(cl: CanvasLayer) -> void:
	var vp := get_viewport().get_visible_rect().size
	var w := 960.0; var h := 560.0   # GẤP ĐÔI
	_confirm_panel = Control.new()
	_confirm_panel.process_mode = Node.PROCESS_MODE_ALWAYS   # bấm được khi PAUSE
	_confirm_panel.z_index = 220
	_confirm_panel.position = Vector2(vp.x * 0.5 - w * 0.5, vp.y * 0.5 - h * 0.5)
	var bg := NinePatchRect.new()
	bg.texture = load(ART + "UI Elements/Papers/SpecialPaper.png")
	bg.patch_margin_left = 56; bg.patch_margin_right = 56; bg.patch_margin_top = 56; bg.patch_margin_bottom = 56
	bg.size = Vector2(w, h)
	_confirm_panel.add_child(bg)
	var q := Label.new(); q.text = "Start a new game?"; q.add_theme_font_size_override("font_size", 88)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; q.position = Vector2(0, 100); q.size = Vector2(w, 100)
	_confirm_panel.add_child(q)
	var yes := Button.new(); yes.text = "Yes"; yes.add_theme_font_size_override("font_size", 72)
	yes.position = Vector2(100, h - 232); yes.custom_minimum_size = Vector2(360, 184); yes.size = Vector2(360, 184); yes.focus_mode = Control.FOCUS_NONE
	_style_btn(yes); yes.pressed.connect(_start_new_game)
	_confirm_panel.add_child(yes)
	var no := Button.new(); no.text = "No"; no.add_theme_font_size_override("font_size", 72)
	no.position = Vector2(w - 460, h - 232); no.custom_minimum_size = Vector2(360, 184); no.size = Vector2(360, 184); no.focus_mode = Control.FOCUS_NONE
	_style_btn(no); no.pressed.connect(func(): _confirm_panel.visible = false)
	_confirm_panel.add_child(no)
	_confirm_panel.visible = false
	cl.add_child(_confirm_panel)

func _on_new_game() -> void:
	if _confirm_panel != null: _confirm_panel.visible = true

# Bấm "Yes" trong confirm → đóng HẾT menu (kể cả nền mờ) rồi dựng màn mới.
func _start_new_game() -> void:
	_close_overlays()
	get_tree().paused = false
	build_map()

# Mở settings → PAUSE toàn bộ game (ko bấm được gì khác). Đóng → chạy tiếp.
func _on_settings() -> void:
	if _settings_panel == null: return
	var show := not _settings_panel.visible
	_settings_panel.visible = show
	if _modal_dim != null: _modal_dim.visible = show
	if _lose_label != null: _lose_label.visible = (not show) and _match_over   # ẩn chữ GAME OVER khi mở menu
	if not show:
		if _credits_panel != null: _credits_panel.visible = false
		if _menu != null: _menu.visible = false
	get_tree().paused = show

# Ẩn TẤT CẢ lớp menu/overlay (settings, confirm, credits, debug, nền mờ).
func _close_overlays() -> void:
	if _settings_panel != null: _settings_panel.visible = false
	if _modal_dim != null: _modal_dim.visible = false
	if _confirm_panel != null: _confirm_panel.visible = false
	if _credits_panel != null: _credits_panel.visible = false
	if _menu != null: _menu.visible = false

func _close_settings() -> void:
	_close_overlays()
	if _lose_label != null and _match_over: _lose_label.visible = true
	get_tree().paused = false

# Nhạc nền: fade IN 1.5s đầu, fade OUT 3s cuối (player volume riêng, ko đụng âm lượng user trên bus).
func _music_fade() -> void:
	if _music == null or not _music.playing: return
	# fade-in theo THỜI GIAN THẬT (web: get_playback_position có thể = 0 lúc context suspended → bị câm)
	var el: float = (Time.get_ticks_msec() - _music_start_ms) / 1000.0
	var f := 1.0
	if el < 1.5: f = el / 1.5
	if _music.stream != null:
		var L: float = _music.stream.get_length()
		var pos: float = _music.get_playback_position()
		if L > 0.0 and pos > 0.5 and L - pos < 3.0: f = minf(f, (L - pos) / 3.0)   # fade-out cuối (chỉ khi pos đáng tin)
	_music.volume_db = linear_to_db(clampf(f * _music_vol, 0.0001, 1.0))   # fade × âm lượng user

func _set_music_vol(v: float) -> void:
	_music_vol = clampf(v, 0.0, 1.0)
	if _music != null: _music.volume_db = linear_to_db(maxf(_music_vol, 0.0001))
	_save_volumes()

func _set_sfx_vol(v: float) -> void:
	_sfx_vol = clampf(v, 0.0, 1.0)
	_save_volumes()

func add_resource(type: String, n: int) -> void:   # nông dân giao hàng → +n đúng loại + cập nhật HUD
	if not _res.has(type): return
	_res[type] += n
	if _res_labels.has(type): _res_labels[type].text = str(_res[type])

# Giao hàng theo ĐỘI: XANH (0) → kho người chơi + HUD + "+1" bay lên; ĐỎ (1) → kho AI.
func deliver(team: int, type: String, n: int, pos: Vector2) -> void:
	if team == 0:
		add_resource(type, n)
		float_gain(pos, type)
		play_sfx("coin", pos)
	else:
		_ai_res[type] = _ai_res.get(type, 0) + n

const _RES_ICON := {
	"Wood": "Pawn and Resources/Wood/Wood Resource/Wood Resource.png",
	"Gold": "UI Elements/Icons/Icon_03.png",
	"Meat": "Pawn and Resources/Meat/Meat Resource/Meat Resource.png",
}

# Icon búa bay lên (khi xây/sửa) — giống hiệu ứng khai thác.
func float_build_icon(p: Vector2) -> void:
	var s := Sprite2D.new()
	s.texture = load(ART + "UI Elements/Icons/Icon_01.png")
	s.scale = Vector2(0.7, 0.7); s.z_index = 950; s.position = p + Vector2(0, -30)
	if _gen != null: _gen.add_child(s)
	var tw := s.create_tween(); tw.set_parallel(true)
	tw.tween_property(s, "position:y", s.position.y - 64, 0.9)
	tw.tween_property(s, "modulate:a", 0.0, 0.9)
	tw.set_parallel(false); tw.tween_callback(func(): if is_instance_valid(s): s.queue_free())

# "+1" + icon resource bay lên mờ dần (khi giao hàng về nhà).
func float_gain(p: Vector2, type: String) -> void:
	var n := Node2D.new(); n.position = p + Vector2(0, -40); n.z_index = 950
	if _gen != null: _gen.add_child(n)
	var s := Sprite2D.new(); s.texture = load(ART + str(_RES_ICON.get(type, _RES_ICON["Wood"])))
	s.scale = Vector2(0.42, 0.42); s.position = Vector2(-24, 0); n.add_child(s)
	var l := Label.new(); l.text = "+1"; l.add_theme_font_size_override("font_size", 40); l.position = Vector2(6, -26)
	n.add_child(l)
	var tw := n.create_tween(); tw.set_parallel(true)
	tw.tween_property(n, "position:y", n.position.y - 80, 1.1)
	tw.tween_property(n, "modulate:a", 0.0, 1.1)
	tw.set_parallel(false); tw.tween_callback(func(): if is_instance_valid(n): n.queue_free())

func _update_unit_hud() -> void:
	if _unit_label == null: return
	var n := 0
	for f in get_tree().get_nodes_in_group("fighter"):
		if is_instance_valid(f) and f.team == 0 and not f.is_dead(): n += 1
	_unit_label.text = "%d/%d" % [n, _unit_cap]

func _update_build_panel() -> void:   # hiện bảng XÂY khi nhóm chọn có nông dân
	if _build_panel == null: return
	var has_pawn := false
	for u in _selected:
		if is_instance_valid(u) and u.kind == "Pawn": has_pawn = true; break
	_build_panel.visible = has_pawn
	if _prod_panel != null and not _selected.is_empty(): _prod_panel.visible = false   # chọn lính → ẩn menu sản xuất

# Bấm nút XÂY → vào CHẾ ĐỘ ĐẶT (ghost mờ + chữ "chọn vị trí"); ko đủ gỗ → báo.
func build_building(type: String) -> void:
	if not BUILD_INFO.has(type): return
	var info: Dictionary = BUILD_INFO[type]
	if _res["Wood"] < int(info["cost"]):
		_show_msg("Not enough Wood! (need %d)" % int(info["cost"])); return
	if not _has_pawn_selected(): return
	_build_mode = type
	_update_build_x()                  # hiện nút X ở góc slot nhà đang chọn xây
	# ghost mờ hiện cạnh nông dân
	var pawn := _first_pawn()
	if _ghost != null and is_instance_valid(_ghost): _ghost.queue_free()
	_ghost = Sprite2D.new()
	var sheet: String = info.get("sheet", "House1")
	_ghost.texture = load(ART + "Buildings/Blue Buildings/%s.png" % sheet)
	_ghost.offset = Vector2(0, feet_offset(_ghost.texture, int(info["w"]), int(info["h"])) + 0.5 * PPU)
	_ghost.modulate = Color(0.4, 1.0, 0.4, 0.5)
	_ghost.z_index = 1200
	if pawn != null: _ghost.position = pawn.position + Vector2(PPU, 0)
	_gen.add_child(_ghost)
	_show_msg("Choose where to build %s (tap to place)" % str(info["label"]), 99.0)

func _first_pawn() -> Fighter:
	for u in _selected:
		if is_instance_valid(u) and u.kind == "Pawn": return u
	return null

# Ô xây hợp lệ: đất, KO ven nước / KO ranh giới cao nguyên / KO đè vật cản (cây/nhà…).
func _can_build(c: Vector2i) -> bool:
	if _build_mode == "" or not BUILD_INFO.has(_build_mode): return false
	var info: Dictionary = BUILD_INFO[_build_mode]
	var foot: int = maxi(0, int((float(info["w"]) / PPU - 1.0) / 2.0))
	var hrows: int = clampi(int(float(info["h"]) / PPU) - 1, 1, 3)
	var lv: int = hmap.lvl(c)   # cao độ ô gốc — CẢ footprint phải cùng cao độ (đồng bằng HOẶC trọn trên cao nguyên)
	for dy in range(-(hrows - 1), 1):
		for dx in range(-foot, foot + 1):
			var cc := Vector2i(c.x + dx, c.y + dy)
			if not is_land(cc.x, cc.y): return false
			if not hmap.walkable.get(cc, false): return false   # đá/nước/đã có nhà/mép
			if _coastal(cc): return false
			if hmap.lvl(cc) != lv: return false                 # ko xây nửa đồi nửa đất
	# cần ÍT NHẤT 1 ô đi-được cạnh nhà (cùng cao độ) để lính đi ra/đứng xây
	for dx in range(-foot, foot + 1):
		if hmap.walkable.get(Vector2i(c.x + dx, c.y + 1), false): return true
	if hmap.walkable.get(Vector2i(c.x - foot - 1, c.y), false): return true
	if hmap.walkable.get(Vector2i(c.x + foot + 1, c.y), false): return true
	return false

func _cancel_build() -> void:
	_build_mode = ""
	if _ghost != null and is_instance_valid(_ghost): _ghost.queue_free()
	_ghost = null
	if _msg_label != null: _msg_label.visible = false; _msg_t = 0.0
	_update_build_x()

# Chỉ HIỆN nút X ở góc slot của nhà ĐANG chọn để xây; còn lại ẩn.
func _update_build_x() -> void:
	for t in _build_x:
		if is_instance_valid(_build_x[t]): _build_x[t].visible = (t == _build_mode)

# Đặt công trình tại ô (sau khi chọn vị trí hợp lệ) → trừ gỗ, tạo Building đang XÂY, giao nông dân tới xây.
func _place_building_at(c: Vector2i) -> void:
	var type := _build_mode
	var info: Dictionary = BUILD_INFO[type]
	if _res["Wood"] < int(info["cost"]):
		_show_msg("Not enough Wood!"); _cancel_build(); return
	_res["Wood"] -= int(info["cost"])
	if _res_labels.has("Wood"): _res_labels["Wood"].text = str(_res["Wood"])
	var b := make_building(type, c, 0)   # team 0
	_world.add_child(b)
	_setup_footprint(b, c, int(info["w"]), int(info["h"]))
	# giao TẤT CẢ nông dân đang chọn đi xây (nhiều nông dân → nhanh hơn)
	for u in _selected:
		if is_instance_valid(u) and u.kind == "Pawn": u.command_build(b)
	_cancel_build()

# Chặn footprint nhà (rộng theo ảnh) + tính chỗ ĐỨNG xây (ô đi-được sát chân nhà).
func _setup_footprint(b: Building, c: Vector2i, w: int, h: int) -> void:
	var foot: int = maxi(0, int((float(w) / PPU - 1.0) / 2.0))   # nửa bề ngang (ô)
	var hrows: int = clampi(int(float(h) / PPU) - 1, 1, 3)       # số hàng SAU nhà (bắc) bị chặn → ko đứng sau
	b.foot = foot
	_clear_build_cells(c, foot, hrows)   # xóa resource/cây/bụi + ĐẨY lính ra khỏi nền + sau nhà
	for dy in range(-(hrows - 1), 1):    # chặn cả thân nhà phía sau (bắc) → người ko đi ra sau bị khuất
		for dx in range(-foot, foot + 1):
			var fc := Vector2i(c.x + dx, c.y + dy)
			hmap.walkable[fc] = false
			hmap.bldg[fc] = true         # đánh dấu ô NHÀ → ghost (nông dân AI) đi xuyên được
	b.work_pos = _building_work_pos(c, foot)

# Dọn nền nhà (cả phần thân sau): xóa resource/cây/bụi/đá; đẩy lính đang đứng đó ra phía NAM.
func _clear_build_cells(c: Vector2i, foot: int, hrows: int) -> void:
	for d in get_tree().get_nodes_in_group("clearable"):
		if not is_instance_valid(d): continue
		var dc := hmap.cell_of(d.global_position)
		if dc.y <= c.y and dc.y > c.y - hrows and absi(dc.x - c.x) <= foot:
			d.queue_free()                 # cây/vàng/cừu/bụi/đá → biến mất
	var k := 0
	for fgt in get_tree().get_nodes_in_group("fighter"):
		if not is_instance_valid(fgt): continue
		var fc := hmap.cell_of(fgt.position)
		if fc.y <= c.y and fc.y > c.y - hrows - 1 and absi(fc.x - c.x) <= foot:   # đứng trên/sau nền
			fgt.command_move(Vector2(c.x + k - foot + 0.5, c.y + foot + 2 + 0.5) * PPU)  # né ra phía nam
			k += 1

func _building_work_pos(c: Vector2i, foot: int) -> Vector2:
	# NGANG HÀNG với nhà (đứng cạnh trái/phải, cùng hàng) → búa mới chạm; fallback xuống nam.
	var cands: Array = [Vector2i(c.x - foot - 1, c.y), Vector2i(c.x + foot + 1, c.y)]
	for dx in range(-foot, foot + 1): cands.append(Vector2i(c.x + dx, c.y + 1))
	for cc in cands:
		if hmap.walkable.get(cc, false): return Vector2(cc.x + 0.5, cc.y + 0.5) * PPU
	return Vector2(c.x - foot - 1 + 0.5, c.y + 0.5) * PPU

func make_building(type: String, cell: Vector2i, tm: int, done := false) -> Building:
	var info: Dictionary = BUILD_INFO[type]
	var sheet: String = info.get("sheet", "")
	if type == "house": sheet = "House%d" % (1 + rng.randi() % 3)   # nhà dân random 1/3
	var clr := "Blue" if tm == 0 else "Red"
	var tex: Texture2D = load(ART + "Buildings/%s Buildings/%s.png" % [clr, sheet])
	var off := feet_offset(tex, int(info["w"]), int(info["h"])) + 0.5 * PPU   # chân nhà sát ĐÁY ô (ngồi trên ô)
	var b := Building.new()
	b.position = Vector2(cell.x + 0.5, cell.y + 0.5) * PPU
	b.hmap = hmap; b.cell = cell; b.builder = self
	b.setup_b(tex, off, type, float(info["hp"]), float(info["time"]), tm, type == "house", done)
	b.add_to_group("occluder")
	return b

func on_house_built() -> void:   # Building gọi khi xây xong nhà dân → +5 cap
	_unit_cap = min(50, _unit_cap + 5)
	_update_unit_hud()

# ===== DỰNG TRẬN: 2 căn cứ giống hệt nhau (XANH người chơi tây, ĐỎ AI đông) =====
func _setup_match(world: Node2D) -> void:
	var xs: Array = land.keys().map(func(c): return c.x)
	var minx: int = xs.min(); var maxx: int = xs.max()
	_place_base(world, 0, "Blue", minx + 9)
	_place_base(world, 1, "Red", maxx - 9)

# 1 căn cứ: Castle + 1 nhà dân gần đó + 5 nông dân đứng thẳng hàng TRƯỚC (nam) castle.
func _place_base(world: Node2D, team: int, color: String, cx: int) -> void:
	var ccell := _fit_cell(cx, 2, 320, 256)
	_place_castle_team(world, team, ccell)
	# nhà dân gần castle, lệch về phía GIỮA map (đông cho xanh, tây cho đỏ)
	var dir := 1 if team == 0 else -1
	var hcell := _fit_cell(ccell.x + dir * 7, ccell.y, 128, 192)
	var hb := make_building("house", hcell, team, true)   # nhà dân dựng sẵn (depot)
	world.add_child(hb)
	_setup_footprint(hb, hcell, 128, 192)
	# 5 nông dân thẳng hàng trước castle (phía nam, dưới chân)
	var fy: int = ccell.y + 4
	for k in range(5):
		_make_fighter(world, team, color, "Pawn", nearest_free(ccell.x - 2 + k, fy))

# Castle 1 đội (depot, đủ máu). Mất castle → thua đội đó.
func _place_castle_team(world: Node2D, team: int, cell: Vector2i) -> void:
	var clr := "Blue" if team == 0 else "Red"
	var tex: Texture2D = load(ART + "Buildings/%s Buildings/Castle.png" % clr)
	var b := Building.new()
	b.position = Vector2(cell.x + 0.5, cell.y + 0.5) * PPU
	b.hmap = hmap; b.cell = cell; b.builder = self
	b.setup_b(tex, feet_offset(tex, 320, 256) + 0.5 * PPU, "castle", 1000.0, 1.0, team, true, true)
	b.add_to_group("occluder"); b.add_to_group("castle")
	world.add_child(b)
	_setup_footprint(b, cell, 320, 256)
	_castle_placed = true

# Castle CÒN SỐNG của 1 đội (null nếu đã nổ).
func _castle_of(team: int):
	for c in get_tree().get_nodes_in_group("castle"):
		if is_instance_valid(c) and c.team == team and not c.is_dead(): return c
	return null

# Kết thúc trận: hiện VICTORY/GAME OVER, TẮT sương mù + bóng đêm, dừng AI.
func _end_match(player_won: bool) -> void:
	_match_over = true
	_fog_dim_on = false; _fog_black_on = false; _on_fog_toggle()   # fog biến mất
	_clear_selection(); _cancel_build()
	if _build_panel != null: _build_panel.visible = false
	if _prod_panel != null: _prod_panel.visible = false
	if _lose_label != null:
		_lose_label.text = "VICTORY!" if player_won else "GAME OVER"
		_lose_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4) if player_won else Color(1.0, 0.35, 0.35))
		_lose_label.position = Vector2(get_viewport().get_visible_rect().size.x * 0.5 - 320, get_viewport().get_visible_rect().size.y * 0.5 - 70)
		_lose_label.visible = true
	play_sfx("victory" if player_won else "defeat")
	# DỪNG game world (lính/AI/anim) nhưng KO pause cả cây → vẫn zoom/pan camera được
	if _world != null and is_instance_valid(_world): _world.process_mode = Node.PROCESS_MODE_DISABLED

# ===== Mục tiêu AI (snowball mạnh) =====
const AI_PAWN_TARGET := 20                                  # nuôi tới 20 nông dân
const AI_BLD_TARGET := {"barracks": 10, "archer": 10, "monk": 5}   # 10 nhà lính, 10 nhà cung, 5 nhà monk
const AI_ARMY_CAP := 80                                     # trần quân (mua liên tục tới đây)
const AI_ATTACK_MIN := 10                                   # đủ 10 lính → tràn đánh liên tục

# ============================ AI QUÂN ĐỎ ============================
# Mục tiêu: thu hoạch → huấn luyện lính → khi đông hơn người chơi thì tràn sang phá Castle.
# Cho AI lợi thế kinh tế (thu nhập thụ động + huấn luyện nhanh) để người chơi rất khó thắng.
func _ai_tick(delta: float) -> void:
	_ai_t -= delta
	if _ai_t > 0.0: return
	_ai_t = 0.5                                   # suy nghĩ mỗi 0.5s
	var rc = _castle_of(1)
	if rc == null: return
	# thu nhập nhẹ: +1 gỗ +1 thịt mỗi 5s (ngoài ra vẫn phải tự đào)
	_ai_income_t -= 0.5
	if _ai_income_t <= 0.0:
		_ai_income_t = 5.0
		_ai_res["Wood"] = _ai_res.get("Wood", 0) + 1
		_ai_res["Meat"] = _ai_res.get("Meat", 0) + 1
	# phân loại lính đỏ + nhà đỏ ĐÃ XÂY XONG (theo loại)
	var pawns: Array = []; var army: Array = []
	for f in get_tree().get_nodes_in_group("fighter"):
		if not is_instance_valid(f) or f.team != 1 or f.is_dead(): continue
		if f.kind == "Pawn": pawns.append(f)
		else: army.append(f)
	var built_by := {}            # btype -> [Building đã xây]
	var constructing: Array = []  # nhà đỏ đang xây
	for b in get_tree().get_nodes_in_group("building"):
		if not is_instance_valid(b) or b.team != 1: continue
		if b.is_built():
			if not built_by.has(b.btype): built_by[b.btype] = []
			built_by[b.btype].append(b)
		elif b.btype != "castle":
			constructing.append(b)
	var inprog := {}
	for b in constructing: inprog[b.btype] = inprog.get(b.btype, 0) + 1
	# 1) XÂY NHÀ song song (tối đa theo số nông dân) tới khi đủ mục tiêu
	var max_construct: int = clampi(pawns.size() / 4, 1, 3)
	if constructing.size() < max_construct:
		var nt := _ai_next_building(built_by, inprog)
		if nt != "" and _ai_res.get("Wood", 0) >= int(BUILD_INFO[nt]["cost"]):
			var nb = _ai_start_build(nt, rc)
			if nb != null: constructing.append(nb)
	# 2) NÔNG DÂN: gán "nghề" cố định + bù thợ cho MỌI công trình đang xây (mỗi cái ≤2 thợ)
	var need_wood: bool = _ai_next_building(built_by, inprog) != "" or not constructing.is_empty()
	for p in pawns:
		var pid: int = p.get_instance_id()
		if not _ai_pawn_tool.has(pid): _ai_pawn_tool[pid] = _ai_least_assigned_tool(pawns, need_wood)
	var slots: Array = []          # [building, số thợ còn thiếu]
	for b in constructing:
		var nb := 0
		for p in pawns:
			if p.ai_build_target() == b: nb += 1
		if nb < 2: slots.append([b, 2 - nb])
	for p in pawns:
		if p.ai_carrying(): continue
		var bt = p.ai_build_target()
		if bt != null and is_instance_valid(bt): continue          # đang xây cái gì đó → để yên
		var assigned := false
		for sl in slots:
			if sl[1] > 0: p.command_build(sl[0]); sl[1] -= 1; assigned = true; break
		if assigned: continue
		var tool: String = _ai_pawn_tool.get(p.get_instance_id(), "Axe")
		if p.ai_gather_tool() == tool: continue
		var r = _ai_nearest_resource(p.position, tool)
		if r != null: p.command_gather(r)
	# 3) HUẤN LUYỆN liên tục: nông dân tới 20; mỗi NHÀ rảnh → ra 1 lính (song song) tới cap
	_ai_train_t -= 0.5
	if _ai_train_t <= 0.0:
		_ai_train_t = 1.0
		_ai_train_units(rc, built_by, pawns.size(), army.size())
	# 4) QUÂN SỰ: đủ 10 lính → TRÀN phá Castle liên tục; chưa thì THỦ căn cứ
	var pc = _castle_of(0)
	var attack: bool = pc != null and army.size() >= AI_ATTACK_MIN
	var rally: Vector2 = rc.global_position + Vector2(0, 3.0 * PPU)
	var now: int = Time.get_ticks_msec()
	for s in army:
		var id: int = s.get_instance_id()
		var cur = _ai_tgt.get(id)
		# mục tiêu Node chết/biến mất → bỏ (chuỗi "rally" giữ nguyên)
		if cur != null and cur is Object and (not is_instance_valid(cur) or (cur.has_method("is_dead") and cur.is_dead())):
			cur = null; _ai_tgt.erase(id); _ai_chase_t.erase(id)
		var want = null
		if attack:
			# ưu tiên đánh DÂN/lính gần; đang trong thời gian "bỏ đuổi" thì đánh thẳng nhà
			var near_e = null
			if now >= int(_ai_nochase_until.get(id, 0)):
				near_e = _ai_nearest_enemy(s.position, 3.6, true)   # prefer pawn (dân sửa nhà quanh đó)
			if near_e != null:
				if cur == near_e and now - int(_ai_chase_t.get(id, now)) > 5000:
					want = pc; _ai_nochase_until[id] = now + 6000   # đuổi >5s ko kịp → bỏ, đánh nhà 6s
				else:
					want = near_e
					if cur != near_e: _ai_chase_t[id] = now          # đổi mục tiêu → reset đồng hồ đuổi
			else:
				want = pc
		else:
			want = _ai_nearest_enemy(rc.global_position, 7.0, true)   # địch mò tới căn cứ → phản công
		if want != null:
			if want != cur: s.command_attack(want); _ai_tgt[id] = want
		else:
			# THỦ: ko có địch quanh căn cứ → thu quân về (ngừng đuổi), về tới nơi thì thả rảnh
			if cur != null and cur != "rally":
				s.command_move(rally); _ai_tgt[id] = "rally"
			elif cur == "rally":
				if not s.ai_busy(): _ai_tgt.erase(id)
			elif s.position.distance_to(rc.global_position) > 8.0 * PPU and not s.ai_busy():
				s.command_move(rally); _ai_tgt[id] = "rally"

func _ai_afford(cost: Dictionary) -> bool:
	for k in cost:
		if _ai_res.get(k, 0) < int(cost[k]): return false
	return true

func _ai_pay(cost: Dictionary) -> void:
	for k in cost: _ai_res[k] = _ai_res.get(k, 0) - int(cost[k])

# Công trình kế tiếp cần xây = loại còn THIẾU nhiều nhất so với mục tiêu (ưu tiên nhà lính > cung > monk).
func _ai_next_building(built_by: Dictionary, inprog: Dictionary) -> String:
	var best := ""; var best_def := 0
	for t in AI_BLD_TARGET:
		var have: int = built_by.get(t, []).size() + inprog.get(t, 0)
		var deficit: int = int(AI_BLD_TARGET[t]) - have
		if deficit > best_def: best_def = deficit; best = t
	return best

# Bắt đầu xây 1 công trình: ô sạch quanh castle đỏ (rải ngẫu nhiên), trừ gỗ. Trả Building (thợ giao ở vòng nông dân).
func _ai_start_build(type: String, rc):
	var info: Dictionary = BUILD_INFO[type]
	var ox := rng.randi_range(-11, 11)
	var oy := rng.randi_range(3, 13)            # phía nam castle, ko chắn
	var cell := _fit_cell(rc.cell.x + ox, rc.cell.y + oy, int(info["w"]), int(info["h"]))
	_ai_res["Wood"] = _ai_res.get("Wood", 0) - int(info["cost"])
	var b := make_building(type, cell, 1, false)   # team 1, ĐANG XÂY
	_world.add_child(b)
	_setup_footprint(b, cell, int(info["w"]), int(info["h"]))
	return b

# Lính mua được ở nhà loại t (nhà lính: Warrior/Lancer luân phiên). "" nếu ko đủ tiền.
func _ai_kind_for(t: String) -> String:
	if t == "archer": return "Archer" if _ai_afford(UNIT_INFO["Archer"]["cost"]) else ""
	if t == "monk": return "Monk" if _ai_afford(UNIT_INFO["Monk"]["cost"]) else ""
	var first := "Warrior" if (rng.randi() % 2 == 0) else "Lancer"   # barracks
	var second := "Lancer" if first == "Warrior" else "Warrior"
	if _ai_afford(UNIT_INFO[first]["cost"]): return first
	if _ai_afford(UNIT_INFO[second]["cost"]): return second
	return ""

# Huấn luyện LIÊN TỤC: nông dân tới 20; mỗi NHÀ rảnh (queue rỗng) ra thêm 1 lính, tới trần quân.
func _ai_train_units(rc, built_by: Dictionary, npawns: int, narmy: int) -> void:
	if npawns + _ai_queued_kind("Pawn") < AI_PAWN_TARGET and _ai_afford({"Meat": 5}):
		_ai_pay({"Meat": 5}); rc.enqueue("Pawn", float(UNIT_INFO["Pawn"]["time"]))
	for t in ["barracks", "archer", "monk"]:
		for b in built_by.get(t, []):
			if narmy + _ai_queued() >= AI_ARMY_CAP: return
			if b.queue.size() > 0: continue        # nhà đang bận → bỏ qua (sản xuất song song)
			var kind := _ai_kind_for(t)
			if kind != "":
				_ai_pay(UNIT_INFO[kind]["cost"]); b.enqueue(kind, float(UNIT_INFO[kind]["time"]))

func _ai_queued() -> int:                           # tổng unit đỏ trong hàng đợi
	var n := 0
	for b in get_tree().get_nodes_in_group("building"):
		if is_instance_valid(b) and b.team == 1: n += b.queue.size()
	return n

func _ai_queued_kind(kind: String) -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group("building"):
		if is_instance_valid(b) and b.team == 1: n += b.queue_count(kind)
	return n

# Chọn "nghề" cho nông dân MỚI: loại đang ÍT người làm nhất (còn xây nhà → thiên về GỖ).
func _ai_least_assigned_tool(pawns: Array, need_wood: bool) -> String:
	var cnt := {"Axe": 0, "Pickaxe": 0, "Knife": 0}
	for p in pawns:
		var t = _ai_pawn_tool.get(p.get_instance_id(), "")
		if cnt.has(t): cnt[t] += 1
	var bias := {"Axe": (-1 if need_wood else 0), "Pickaxe": 0, "Knife": 0}
	var best := "Axe"; var bestv := INF
	for t in cnt:
		var v: float = float(cnt[t] + bias[t])
		if v < bestv: bestv = v; best = t
	return best

# Resource gần nhất, ưu tiên đúng công cụ tool; ko có loại đó thì lấy bất kỳ.
func _ai_nearest_resource(pos: Vector2, tool := ""):
	var best = null; var bd := INF
	var any = null; var ad := INF
	for r in get_tree().get_nodes_in_group("resource"):
		if not is_instance_valid(r): continue
		var amt = r.get("amount")
		if amt != null and amt <= 0: continue
		var dd: float = pos.distance_squared_to(r.global_position)
		if dd < ad: ad = dd; any = r
		if tool == "" or str(r.get_meta("tool", "")) == tool:
			if dd < bd: bd = dd; best = r
	return best if best != null else any

# Địch (team 0) gần nhất trong tầm; prefer_pawn=true → ƯU TIÊN nông dân (dân sửa nhà/khai thác).
func _ai_nearest_enemy(pos: Vector2, within_cells: float, prefer_pawn := false):
	var rng2: float = within_cells * within_cells * PPU * PPU
	var bp = null; var bpd := rng2     # nông dân gần nhất
	var bf = null; var bfd := rng2     # lính gần nhất
	for f in get_tree().get_nodes_in_group("fighter"):
		if not is_instance_valid(f) or f.team != 0 or f.is_dead(): continue
		var dd: float = pos.distance_squared_to(f.position)
		if f.kind == "Pawn":
			if dd < bpd: bpd = dd; bp = f
		else:
			if dd < bfd: bfd = dd; bf = f
	if prefer_pawn and bp != null: return bp
	return bf if bf != null else bp

# Menu Debug: các công tắc để TÁCH RIÊNG từng thứ → soi cái nào ăn FPS.
func _build_menu(cl: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(160, 30)
	panel.process_mode = Node.PROCESS_MODE_ALWAYS   # mở từ Settings (đang pause) vẫn bấm được
	panel.z_index = 210
	panel.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	_mk_toggle(vb, "FPS", _show_fps, func(on): _show_fps = on; _apply_debug_flags())
	_mk_toggle(vb, "Tiles", _show_debug, func(on): _show_debug = on; _apply_debug_flags())
	_mk_toggle(vb, "Fog (explored)", _fog_dim_on, func(on): _fog_dim_on = on; _on_fog_toggle())
	_mk_toggle(vb, "Black (unexplored)", _fog_black_on, func(on): _fog_black_on = on; _on_fog_toggle())
	_mk_toggle(vb, "Waves (foam)", _foam_on, func(on): _foam_on = on; _apply_debug_flags())
	cl.add_child(panel)
	_menu = panel

func _mk_toggle(vb: VBoxContainer, txt: String, on: bool, cb: Callable) -> void:
	var c := CheckButton.new()
	c.text = txt
	c.button_pressed = on
	c.add_theme_font_size_override("font_size", 34)
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(cb)
	vb.add_child(c)

# Áp trạng thái toggle lên các node hiện tại (gọi lại sau mỗi build_map vì node bị dựng lại).
# Cây/nhà che lính (lính đứng SAU, trong tán) → làm occluder MỜ đi cho thấy lính.
func _update_occluders(delta: float) -> void:
	var vr := _view_rect()
	for o in get_tree().get_nodes_in_group("occluder"):
		if not is_instance_valid(o) or not o.visible: continue
		if o.has_method("needs_work"):         # NHÀ ko mờ (đã chặn ô sau nhà → lính ko bị khuất) → giữ đặc
			if o.modulate.a < 1.0: o.modulate.a = 1.0
			continue
		var op: Vector2 = o.global_position    # CHÂN cây/nhà
		if not vr.has_point(op): continue       # ngoài khung nhìn → khỏi xét
		var hide := false
		for f in get_tree().get_nodes_in_group("fighter"):
			if not is_instance_valid(f) or not f.visible: continue
			var fp: Vector2 = f.global_position
			# lính đứng SAU (chân cao hơn = y nhỏ hơn) + trong bề ngang + trong tầm cao tán
			if fp.y < op.y and fp.y > op.y - 150.0 and absf(fp.x - op.x) < 42.0:
				hide = true; break
		var tgt: float = 0.4 if hide else 1.0
		o.modulate.a = move_toward(o.modulate.a, tgt, delta * 4.0)

func _fog_active() -> bool: return _fog_dim_on or _fog_black_on

func _apply_debug_flags() -> void:
	_kb = 1.0 if _fog_black_on else 0.0
	_kd = FOG_DIM if _fog_dim_on else 0.0
	if _fps_label != null: _fps_label.visible = _show_fps
	if _dn != null and is_instance_valid(_dn): _dn.visible = _show_debug
	if _fog != null and is_instance_valid(_fog): _fog.visible = _fog_active()
	if _foam_root != null and is_instance_valid(_foam_root): _foam_root.visible = _foam_on

# Đổi toggle sương mù / bóng đen → cập nhật hệ số + vẽ lại TOÀN BỘ fog (vì vùng đen/mờ ko nằm trong _prev_lit).
func _on_fog_toggle() -> void:
	_kb = 1.0 if _fog_black_on else 0.0
	_kd = FOG_DIM if _fog_dim_on else 0.0
	if _fog != null and is_instance_valid(_fog): _fog.visible = _fog_active()
	if not _fog_active():
		_show_all_units()
		return
	_refresh_fog_all()

# Vẽ lại alpha CẢ mảng theo _seenf/_vis hiện tại (chỉ gọi khi đổi toggle — ko phải mỗi frame).
func _refresh_fog_all() -> void:
	if _fog == null or not is_instance_valid(_fog): return
	for i in range(_seenf.size()):
		var sn: float = _seenf[i]
		_fogbytes[i * 4 + 3] = int(((1.0 - sn) * _kb + sn * _kd) * (1.0 - _vis[i]) * 255.0)
	_fog_img.set_data(_fpw, _fph, false, Image.FORMAT_RGBA8, _fogbytes)
	_fog_tex.update(_fog_img)

func _show_all_units() -> void:   # tắt sương → mọi thứ hiện hết + chạy anim lại
	for f in get_tree().get_nodes_in_group("fighter"):
		if is_instance_valid(f): f.visible = true
	for b in get_tree().get_nodes_in_group("building"):
		if is_instance_valid(b): b.visible = true
	for r in get_tree().get_nodes_in_group("resource"):
		if is_instance_valid(r): r.visible = true
	for s in get_tree().get_nodes_in_group("fog_anim"):
		if is_instance_valid(s):
			s.process_mode = Node.PROCESS_MODE_INHERIT
			s.visible = true
			if not s.is_playing(): s.play()

func _mk_btn(cl: CanvasLayer, txt: String, pos: Vector2, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = txt
	btn.add_theme_font_size_override("font_size", 38)
	btn.position = pos
	btn.custom_minimum_size = Vector2(300, 116); btn.size = Vector2(300, 116)
	btn.focus_mode = Control.FOCUS_NONE
	btn.process_mode = Node.PROCESS_MODE_ALWAYS   # vẫn bấm được khi PAUSE (vd "Map mới" sau game over)
	_style_btn(btn)
	btn.pressed.connect(cb)
	cl.add_child(btn)

# Áp nền BigBlueButton cho nút (mọi trạng thái) → nút xanh đồng bộ.
func _style_btn(btn: Button) -> void:
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxTexture.new()
		sb.texture = load(ART + "UI Elements/Buttons/BigBlueButton_Regular.png")
		sb.set_texture_margin_all(40)
		sb.content_margin_left = 34; sb.content_margin_right = 34   # DÀY hơn → chữ ko lòi ra
		sb.content_margin_top = 18; sb.content_margin_bottom = 26
		if st == "pressed" or st == "hover": sb.modulate_color = Color(0.88, 0.88, 0.92)
		btn.add_theme_stylebox_override(st, sb)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.pressed.connect(func(): play_sfx("click"))

func _on_debug() -> void:   # mở/đóng menu toggle
	if _menu != null: _menu.visible = not _menu.visible

func _process(delta: float) -> void:
	if _fps_label != null and _fps_label.visible:
		_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	if _time_label != null:
		if not _match_over and _castle_placed: _match_t += delta   # dừng đếm khi hết trận
		_time_label.text = "%d:%02d" % [int(_match_t) / 60, int(_match_t) % 60]
	_music_fade()
	_update_prod_cards()   # cập nhật số đang tạo + progress bar trong menu sản xuất
	if _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t <= 0.0 and _msg_label != null: _msg_label.visible = false
	if _castle_placed and not _match_over:
		var blue = _castle_of(0); var red = _castle_of(1)
		if blue == null or red == null:           # 1 castle nổ → kết thúc
			_end_match(red == null)               # đỏ mất castle → người chơi THẮNG
		else:
			_ai_tick(delta)                       # AI quân đỏ suy nghĩ
	_update_occluders(delta)   # cây/nhà che lính → mờ đi
	if _fog == null or not is_instance_valid(_fog): return
	_cull_t -= delta
	if _cull_t <= 0.0:
		_cull_t = 0.08
		_cull_view()    # chỉ "gen" (vẽ/anim) vật TRONG khung nhìn → ngoài màn ẩn hết
	if not _fog_active(): return
	_fog_t -= delta
	if _fog_t <= 0.0:
		_fog_t = 0.15
		_update_fog()   # cập nhật sương mù: lính đi tới đâu sáng tới đó, đi qua → mờ lại

# Dựng (lại) toàn bộ map. Mỗi lần gọi: free map cũ, reset state, seed mới → map khác.
func build_map() -> void:
	get_tree().paused = false        # bỏ pause (sau game over / settings) khi dựng map mới
	_close_overlays()                # ẩn SẠCH menu/nền mờ (tránh lớp xám chặn click sau New Game)
	if _gen != null:
		_gen.free()                 # free NGAY (ko queue) → tránh trùng node/nhóm khi dựng lại
	_gen = Node2D.new()
	add_child(_gen)
	_selected = []   # lính cũ đã bị free
	_last_sel_f = null
	_castle_placed = false; _unit_cap = 10   # castle (5) + 1 nhà dân (5)
	_match_over = false; _match_t = 0.0; _ai_tgt = {}; _ai_pawn_tool = {}; _ai_chase_t = {}; _ai_nochase_until = {}; _ai_t = 0.0; _ai_train_t = 3.0; _ai_income_t = 5.0
	_ai_res = {"Wood": 10, "Gold": 0, "Meat": 10}
	if _lose_label != null: _lose_label.add_theme_color_override("font_color", Color.WHITE)
	_build_mode = ""
	if _ghost != null and is_instance_valid(_ghost): _ghost.queue_free()
	_ghost = null
	if _lose_label != null: _lose_label.visible = false
	if _msg_label != null: _msg_label.visible = false
	if _build_panel != null: _build_panel.visible = false
	if _prod_panel != null: _prod_panel.visible = false
	_sel_building = null; _prod_cards = {}
	_res = {"Wood": 10, "Gold": 0, "Meat": 10}   # bắt đầu: 10 gỗ + 10 thịt
	for k in _res_labels: _res_labels[k].text = str(_res[k])

	# reset toàn bộ state
	land = {}; plateau = {}; hmap = TSHeight.new()
	_dbg = []; _cells = {}; _brock = {}
	rng.seed = SEED + _gen_count * 104729   # lần đầu = SEED (ổn định), mỗi lần bấm → seed khác
	_gen_count += 1

	generate_land(-68, 68, -42, 40)   # đảo RỘNG GẤP ĐÔI (so với bản trước)
	carve_lakes()                     # khoét vài HỒ NƯỚC trong đảo
	for c in land.keys():
		hmap.walkable[c] = true   # mọi ô đất đi được (cao nguyên sẽ sửa lại đá=ko)
	_coast_rock = compute_coast_rock()   # ô NƯỚC ngay dưới mép nam đảo → thành VÁCH ĐÁ ven biển
	for c in land.keys():
		if _block_water(c): hmap.walkable[c] = false   # chặn lính ở ô NƯỚC-PHÍA-BẮC (thân lòi lên) / góc (cao nguyên/dốc set lại sau)

	_foam_root = Node2D.new(); _foam_root.z_index = -20
	_gen.add_child(_foam_root); build_foam(_foam_root)

	var ground := build_color_layer(ART + "Terrain/Tileset/Tilemap_color1.png")
	var gl: TileMapLayer = ground[0]; var gsid: int = ground[1]
	gl.z_index = -10; _gen.add_child(gl)
	paint_ground(gl, gsid)
	build_coast(gl, gsid)   # lip mép nam + vách đá đổ xuống biển

	build_plateaus()   # color3 layer + hmap marks + plateau set

	_shadow_root = Node2D.new(); _shadow_root.z_index = -8   # giữa nền (-10) và cao nguyên (-7/-5)
	_gen.add_child(_shadow_root); build_shadows(_shadow_root)

	var world := Node2D.new(); world.y_sort_enabled = true
	_gen.add_child(world)
	_world = world
	scatter_decorations(world)
	_setup_match(world)            # 2 căn cứ: XANH (người chơi) tây, ĐỎ (AI) đông
	_update_unit_hud(); _update_build_panel()

	_setup_fog(-69, -43, 139, 86)   # phủ sương mù toàn hộp map (rộng hơn hộp đất 1 ô)
	_init_camera(world)            # view NHỎ, căn vào quân XANH lúc đầu

	# DEBUG: overlay số index tile (vàng=cao nguyên cỏ, xanh lá=mảnh dốc 40, xanh dương=đá vách, mờ=nền)
	var items: Array = []
	for cell in _cells.keys():
		var e: Dictionary = _cells[cell]
		items.append({"pos": Vector2(cell.x * PPU + 18, cell.y * PPU + 40), "t": str(e["idx"]), "c": e["c"], "s": e["s"]})
	items.append_array(_dbg)   # nhãn phụ khác
	for bc in _brock.keys():   # nhãn back-rock "[..]" ở ĐỈNH ô (y nhỏ), sau fixup → đúng 36/37/38
		items.append({"pos": Vector2(bc.x * PPU + 16, bc.y * PPU + 16), "t": "[" + str(_brock[bc]) + "]", "c": Color(1, 0.55, 0.2), "s": 11})
	_dn = DebugNumbers.new()
	_dn.items = items
	_dn.z_index = 4096
	_dn.visible = _show_debug   # tôn trọng trạng thái nút Debug qua các lần gen map
	_gen.add_child(_dn)
	_dn.queue_redraw()
	_apply_debug_flags()   # áp lại các toggle Debug lên node vừa dựng

	if _CAPTURE:
		await get_tree().create_timer(0.8).timeout
		get_viewport().get_texture().get_image().save_png("res://shot.png")
		get_tree().quit()


# ---------- đảo ----------
func generate_land(bx0: int, bx1: int, by0: int, by1: int) -> void:
	var cx := rng.randf_range(-3.0, 3.0)
	var cy := -1.0 + rng.randf_range(-2.0, 2.0)
	var rx := rng.randf_range(37.0, 44.0)   # đảo rộng gấp đôi
	var ry := rng.randf_range(23.0, 27.0)
	var p1 := rng.randf_range(0.0, TAU); var a1 := rng.randf_range(0.10, 0.16)
	var p2 := rng.randf_range(0.0, TAU); var a2 := rng.randf_range(0.07, 0.12)
	var p3 := rng.randf_range(0.0, TAU); var a3 := rng.randf_range(0.05, 0.09)
	var n1 := 2 + rng.randi() % 2
	var n2 := 3 + rng.randi() % 3
	for x in range(bx0, bx1 + 1):
		for y in range(by0, by1 + 1):
			var dx := (x - cx) / rx; var dy := (y - cy) / ry
			var d := sqrt(dx * dx + dy * dy)
			var th := atan2(y - cy, x - cx)
			var thr := 1.0 + a1 * sin(n1 * th + p1) + a2 * sin(n2 * th + p2) + a3 * sin(th + p3)
			if d <= thr: land[Vector2i(x, y)] = true

func is_land(x: int, y: int) -> bool: return land.has(Vector2i(x, y))

# Khoét vài HỒ NƯỚC trong đảo: bỏ 1 cụm ô khỏi `land` (sâu trong đảo, ko phá mép). Cạnh hồ → ô lip cỏ + foam tự lo.
func carve_lakes() -> void:
	_lakes = {}; _lake_edge = {}
	var xs: Array = land.keys().map(func(c): return c.x)
	var ys: Array = land.keys().map(func(c): return c.y)
	if xs.is_empty(): return
	var minx: int = xs.min(); var maxx: int = xs.max()
	var miny: int = ys.min(); var maxy: int = ys.max()
	var n_lakes := 2 + rng.randi() % 3   # 2..4 hồ
	for _i in range(n_lakes):
		var cx := rng.randi_range(minx + 8, maxx - 8)
		var cy := rng.randi_range(miny + 6, maxy - 6)
		var rx := rng.randf_range(2.5, 4.5); var ry := rng.randf_range(2.0, 3.5)
		var p1 := rng.randf_range(0.0, TAU); var a1 := rng.randf_range(0.15, 0.3)
		var blob: Array = []
		var ok := true
		for x in range(cx - 6, cx + 7):
			for y in range(cy - 6, cy + 7):
				var dx := (x - cx) / rx; var dy := (y - cy) / ry
				var th := atan2(y - cy, x - cx)
				if sqrt(dx * dx + dy * dy) <= 1.0 + a1 * sin(2 * th + p1):
					var c := Vector2i(x, y)
					if not is_land(x, y) or plateau.has(c): ok = false   # chỉ khoét ở đất bằng, ko đè cao nguyên/mép
					blob.append(c)
		if not ok or blob.size() < 5: continue
		for c in blob:
			land.erase(c); _lakes[c] = true
	# ô đất giáp hồ (4 hướng) → để bias bụi cây
	for lk in _lakes.keys():
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = lk + d
			if is_land(nb.x, nb.y): _lake_edge[nb] = true


# ---------- tile layer ----------
func tile_atlas(i: int) -> Vector2i:
	var row := i / 8; var j := i % 8
	return Vector2i((j if j < 4 else j + 1), row)

func build_color_layer(sheet: String) -> Array:
	var ts := TileSet.new(); ts.tile_size = Vector2i(64, 64)
	var src := TileSetAtlasSource.new()
	src.texture = load(sheet); src.texture_region_size = Vector2i(64, 64)
	for ry in range(6):
		for cx in range(9):
			if cx == 4: continue
			src.create_tile(Vector2i(cx, ry))
	var sid := ts.add_source(src)
	var layer := TileMapLayer.new(); layer.tile_set = ts
	return [layer, sid]

func paint_ground(layer: TileMapLayer, sid: int) -> void:
	for cell in land.keys():
		var x: int = cell.x; var y: int = cell.y
		var wN := not is_land(x, y - 1); var wS := not is_land(x, y + 1)
		var wE := not is_land(x + 1, y); var wW := not is_land(x - 1, y)
		var idx := 9
		if wN and wS and wE and wW: idx = 27
		elif wE and wW: idx = (3 if wN else (19 if wS else 11))
		elif wN and wS: idx = (24 if wW else (26 if wE else 25))
		elif wN and wW: idx = 0
		elif wN and wE: idx = 2
		elif wS and wW: idx = 16
		elif wS and wE: idx = 18
		elif wN: idx = 1
		elif wS: idx = 17
		elif wW: idx = 8
		elif wE: idx = 10
		layer.set_cell(cell, sid, tile_atlas(idx))
		dbg(cell, idx, Color(1, 1, 1, 0.4), 9)


# ---------- cao nguyên (color3) ----------
var _back: TileMapLayer       # layer SAU (rock đằng sau bậc thang 32 — quy tắc 3)
var _brock := {}              # back-rock theo ô: cell -> idx (36/37/38) — fixup viền ở cuối
var _stair_cells := {}        # mọi ô THUỘC dốc (để giãn cách: 2 dốc cách ≥1 ô 8-hướng)
var _rock_cells := {}         # ô VÁCH ĐÁ (hàng thấp nhất) — để đổ bóng
var _no_shadow := {}        # ô KO đổ bóng: dốc BẮC + ô MẶT TRÊN 32/35 (chỉ chân dốc 40/43 mới có bóng)
var _coast_rock := {}       # ô NƯỚC ngay dưới mép nam đảo → vẽ thành VÁCH ĐÁ ven biển (đảo nổi lên)
var _grass_cells: Array = []      # ô cỏ (respawn vàng/cừu)
var _interior_cells: Array = []   # ô cỏ trong (respawn cây)
var _grass_set := {}              # tập ô cỏ (cừu lang thang)
var _lakes := {}            # ô NƯỚC trong đảo (hồ); cạnh hồ ưu tiên đặt nhiều BỤI CÂY
var _lake_edge := {}        # ô đất giáp hồ → bias bụi cây

# Ô nước ngay DƯỚI mỗi ô đất giáp biển ở NAM → thành vách đá ven biển.
func compute_coast_rock() -> Dictionary:
	var cr := {}
	for c in land.keys():
		var below := Vector2i(c.x, c.y + 1)
		if not is_land(below.x, below.y) and not _lakes.has(below):   # bờ HỒ ko làm vách đá (chỉ biển nam)
			cr[below] = true
	return cr

# Mép NAM đảo: ô đất giáp biển nam → LIP (cỏ mép) ; ô nước dưới → VÁCH ĐÁ (color1 36/37/38). Đảo nổi trên biển.
func build_coast(layer: TileMapLayer, sid: int) -> void:
	# 1) lip mép nam — viền theo CẢ 2 bên (đá/biển = ko phải đất → cần viền):
	#    trái+phải đều ko-đất → 23 (strip-lip, viền 2 bên); chỉ trái → 20; chỉ phải → 22; ko → 21.
	for c in land.keys():
		if is_land(c.x, c.y + 1): continue
		var lw := not is_land(c.x - 1, c.y)
		var rw := not is_land(c.x + 1, c.y)
		var idx := 21
		if lw and rw: idx = 23
		elif lw: idx = 20
		elif rw: idx = 22
		layer.set_cell(c, sid, tile_atlas(idx))
		dbg(c, idx, Color(1, 1, 1, 0.4), 9)
	# 2) vách đá đổ xuống biển — 9-slice ngang (luật 5: mép trái 36 / phải 38 / giữa 37)
	for r in _coast_rock.keys():
		var l_solid := is_island(r.x - 1, r.y)
		var r_solid := is_island(r.x + 1, r.y)
		var ridx := 37
		if not l_solid: ridx = 36
		elif not r_solid: ridx = 38
		layer.set_cell(r, sid, tile_atlas(ridx))
		dbg(r, ridx, Color(0.6, 0.8, 1.0), 9)

# Bóng đổ: shadow tile làm NỀN ngay PHÍA SAU mỗi ô VÁCH ĐÁ (nam) + ô DỐC (chân dốc đông/tây). KO cho dốc BẮC.
func build_shadows(parent: Node2D) -> void:
	var tex: Texture2D = load(ART + "Terrain/Tileset/Shadow.png")
	var cells := {}
	for r in _rock_cells.keys(): cells[r] = true     # vách núi (nam)
	for r in hmap.ramp.keys(): cells[r] = true       # dốc (nam/đông/tây)
	# mép TRÁI & PHẢI cao nguyên (cạnh DỌC giáp đất thấp đông/tây) → cũng đổ bóng. BỎ ô mép BẮC (rìa bắc ko bóng).
	for c in plateau.keys():
		if not plateau.has(Vector2i(c.x, c.y - 1)): continue   # ô mép BẮC (trên ko phải cao nguyên) → ko bóng
		var w_low := is_land(c.x - 1, c.y) and not plateau.has(Vector2i(c.x - 1, c.y))
		var e_low := is_land(c.x + 1, c.y) and not plateau.has(Vector2i(c.x + 1, c.y))
		if w_low or e_low: cells[c] = true
	for r in _no_shadow.keys(): cells.erase(r)     # bỏ dốc BẮC + mặt trên 32/35 (chỉ chân dốc có bóng)
	for c in cells.keys():
		var spr := Sprite2D.new()
		spr.texture = tex                            # native, scale 1.0, alpha 1.0
		spr.position = Vector2(c.x + 0.5, c.y + 0.5) * PPU   # NGAY ô vách/dốc (ko dời)
		parent.add_child(spr)

# RULE: dốc mới phải cách MỌI dốc đã đặt ≥1 ô (8 hướng). True nếu KO ô nào của dốc mới chạm 3x3 dốc cũ.
func stair_spacing_ok(cells: Array) -> bool:
	for c in cells:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if _stair_cells.has(Vector2i(c.x + dx, c.y + dy)): return false
	return true

func register_stair(cells: Array) -> void:
	for c in cells: _stair_cells[c] = true
var _bsid: int

func build_plateaus() -> void:
	var bres := build_color_layer(ART + "Terrain/Tileset/Tilemap_color3.png")
	_back = bres[0]; _bsid = bres[1]; _back.z_index = -7; _gen.add_child(_back)
	var res := build_color_layer(ART + "Terrain/Tileset/Tilemap_color3.png")
	var layer: TileMapLayer = res[0]; var sid: int = res[1]; layer.z_index = -5; _gen.add_child(layer)
	_stair_cells = {}; _rock_cells = {}; _no_shadow = {}
	var made := 0; var tries := 0
	while made < 11 and tries < 2200:   # ÍT cao nguyên hơn 1 chút (so với map rộng gấp đôi)
		tries += 1
		var H := gen_blob()
		if H.is_empty(): continue
		paint_plateau(layer, sid, H)
		made += 1
	# GUARD luật mới: đá cạnh CHÂN DỐC (phải-của-40 / trái-của-43) — 40/43 là nửa cỏ nửa đá, mặt đá của nó
	# đã có viền sẵn → đá kế bên KO được viền hướng vào dốc (36 phải-của-40, 38 trái-của-43) → đổi thành 37.
	for cell in _cells.keys():
		var idx: int = int(_cells[cell]["idx"])
		if idx == 40:
			var rc := Vector2i(cell.x + 1, cell.y)
			if _cells.has(rc) and int(_cells[rc]["idx"]) == 36:
				layer.set_cell(rc, sid, tile_atlas(37)); _cells[rc]["idx"] = 37
		elif idx == 43:
			var lc := Vector2i(cell.x - 1, cell.y)
			if _cells.has(lc) and int(_cells[lc]["idx"]) == 38:
				layer.set_cell(lc, sid, tile_atlas(37)); _cells[lc]["idx"] = 37
	# GUARD back-rock (sau lưng 32/35): 36 có viền TRÁI / 38 có viền PHẢI. Nếu ô cạnh phía đó là CAO NGUYÊN/ĐÁ/DỐC
	# (plateau, vd ô 40 của dốc đông/tây) → đá cạnh đá, ko được viền giữa → đổi back-rock thành 37 (khử "khe").
	for bc in _brock.keys():
		var v: int = _brock[bc]
		if v == 36 and plateau.has(Vector2i(bc.x - 1, bc.y)):
			_back.set_cell(bc, _bsid, tile_atlas(37)); _brock[bc] = 37
		elif v == 38 and plateau.has(Vector2i(bc.x + 1, bc.y)):
			_back.set_cell(bc, _bsid, tile_atlas(37)); _brock[bc] = 37

# Sinh 1 cao nguyên HÌNH TỰ NHIÊN (blob gợn sóng), làm MƯỢT. {} nếu ko hợp lệ.
func gen_blob() -> Dictionary:
	var cx := rng.randi_range(-37, 37); var cy := rng.randi_range(-28, 20)
	var rx := rng.randf_range(2.8, 4.4); var ry := rng.randf_range(2.2, 3.2)
	var p1 := rng.randf_range(0.0, TAU); var a1 := rng.randf_range(0.15, 0.32)
	var p2 := rng.randf_range(0.0, TAU); var a2 := rng.randf_range(0.08, 0.18)
	var n2 := 3 + rng.randi() % 2
	var H := {}
	for x in range(cx - 6, cx + 7):
		for y in range(cy - 6, cy + 7):
			var dx := (x - cx) / rx; var dy := (y - cy) / ry
			var th := atan2(y - cy, x - cx)
			var thr := 1.0 + a1 * sin(2 * th + p1) + a2 * sin(n2 * th + p2)
			if sqrt(dx * dx + dy * dy) <= thr: H[Vector2i(x, y)] = true
	# LÀM MƯỢT: bỏ ô 1-ô-RỘNG/CAO hoặc <2 hàng xóm → hết gai/cột-đơn (ko cần strip 7/15/23 → đúng luật 1)
	for _p in range(3):
		var rm: Array = []
		for c in H.keys():
			var hn := H.has(Vector2i(c.x, c.y - 1)); var hs := H.has(Vector2i(c.x, c.y + 1))
			var he := H.has(Vector2i(c.x + 1, c.y)); var hw := H.has(Vector2i(c.x - 1, c.y))
			if (not hw and not he) or (not hn and not hs) or (int(hn) + int(hs) + int(he) + int(hw) < 2):
				rm.append(c)
		for c in rm: H.erase(c)
	if H.size() < 9: return {}
	for c in H.keys():
		if not is_land(c.x, c.y): return {}
		# QUY TẮC 6: cách cao nguyên KHÁC ≥3 ô (quét 2-ring) → luôn có hành lang đi giữa, ko sát nhau
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				if plateau.has(Vector2i(c.x + dx, c.y + dy)): return {}
		var below := Vector2i(c.x, c.y + 1)
		if not H.has(below):
			if not is_land(below.x, below.y): return {}
			if not is_land(c.x, c.y + 2): return {}
	# bắt buộc có ÍT NHẤT 1 chỗ đặt stairs hợp lệ (đủ luật) → ko cao nguyên nào thiếu lối lên
	var rk := south_rock(H)
	if stair_spots(H, rk).is_empty(): return {}
	# QUY TẮC 7: thêm blob này KHÔNG được chia cắt đất thấp (lính ko bị kẹt, vẫn đi vòng ra được)
	if not ground_connected_after(H, rk): return {}
	return H

# Đất THẤP đi được sau khi thêm blob (H + vách) có còn LIỀN MẠCH (1 vùng) không? (flood 4-hướng)
func ground_connected_after(H: Dictionary, rock: Dictionary) -> bool:
	var blocked := {}
	for c in plateau.keys(): blocked[c] = true
	for c in H.keys(): blocked[c] = true
	for r in rock.keys(): blocked[r] = true
	var total := 0
	var start: Variant = null
	for c in land.keys():
		if not blocked.has(c):
			total += 1
			if start == null: start = c
	if start == null: return false
	var seen := {start: true}
	var q: Array = [start]
	var head := 0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while head < q.size():
		var cur: Vector2i = q[head]; head += 1
		for d in dirs:
			var nb: Vector2i = cur + d
			if seen.has(nb) or blocked.has(nb) or not land.has(nb): continue
			seen[nb] = true; q.append(nb)
	return seen.size() == total

# Ô VÁCH ĐÁ = ô ngay dưới mỗi ô NAM (south-facing) của H.
func south_rock(H: Dictionary) -> Dictionary:
	var r := {}
	for c in H.keys():
		if not H.has(Vector2i(c.x, c.y + 1)): r[Vector2i(c.x, c.y + 1)] = true
	return r

# Gom các ô đá thành RUN (đoạn ngang liền nhau, cùng y) → mỗi run xét đặt 1 dốc ở 1 đầu.
func rock_runs(rock: Dictionary) -> Array:
	var runs: Array = []
	var seen := {}
	for r in rock.keys():
		if seen.has(r): continue
		var x0: int = r.x
		while rock.has(Vector2i(x0 - 1, r.y)): x0 -= 1
		var run: Array = []
		var x: int = x0
		while rock.has(Vector2i(x, r.y)):
			var cc := Vector2i(x, r.y)
			run.append(cc); seen[cc] = true; x += 1
		runs.append(run)
	return runs

# 1 đầu run đặt được STAIRS? L=đầu trái (trái=đất), R=đầu phải (phải=đất); dưới=đất, trên (lip) thuộc H.
func _stair_ok(H: Dictionary, rock: Dictionary, r: Vector2i, side: String) -> bool:
	var outside := Vector2i(r.x - 1, r.y) if side == "L" else Vector2i(r.x + 1, r.y)
	if H.has(outside) or rock.has(outside) or not is_land(outside.x, outside.y): return false
	var bel := Vector2i(r.x, r.y + 1)
	if rock.has(bel) or plateau.has(bel) or not is_land(bel.x, bel.y): return false
	if not H.has(Vector2i(r.x, r.y - 1)): return false
	return true

# Chọn 1 dốc cho run; XEN KẼ trái/phải (theo chỉ số run) để ĐA DẠNG dùng cả 32/40 (trái) lẫn 35/43 (phải).
func _pick_stair(H: Dictionary, rock: Dictionary, run: Array, prefer: String) -> Variant:
	var lok := _stair_ok(H, rock, run[0], "L")
	var rok := _stair_ok(H, rock, run[run.size() - 1], "R")
	if prefer == "R":
		if rok: return {"r": run[run.size() - 1], "side": "R"}
		if lok: return {"r": run[0], "side": "L"}
	else:
		if lok: return {"r": run[0], "side": "L"}
		if rok: return {"r": run[run.size() - 1], "side": "R"}
	return null

# Danh sách dốc của cả cao nguyên (mỗi run ≥2 ô → 1 dốc, xen kẽ L/R cho đa dạng).
func stair_spots(H: Dictionary, rock: Dictionary) -> Array:
	var spots: Array = []
	var runs := rock_runs(rock)
	for i in range(runs.size()):
		var run: Array = runs[i]
		if run.size() < 2: continue
		var prefer := "R" if (i % 2 == 1) else "L"
		var sp = _pick_stair(H, rock, run, prefer)
		if sp != null: spots.append(sp)
	return spots

func paint_plateau(layer: TileMapLayer, sid: int, H: Dictionary) -> void:
	# 1) MẶT CỎ CAO — autotile 9-slice color3 (luật 1: viền chỉ ở mép giáp color1/đá)
	for c in H.keys():
		var idx := elev_tile(H, c)
		layer.set_cell(c, sid, tile_atlas(idx))
		dbg(c, idx, Color(1, 0.9, 0.15), 13)
		hmap.level[c] = 1; hmap.walkable[c] = true; plateau[c] = true
	# 2) VÁCH ĐÁ dưới mọi ô NAM (south-facing); rock 9-slice ngang
	var rock := south_rock(H)
	for r in rock.keys():
		# QUY TẮC 5: đá có mép (36 trái / 38 phải) CHỈ khi cạnh nó là ĐẤT (đá tự lo viền);
		# nếu cạnh là CỎ (cỏ đã có mép) hoặc ĐÁ (nối tiếp) → 37 (giữa, ko mép) → tránh 2 viền chồng.
		var lft := Vector2i(r.x - 1, r.y); var rgt := Vector2i(r.x + 1, r.y)
		var left_ground := not rock.has(lft) and not H.has(lft)
		var right_ground := not rock.has(rgt) and not H.has(rgt)
		var ridx := 37
		if left_ground: ridx = 36
		elif right_ground: ridx = 38
		layer.set_cell(r, sid, tile_atlas(ridx))
		dbg(r, ridx, Color(0.6, 0.8, 1.0), 13)
		hmap.walkable[r] = false; plateau[r] = true; _rock_cells[r] = true
	# 3) STAIRS — xen kẽ TRÁI (32/40) và PHẢI (35/43) cho đa dạng (luật 2/3/4, gương đối xứng)
	for sp in stair_spots(H, rock):
		var r: Vector2i = sp["r"]; var side: String = sp["side"]
		var top := Vector2i(r.x, r.y - 1)                        # lip ngay trên (thuộc H)
		if not stair_spacing_ok([r, top]): continue              # RULE: cách dốc khác ≥1 ô (8 hướng)
		register_stair([r, top])
		hmap.level[r] = 1; hmap.ramp[r] = true; hmap.walkable[r] = true
		if side == "L":
			layer.set_cell(r, sid, tile_atlas(40))               # mảnh DƯỚI dốc TRÁI
			dbg(r, 40, Color(0.3, 1, 0.3), 13)
			layer.set_cell(top, sid, tile_atlas(32))             # mảnh TRÊN (đè lip)
			dbg(top, 32, Color(1, 0.9, 0.15), 13)
		else:
			layer.set_cell(r, sid, tile_atlas(43))               # mảnh DƯỚI dốc PHẢI
			dbg(r, 43, Color(0.3, 1, 0.3), 13)
			layer.set_cell(top, sid, tile_atlas(35))             # mảnh TRÊN (đè lip)
			dbg(top, 35, Color(1, 0.9, 0.15), 13)
		var above := Vector2i(top.x, top.y - 1)
		if H.has(above):                                         # luật 3: trên 32/35 cùng màu → back-rock
			var top_same := H.has(Vector2i(above.x, above.y - 1))
			var back_rock: int
			var idx4: int
			if side == "L":
				# back-rock (luật 1): 36 (mép trái) CHỈ khi TRÁI nó là ĐẤT THẬT; ngược lại 37 (giữa) → ko "2 ô 36 cạnh nhau"
				var lc := Vector2i(r.x - 1, r.y - 1)
				back_rock = 36 if (not H.has(lc) and not rock.has(lc)) else 37
				# rule-4: TRÊN cùng màu → lip(20/21), khác → cliff-top(28/29); TRÁI cỏ → mid(21/29, ko tua), TRÁI đất → left(20/28, tua trái)
				var left_solid := H.has(Vector2i(above.x - 1, above.y))
				if left_solid: idx4 = 21 if top_same else 29
				else: idx4 = 20 if top_same else 28
			else:
				# GƯƠNG: back-rock 38 (mép phải) CHỈ khi PHẢI nó là ĐẤT THẬT; ngược lại 37
				var rc := Vector2i(r.x + 1, r.y - 1)
				back_rock = 38 if (not H.has(rc) and not rock.has(rc)) else 37
				# rule-4 gương: PHẢI cỏ → mid(21/29, ko tua), PHẢI đất → right(22/30, tua phải)
				var right_solid := H.has(Vector2i(above.x + 1, above.y))
				if right_solid: idx4 = 21 if top_same else 29
				else: idx4 = 22 if top_same else 30
			_back.set_cell(top, _bsid, tile_atlas(back_rock))
			_brock[top] = back_rock   # nhớ để fixup viền + sinh label ở cuối (sau khi mọi dốc đặt xong)
			layer.set_cell(above, sid, tile_atlas(idx4))
			dbg(above, idx4, Color(1, 0.9, 0.15), 13)
	# 4) DỐC KHUẤT phía BẮC — 1 tile lẻ 32/35 nhúng vào MÉP BẮC (leo từ phía sau/bắc, nên "khuất")
	#    32: bên PHẢI là cỏ mép bắc 5/6 ; 35: bên TRÁI là cỏ mép bắc 4/5 (đối xứng gương)
	var north_done := false
	for c in H.keys():
		if north_done: break
		if hmap.ramp.has(c): continue                            # đừng đè lên dốc đã đặt
		if H.has(Vector2i(c.x, c.y - 1)): continue               # phải là ô MÉP BẮC (trên ko phải H)
		var nb := Vector2i(c.x, c.y - 1)                         # ô ngay phía bắc = lối vào từ phía sau
		if not is_land(nb.x, nb.y) or plateau.has(nb): continue
		var rgt := Vector2i(c.x + 1, c.y); var lft := Vector2i(c.x - 1, c.y)
		var r_north := H.has(rgt) and not H.has(Vector2i(rgt.x, rgt.y - 1))
		var l_north := H.has(lft) and not H.has(Vector2i(lft.x, lft.y - 1))
		var below := Vector2i(c.x, c.y + 1)
		if hmap.ramp.has(below): continue                        # đừng đè dốc khác ở ô dưới
		if not stair_spacing_ok([c]): continue                   # RULE: cách dốc khác ≥1 ô (8 hướng)
		# RULE: TRÁI của 32 / PHẢI của 35 KO được là cỏ cùng màu (color3=H) → dốc nằm ở ĐẦU mép (cạnh đất thấp)
		if r_north and not H.has(lft) and (elev_tile(H, rgt) == 5 or elev_tile(H, rgt) == 6):
			layer.set_cell(c, sid, tile_atlas(32))
			dbg(c, 32, Color(0.3, 1, 0.3), 13)
			hmap.level[c] = 1; hmap.ramp[c] = true; hmap.walkable[c] = true; north_done = true
		elif l_north and not H.has(rgt) and (elev_tile(H, lft) == 4 or elev_tile(H, lft) == 5):
			layer.set_cell(c, sid, tile_atlas(35))
			dbg(c, 35, Color(0.3, 1, 0.3), 13)
			hmap.level[c] = 1; hmap.ramp[c] = true; hmap.walkable[c] = true; north_done = true
		if north_done:
			register_stair([c]); _no_shadow[c] = true   # đánh dấu dốc BẮC → ko đổ bóng
			# KO lót sau 32/35 — phía TRÊN phải TRONG SUỐT (lối xuống đất). Tránh "ô sáng" bằng RULE giãn cách dốc.
			# DƯỚI 32/35 phải có VIỀN (luật mới): 5 = mép cỏ (còn cao nguyên ở dưới) / 29 = cliff-top (ô này cũng là mép nam trên vách)
			if H.has(below):
				var bidx := north_under(H, below)
				layer.set_cell(below, sid, tile_atlas(bidx))
				# viền 5/29 trong suốt ~2 hàng mép trên → lót CỎ ĐẶC (13) ở _back để mép hiện cỏ, ko lộ tile nền color1
				_back.set_cell(below, _bsid, tile_atlas(13))
				dbg(below, bidx, Color(1, 0.9, 0.15), 13)
	# 5) dốc ĐÔNG & TÂY — LÒI RA NGOÀI, theo luật cũ: dốc 2 tile (32+40 / 35+43) đặt lên ĐẤT THẤP ngoài mép.
	#    Bỏ viền ở mặt giáp cao nguyên (ô mép thành 13, ko viền). TÂY = 32/40 (trái), ĐÔNG = 35/43 (phải).
	var west_done := false; var east_done := false
	for c in H.keys():
		if west_done and east_done: break
		if not H.has(Vector2i(c.x, c.y - 1)) or not H.has(Vector2i(c.x, c.y + 1)): continue  # ô mép HÔNG giữa (trên+dưới là H)
		var w := Vector2i(c.x - 1, c.y); var e := Vector2i(c.x + 1, c.y)
		var wb := Vector2i(w.x, w.y + 1); var eb := Vector2i(e.x, e.y + 1)   # ô DƯỚI cho 40/43
		var w_ok := not H.has(w) and is_land(w.x, w.y) and not plateau.has(w) and not hmap.ramp.has(w) \
			and is_land(wb.x, wb.y) and not plateau.has(wb) and not hmap.ramp.has(wb) and stair_spacing_ok([w, wb, c])
		var e_ok := not H.has(e) and is_land(e.x, e.y) and not plateau.has(e) and not hmap.ramp.has(e) \
			and is_land(eb.x, eb.y) and not plateau.has(eb) and not hmap.ramp.has(eb) and stair_spacing_ok([e, eb, c])
		if not west_done and w_ok and H.has(e):                  # mép TÂY: đặt 32 (trên) + 40 (dưới) Ở Ô TÂY, nhô ra
			layer.set_cell(w, sid, tile_atlas(32)); dbg(w, 32, Color(0.3, 1, 0.3), 13)
			layer.set_cell(wb, sid, tile_atlas(40)); dbg(wb, 40, Color(0.3, 1, 0.3), 13)
			layer.set_cell(c, sid, tile_atlas(13)); dbg(c, 13, Color(1, 0.9, 0.15), 13)   # bỏ viền PHẢI-của-32 (mặt cao nguyên)
			for cc in [w, wb]:
				hmap.level[cc] = 1; hmap.ramp[cc] = true; hmap.walkable[cc] = true; plateau[cc] = true
			_no_shadow[w] = true   # mặt trên 32 ko bóng (chỉ chân dốc 40 = wb có bóng)
			register_stair([w, wb, c]); west_done = true
		elif not east_done and e_ok and H.has(w):                # mép ĐÔNG: đặt 35 (trên) + 43 (dưới) Ở Ô ĐÔNG, nhô ra
			layer.set_cell(e, sid, tile_atlas(35)); dbg(e, 35, Color(0.3, 1, 0.3), 13)
			layer.set_cell(eb, sid, tile_atlas(43)); dbg(eb, 43, Color(0.3, 1, 0.3), 13)
			layer.set_cell(c, sid, tile_atlas(13)); dbg(c, 13, Color(1, 0.9, 0.15), 13)   # bỏ viền TRÁI-của-35 (mặt cao nguyên)
			for cc in [e, eb]:
				hmap.level[cc] = 1; hmap.ramp[cc] = true; hmap.walkable[cc] = true; plateau[cc] = true
			_no_shadow[e] = true   # mặt trên 35 ko bóng (chỉ chân dốc 43 = eb có bóng)
			register_stair([e, eb, c]); east_done = true

# 9-slice color3 cho ô cao nguyên c theo 4 hàng xóm (bắc=-y). Lip 20/21/22 ở mép NAM.
func elev_tile(H: Dictionary, c: Vector2i) -> int:
	var hN := H.has(Vector2i(c.x, c.y - 1))
	var hS := H.has(Vector2i(c.x, c.y + 1))
	var hE := H.has(Vector2i(c.x + 1, c.y))
	var hW := H.has(Vector2i(c.x - 1, c.y))
	if not hW and not hE: return 7 if not hN else (23 if not hS else 15)   # cột 1-ô: strip dọc
	if not hN and not hW: return 4
	if not hN and not hE: return 6
	if not hN: return 5
	if not hS and not hW: return 20            # lip góc nam-tây
	if not hS and not hE: return 22            # lip góc nam-đông
	if not hS: return 21                       # lip nam
	if not hW: return 12
	if not hE: return 14
	return 13

# Viền cho ô NGAY DƯỚI dốc bắc 32/35 (luật mới). Còn cỏ ở dưới → mép cỏ 5 (góc 4/6); là mép nam trên vách → cliff-top 29 (góc 28/30).
func north_under(H: Dictionary, d: Vector2i) -> int:
	var hW := H.has(Vector2i(d.x - 1, d.y))
	var hE := H.has(Vector2i(d.x + 1, d.y))
	var hS := H.has(Vector2i(d.x, d.y + 1))
	if hS:
		if not hW: return 4
		if not hE: return 6
		return 5
	if not hW: return 28
	if not hE: return 30
	return 29


# Đảo = đất + VÁCH ĐÁ ven biển (đá nhô xuống biển tính như phần đảo cho foam)
func is_island(x: int, y: int) -> bool:
	return is_land(x, y) or _coast_rock.has(Vector2i(x, y))

# ---------- foam ----------
func build_foam(root: Node2D) -> void:
	var frames := make_frames(load(ART + "Terrain/Tileset/Water Foam.png"), 192, 192, 8.0)
	var idx := 0
	var isle := {}
	for c in land.keys(): isle[c] = true
	for c in _coast_rock.keys(): isle[c] = true
	for cell in isle.keys():
		var x: int = cell.x; var y: int = cell.y
		if is_island(x + 1, y) and is_island(x - 1, y) and is_island(x, y + 1) and is_island(x, y - 1):
			continue
		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = frames; spr.animation = "a"
		spr.frame = (idx * 3) % 16; spr.play()
		spr.position = Vector2(x + 0.5, y + 0.5) * PPU
		spr.add_to_group("fog_anim")   # cull theo sương: chỉ chạy anim khi đang SÁNG
		root.add_child(spr); idx += 1


# ---------- cây + bụi + đá + cừu + lính ----------
func _shuffle(arr: Array) -> void:   # Fisher-Yates dùng rng có seed → tái lập theo map
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = arr[i]; arr[i] = arr[j]; arr[j] = tmp

# Ô SÁT cao nguyên (chính nó hoặc 8 ô quanh thuộc plateau) = ranh giới → KO đặt vật ở đây.
func near_plateau(c: Vector2i) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if plateau.has(Vector2i(c.x + dx, c.y + dy)): return true
	return false

# CẢ footprint nhà (rộng foot, sau hrows hàng) phải nằm trọn trên đồng bằng phẳng:
# đất + đi-được + KO sát cao nguyên/ranh giới + KO ven nước (ko đè cao nguyên/đường viền).
func _footprint_clear(c: Vector2i, foot: int, hrows: int) -> bool:
	for dy in range(-(hrows - 1), 2):              # cả thân sau + 1 hàng trước (chỗ đứng/cửa)
		for dx in range(-foot, foot + 1):
			var cc := Vector2i(c.x + dx, c.y + dy)
			if not is_land(cc.x, cc.y): return false
			if not hmap.walkable.get(cc, false): return false
			if near_plateau(cc) or _coastal(cc): return false
	return true

# Tìm ô ĐẶT NHÀ gần (px,py) mà CẢ footprint sạch (ko đè cao nguyên/đồng bằng lẫn lộn, ko đè viền).
func _fit_cell(px: int, py: int, w: int, h: int) -> Vector2i:
	var foot: int = maxi(0, int((float(w) / PPU - 1.0) / 2.0))
	var hrows: int = clampi(int(float(h) / PPU) - 1, 1, 3)
	for r in range(0, 40):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r: continue   # chỉ duyệt vòng ngoài bán kính r
				var c := Vector2i(px + dx, py + dy)
				if _footprint_clear(c, foot, hrows): return c
	return nearest_free(px, py)                      # fallback: ít nhất ô tâm hợp lệ

# Ô VEN NƯỚC (có ít nhất 1 cạnh 4-hướng giáp nước) — dùng để KO đặt VẬT (vật lòi mọi phía đều xấu).
func _coastal(c: Vector2i) -> bool:
	return not (is_island(c.x + 1, c.y) and is_island(c.x - 1, c.y) and is_island(c.x, c.y + 1) and is_island(c.x, c.y - 1))

# Ô CHẶN lính: chỉ chặn Ô GÓC (≥2 cạnh giáp nước, ô grass mỏng). Ô mép 1-cạnh vẫn đi được —
# lính dừng GIỮA ô (command_move snap về tâm) nên thân nằm gọn, ko lòi.
func _block_water(c: Vector2i) -> bool:
	var n := int(not is_island(c.x + 1, c.y)) + int(not is_island(c.x - 1, c.y))
	n += int(not is_island(c.x, c.y + 1)) + int(not is_island(c.x, c.y - 1))
	return n >= 2

func scatter_decorations(world: Node2D) -> void:
	var grass: Array = []        # ô cỏ đất, KHÔNG sát cao nguyên & KHÔNG ven nước
	var interior: Array = []     # cỏ + 4 hàng xóm đất (cho CÂY — ko lòi ra biển)
	for cell in land.keys():
		if near_plateau(cell) or _coastal(cell): continue   # bỏ ô cao nguyên/ranh giới + ven nước
		grass.append(cell)
		var x: int = cell.x; var y: int = cell.y
		if is_land(x + 1, y) and is_land(x - 1, y) and is_land(x, y + 1) and is_land(x, y - 1):
			interior.append(cell)
	_shuffle(grass); _shuffle(interior)
	var grass_set := {}
	for c in grass: grass_set[c] = true
	var interior_set := {}
	for c in interior: interior_set[c] = true
	_grass_cells = grass; _interior_cells = interior; _grass_set = grass_set   # lưu để RESPAWN resource
	var used := {}
	# CÂY mọc thành CỤM (rừng): mỗi cụm 1 LOẠI cây, gom quanh 1 tâm. Ưu tiên ô interior.
	var tree_target := 75
	var tcount := 0
	for center in interior:
		if tcount >= tree_target: break
		if used.has(center): continue
		var ttype := rng.randi() % 4              # cả cụm CÙNG loại cây
		var gsize := 3 + rng.randi() % 6          # 3..8 cây / cụm
		var placed := 0
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				if placed >= gsize: break
				var c := Vector2i(center.x + dx, center.y + dy)
				if used.has(c) or not interior_set.has(c): continue
				if rng.randf() > 0.72: continue   # cụm rậm nhưng còn lỗ hổng (tự nhiên)
				used[c] = true
				var t := make_tree(c, ttype); _tag_res(t, "Axe"); world.add_child(t)
				hmap.walkable[c] = false
				placed += 1; tcount += 1
	# BỤI quanh HỒ (nhiều bụi cạnh hồ nước)
	for c in _lake_edge.keys():
		if used.has(c) or near_plateau(c): continue
		if rng.randf() < 0.7:
			used[c] = true; world.add_child(make_bush(c))
	# VÀNG (Pickaxe) / NHÀ (Hammer) / CỪU (Knife) / BỤI / ĐÁ từ ô cỏ còn trống
	var quota := {"gold": 34, "sheep": 26, "bush": 36, "rock": 44}   # KHÔNG rải nhà dân lẻ (chỉ nhà của 2 căn cứ)
	var order := ["gold", "sheep", "bush", "rock"]
	var oi := 0
	for c in grass:
		if used.has(c): continue
		var tries := 0
		while tries < order.size() and quota[order[oi % order.size()]] <= 0:
			oi += 1; tries += 1
		var kind: String = order[oi % order.size()]
		if quota[kind] <= 0: break
		used[c] = true; quota[kind] -= 1; oi += 1
		match kind:
			"bush":
				var bsh := make_bush(c); bsh.add_to_group("clearable"); world.add_child(bsh)
			"rock":
				var rk := make_rock(c); rk.add_to_group("clearable"); world.add_child(rk)
			"gold":
				var g := make_gold(c); _tag_res(g, "Pickaxe"); world.add_child(g)
				hmap.walkable[c] = false   # VÀNG = vật cản
			"house":
				var h := make_house(c); world.add_child(h)   # nhà dân rải rác = trang trí (ko phải depot)
				hmap.walkable[c] = false   # NHÀ = vật cản
			"sheep":
				var s := Sheep.new()
				s.position = Vector2(c.x + 0.5, c.y + 0.5) * PPU
				s.builder = self
				_tag_res(s, "Knife"); s.add_to_group("clearable"); world.add_child(s)
				s.setup(grass_set, SEED + c.x * 7 + c.y * 31)

func _tag_res(node: Node, tool: String) -> void:   # đánh dấu resource + công cụ để nông dân tới lấy
	node.add_to_group("resource"); node.set_meta("tool", tool)

func _make_fighter(world: Node2D, team: int, color: String, type: String, cell: Vector2i) -> Fighter:
	var f := Fighter.new()
	f.position = Vector2(cell.x + 0.5, cell.y + 0.5) * PPU
	f.builder = self            # để nông dân giao hàng cộng resource
	world.add_child(f)
	f.setup(team, color, type, hmap)
	f.manual = true   # XANH: người chơi ra lệnh; ĐỎ: AI ra lệnh (cùng API command_*)
	f.ghost = (team == 1 and type == "Pawn")   # nông dân AI đi XUYÊN qua nhà (đỡ kẹt)
	return f

func nearest_free(px: int, py: int) -> Vector2i:
	for r in range(0, 30):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if r > 0 and abs(dx) != r and abs(dy) != r: continue
				var c := Vector2i(px + dx, py + dy)
				if is_land(c.x, c.y) and not near_plateau(c) and not _coastal(c) and hmap.walkable.get(c, false): return c   # né ranh giới/mép nước/vật cản
	return Vector2i(px, py)


# CÂY: 4 loại (Tree1/2 = 192x256, Tree3/4 = 192x192), 8 frame SWAY, lệch frame đầu cho ko đồng bộ.
func make_tree(cell: Vector2i, type_idx := -1) -> Node2D:
	var types := [["Tree1", 256], ["Tree2", 256], ["Tree3", 192], ["Tree4", 192]]
	var ti: int = type_idx if type_idx >= 0 else rng.randi() % types.size()
	var t: Array = types[ti]
	var fh: int = t[1]
	var tex: Texture2D = load(ART + "Pawn and Resources/Wood/Trees/%s.png" % t[0])
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = make_frames(tex, 192, fh, 8.0)
	spr.animation = "a"; spr.frame = rng.randi() % 8; spr.play()
	spr.offset = Vector2(0, feet_offset(tex, 192, fh))
	spr.add_to_group("fog_anim")
	var node := _res_wrap(spr, cell); node.add_to_group("occluder"); node.add_to_group("clearable")   # đứng sau cây → cây mờ
	# kinh tế: cây có 50 GỖ; hết → còn GỐC CÂY (Stump cùng số)
	node.res_kind = "wood"; node.amount = 50; node.hmap = hmap; node.cell = cell; node.builder = self
	var st_tex: Texture2D = load(ART + "Pawn and Resources/Wood/Trees/Stump %d.png" % (ti + 1))
	node.stump_tex = st_tex
	node.stump_off = feet_offset(st_tex, st_tex.get_width(), st_tex.get_height())
	return node

# Bọc visual vào ResNode (có hit() rung/chớp) tại ô cell.
func _res_wrap(spr: Node2D, cell: Vector2i) -> ResNode:
	var node := ResNode.new()
	node.position = Vector2(cell.x + 0.5, cell.y + 0.5) * PPU
	node.set_visual(spr)
	return node

# BỤI CÂY: 4 loại (128x128), 8 frame animation (đung đưa).
func make_bush(cell: Vector2i) -> Node2D:
	var tex: Texture2D = load(ART + "Terrain/Decorations/Bushes/Bush %d.png" % (1 + rng.randi() % 4))
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = make_frames(tex, 128, 128, 7.0)
	spr.animation = "a"; spr.frame = rng.randi() % 8; spr.play()
	spr.offset = Vector2(0, feet_offset(tex, 128, 128))
	spr.position = Vector2(cell.x + 0.5, cell.y + 0.5) * PPU
	spr.add_to_group("fog_anim")
	return spr

# ĐÁ: 4 loại (64x64, tĩnh).
func make_rock(cell: Vector2i) -> Node2D:
	var tex: Texture2D = load(ART + "Terrain/Decorations/Rocks/Rock%d.png" % (1 + rng.randi() % 4))
	var spr := Sprite2D.new(); spr.texture = tex
	spr.offset = Vector2(0, feet_offset(tex, 64, 64))
	spr.position = Vector2(cell.x + 0.5, cell.y + 0.5) * PPU
	return spr

# VÀNG: mỏ đá vàng — LUÔN LẤP LÁNH (anim _Highlight 6 frame, loop). Khi đào chỉ thêm nhún (ResNode.hit).
func make_gold(cell: Vector2i) -> Node2D:
	var n := 1 + rng.randi() % 6
	var hi_tex: Texture2D = load(ART + "Pawn and Resources/Gold/Gold Stones/Gold Stone %d_Highlight.png" % n)
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = make_frames(hi_tex, 128, 128, 9.0)   # 6 frame lấp lánh, loop
	spr.animation = "a"; spr.frame = rng.randi() % 6; spr.play()
	spr.offset = Vector2(0, feet_offset(hi_tex, 128, 128))
	spr.add_to_group("fog_anim")
	var node := _res_wrap(spr, cell); node.add_to_group("clearable")
	node.res_kind = "gold"; node.amount = 50; node.hmap = hmap; node.cell = cell; node.builder = self   # 50 vàng; ≤10 → cục nhỏ; hết → biến mất
	return node

# NHÀ: House1-3 (128x192 tĩnh) — xây/sửa bằng BÚA (Hammer).
func make_house(cell: Vector2i) -> Node2D:
	var tex: Texture2D = load(ART + "Buildings/Blue Buildings/House%d.png" % (1 + rng.randi() % 3))
	var spr := Sprite2D.new(); spr.texture = tex
	spr.offset = Vector2(0, feet_offset(tex, 128, 192))
	var node := _res_wrap(spr, cell); node.add_to_group("occluder")   # đứng sau nhà → nhà mờ
	return node

func make_frames(tex: Texture2D, fw: int, fh: int, fps: float) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.add_animation("a"); sf.set_animation_speed("a", fps); sf.set_animation_loop("a", true)
	var n: int = max(1, int(tex.get_width() / fw))
	for i in range(n):
		var at := AtlasTexture.new(); at.atlas = tex; at.region = Rect2(i * fw, 0, fw, fh)
		sf.add_frame("a", at)
	return sf

func feet_offset(tex: Texture2D, fw: int, fh: int) -> float:
	var img: Image = tex.get_image()
	if img == null: return -fh * 0.21
	for y in range(fh - 1, -1, -1):
		for x in range(0, fw, 3):
			if img.get_pixel(x, y).a > 0.3:
				return -(y - fh / 2.0)
	return -fh * 0.21
