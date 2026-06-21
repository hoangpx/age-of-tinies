class_name Fighter extends Node2D
# Lính tự đánh (port Fighter.cs). Đuổi địch gần nhất bằng pathfinding (leo dốc/vòng), đánh khi vào tầm.
# Archer bắn tên (trên cao nguyên +1 tầm/+1 dmg). Monk heal đồng đội. Y-sort theo chân (node tại chân).

const ART := "res://art/"
const CELL := 64
const ENGAGE := 5.0     # tự đánh địch trong 5 ô
const HEAL_RANGE := 3.0    # tầm CAST heal
const MONK_DETECT := 7.0   # tầm PHÁT HIỆN đồng đội bị thương (đi tới heal) — rộng hơn

var team := 0
var kind := "Warrior"
var hp := 100.0
var max_hp := 100.0
var dmg := 4.0
var atk_range := 1.0    # ô
var interval := 2.0
var speed := 1.8        # ô/giây
var hmap: TSHeight
var demo := false       # true = đứng tại chỗ múa động tác đánh (xem anim)
var manual := false     # true = người chơi điều khiển (đi theo lệnh, ko auto-battle)
var ghost := false      # true = đi XUYÊN qua nhà (nông dân AI)
var garrisoned := false # đang đứng TRÊN chòi canh (cao nguyên ảo)
var _garr_tower = null   # chòi đang trèo lên (null = ko)
var _garr_pos := Vector2.ZERO
var _cmd_target = null  # đích người chơi ra lệnh (Vector2) hoặc null
var _attack_target = null  # địch ra lệnh ĐÁNH (Fighter HOẶC Building) — đuổi tới đánh tới chết
var _bob_t := 0.0       # pha nẩy khi đi trên dốc
var _scan_t := 0.0      # nhịp quét địch/đồng đội (ko quét mỗi frame → O(N²) giảm mạnh)
var _cached_enemy: Fighter = null
var _cached_hurt: Fighter = null
var _sep_t := 0.0       # nhịp TÍNH tách (separation) — áp thì mượt mỗi frame
var _sep_vec := Vector2.ZERO
var _path_goal := Vector2(-99999, -99999)   # đích đã tính đường (chỉ tính lại khi đích dời > 1 ô)
var _pf_stuck := 0.0    # thời gian bị tắc khi đi
var _idle_block_t := 0.0  # đang "nghỉ" do bị vây → đứng yên, ko rung
var _moving := false      # frame này đang ĐI (path-move)? → lúc đi thì KO tách (tránh đẩy-kéo giằng co)
var builder = null        # tham chiếu Builder để cộng resource khi giao hàng
var _carry := false       # nông dân đang VÁC resource về nhà?
var _hit_count := 0       # số phát đã bổ resource (5 phát = +1 resource)
var _carry_anim := "Gold" # loại resource đang vác (Gold/Wood/Meat) — chọn anim vác đúng
var _build_node = null    # công trình nông dân đang XÂY (gõ búa)
var _build_stand := Vector2.ZERO   # chỗ đứng xây (bên gần nông dân lúc ra lệnh)
var _build_fx := 0.0      # nhịp icon búa bay lên
var _gather_tool := ""  # công cụ khi đi lấy resource: Axe/Pickaxe/Knife/Hammer ("" = đi thường)
var _gather_node = null # node resource đang nhắm (để rung/chớp khi làm việc)
var _gather_side := 1.0 # đứng bên nào của resource (+1 phải / -1 trái)
var _hit_cd := 0.0      # nhịp ra đòn vào resource
var _fx_cd := 0.0       # nhịp spawn hiệu ứng heal lên đồng đội

# Hiệu ứng HEAL (Heal_Effect 11 frame) hiện lên người được hồi máu.
func _spawn_heal_fx(target: Fighter) -> void:
	var tex: Texture2D = load(ART + "Units/Extra/Heal Effect/Heal_Effect.png")
	var sf := SpriteFrames.new()
	sf.add_animation("a"); sf.set_animation_speed("a", 18.0); sf.set_animation_loop("a", false)
	for i in range(11):
		var at := AtlasTexture.new(); at.atlas = tex; at.region = Rect2(i * 192, 0, 192, 192)
		sf.add_frame("a", at)
	var fx := AnimatedSprite2D.new()
	fx.sprite_frames = sf; fx.animation = "a"; fx.play()
	fx.z_index = 700
	fx.position = target.position + Vector2(0, -22)
	target.get_parent().add_child(fx)
	fx.animation_finished.connect(func(): if is_instance_valid(fx): fx.queue_free())
var _stuck := 0         # đếm frame ko nhúc nhích → bỏ lệnh, về idle
var _sel_mat: ShaderMaterial   # material viền trắng khi được chọn

var _spr: AnimatedSprite2D
var _bar_fill: ColorRect
var _cd := 0.0
var _busy := 0.0
var _path: Array = []
var _repath := 0.0
var _dead := false
var _level := 0

func setup(_team: int, color: String, _kind: String, _hmap: TSHeight) -> void:
	team = _team; kind = _kind; hmap = _hmap
	_scan_t = randf() * 0.25; _sep_t = randf() * 0.1   # SO LE nhịp quét giữa các lính → ko dồn 1 frame
	match kind:
		"Archer": max_hp = 50; dmg = 2; interval = 1.1; atk_range = 5; speed = 1.8   # bắn NHANH hơn
		"Lancer": max_hp = 80; dmg = 6; interval = 1.0; atk_range = 2; speed = 2.16
		"Monk": max_hp = 60; speed = 1.8
		"Pawn": max_hp = 50; dmg = 2; interval = 1.2; atk_range = 1; speed = 2.0   # nông dân: đánh yếu (dao)
		_: max_hp = 120; dmg = 4; interval = 2.0; atk_range = 1; speed = 1.8
	hp = max_hp

	var idle_sheet: String = {"Archer":"Archer_Idle","Lancer":"Lancer_Idle","Monk":"Idle","Pawn":"Pawn_Idle"}.get(kind, "Warrior_Idle")
	var run_sheet: String = {"Archer":"Archer_Run","Lancer":"Lancer_Run","Monk":"Run","Pawn":"Pawn_Run"}.get(kind, "Warrior_Run")
	var atk_sheet: String = {"Archer":"Archer_Shoot","Lancer":"Lancer_Right_Attack","Monk":"Heal","Pawn":"Pawn_Interact Axe"}.get(kind, "Warrior_Attack1")

	var sf := SpriteFrames.new()
	var fh := _add_anim(sf, "idle", color, idle_sheet, 10.0)
	_add_anim(sf, "run", color, run_sheet, 12.0)
	_add_anim(sf, "attack", color, atk_sheet, 12.0)
	if kind == "Archer": sf.set_animation_loop("attack", false)   # bắn 1 lần/phát (giương→buông), ko loop
	if kind == "Pawn":   # anim đi/làm việc theo CÔNG CỤ: Axe=gỗ, Pickaxe=vàng, Knife=thịt cừu, Hammer=xây nhà
		for tool in ["Axe", "Pickaxe", "Knife", "Hammer"]:
			_add_anim(sf, "run_" + tool, color, "Pawn_Run " + tool, 12.0)
			_add_anim(sf, "int_" + tool, color, "Pawn_Interact " + tool, 12.0)
		for res in ["Gold", "Wood", "Meat"]:   # anim VÁC resource (chạy + đứng)
			_add_anim(sf, "carry_" + res, color, "Pawn_Run " + res, 12.0)
			_add_anim(sf, "cidle_" + res, color, "Pawn_Idle " + res, 10.0)

	_spr = AnimatedSprite2D.new()
	_spr.sprite_frames = sf
	_spr.flip_h = (team == 1)
	_spr.offset = Vector2(0, _feet_offset(color, idle_sheet, fh))
	add_child(_spr)
	_spr.play("idle")   # play SAU add_child → idle chạy ngay từ lúc spawn
	_build_bar()
	add_to_group("fighter")
	_level = hmap.lvl_at(position)

# Đường dẫn sheet: Pawn (nông dân) ở "Pawn and Resources/Pawn/<màu> Pawn/"; còn lại ở "Units/<màu> Units/<loại>/".
func _tex_path(color: String, sheet: String) -> String:
	if kind == "Pawn":
		return "%sPawn and Resources/Pawn/%s Pawn/%s.png" % [ART, color, sheet]
	return "%sUnits/%s Units/%s/%s.png" % [ART, color, _folder(), sheet]

func _add_anim(sf: SpriteFrames, name: String, color: String, sheet: String, fps: float) -> int:
	var tex: Texture2D = load(_tex_path(color, sheet))
	var fh: int = tex.get_height()
	if sf.has_animation(name): sf.remove_animation(name)
	sf.add_animation(name)
	sf.set_animation_speed(name, fps)
	sf.set_animation_loop(name, true)   # LOOP cả attack → ko đứng đơ ở frame cuối
	var n: int = max(1, int(tex.get_width() / fh))
	for i in range(n):
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * fh, 0, fh, fh)
		sf.add_frame(name, at)
	return fh

func _folder() -> String:
	return kind   # thư mục theo loại (Warrior/Archer/Lancer/Monk)

func _feet_offset(color: String, sheet: String, fh: int) -> float:
	var tex: Texture2D = load(_tex_path(color, sheet))
	var img: Image = tex.get_image()
	if img == null: return -fh * 0.21
	for y in range(fh - 1, -1, -1):
		for x in range(0, fh, 3):
			if img.get_pixel(x, y).a > 0.3:
				return -(y - fh / 2.0)
	return -fh * 0.21

func _build_bar() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.size = Vector2(40, 6)
	bg.position = Vector2(-20, -64)
	add_child(bg)
	_bar_fill = ColorRect.new()
	_bar_fill.color = (Color(0.30, 0.85, 0.35) if team == 0 else Color(0.90, 0.25, 0.22))
	_bar_fill.size = Vector2(40, 6)
	_bar_fill.position = Vector2(-20, -64)
	add_child(_bar_fill)

# ---------- vòng đời ----------
func is_dead() -> bool: return _dead

func take_damage(d: float) -> void:
	if _dead: return
	hp -= d
	if _bar_fill: _bar_fill.size.x = 40.0 * clampf(hp / max_hp, 0, 1)
	_spr.modulate = Color(1, 0.5, 0.5)
	if hp <= 0: _die()

func heal(a: float) -> void:
	if _dead: return
	hp = min(max_hp, hp + a)
	if _bar_fill: _bar_fill.size.x = 40.0 * clampf(hp / max_hp, 0, 1)

func _die() -> void:
	_dead = true
	remove_from_group("fighter")
	if builder != null: builder.play_sfx("death", position)
	_spawn_death_fx()
	queue_free()

# Hiệu ứng lính chết: dùng DUST CÓ SẴN của asset (Dust_02 = 10 frame 64x64), phóng to, chơi 1 lần rồi xóa.
func _spawn_death_fx() -> void:
	var tex: Texture2D = load(ART + "Particle FX/Dust_02.png")
	var sf := SpriteFrames.new()
	sf.add_animation("a"); sf.set_animation_speed("a", 18.0); sf.set_animation_loop("a", false)
	for i in range(10):
		var at := AtlasTexture.new(); at.atlas = tex; at.region = Rect2(i * 64, 0, 64, 64)
		sf.add_frame("a", at)
	var fx := AnimatedSprite2D.new()
	fx.sprite_frames = sf; fx.animation = "a"; fx.play()
	fx.z_index = 700
	fx.scale = Vector2(2.0, 2.0)                   # 64x64 hơi nhỏ → phóng to cho thấy rõ
	fx.position = position + Vector2(0, -16)
	get_parent().add_child(fx)
	fx.animation_finished.connect(func(): if is_instance_valid(fx): fx.queue_free())

# ---------- điều khiển tay (player) ----------
func command_move(p: Vector2) -> void:   # ra lệnh đi tới điểm p (world)
	_ungarrison()
	_cmd_target = _walkable_center(p)     # về TÂM ô đi-được gần nhất → dừng GIỮA ô (thân ko lòi ra mép)
	_gather_tool = ""; _gather_node = null; _attack_target = null; _build_node = null
	_path.clear(); _repath = 0.0; _pf_stuck = 0.0; _idle_block_t = 0.0

# AI hỏi: lính này có đang BẬN (khai thác/vác/đánh/xây/đi) ko? rảnh → giao việc mới.
func ai_busy() -> bool:
	return _gather_tool != "" or _carry or _attack_target != null or _build_node != null or _cmd_target != null

func ai_build_target():   # công trình lính này đang xây (null nếu ko) — cho AI đếm thợ
	return _build_node

func ai_gather_tool() -> String: return _gather_tool   # "" nếu ko khai thác
func ai_carrying() -> bool: return _carry              # đang vác resource về?

# Trèo lên CHÒI CANH (chỉ archer): tới chòi rồi đứng trên đỉnh = cao nguyên, tự bắn.
func command_garrison(tower, slot_pos: Vector2) -> void:
	_garr_tower = tower; _garr_pos = slot_pos; garrisoned = false
	_attack_target = null; _gather_tool = ""; _gather_node = null; _build_node = null
	_cmd_target = null; _carry = false; _path.clear(); _repath = 0.0; _pf_stuck = 0.0; _idle_block_t = 0.0

func _ungarrison() -> void:
	if _garr_tower != null:
		_garr_tower = null; garrisoned = false; z_index = 0; _level = hmap.lvl_at(position)

func command_attack(target) -> void:   # ra lệnh ĐÁNH 1 con địch/nhà cụ thể (đuổi tới đánh)
	_ungarrison()
	_attack_target = target
	_cmd_target = null; _gather_tool = ""; _gather_node = null; _build_node = null
	_carry = false   # đi đánh nhau → BỎ resource đang vác
	_path.clear(); _repath = 0.0; _pf_stuck = 0.0; _idle_block_t = 0.0

# Vị trí dừng = ô ĐI-ĐƯỢC gần điểm p nhất; nếu là MÉP NAM thì lệch xuống ~0.4 ô cho gần mép nước nam hơn.
func _walkable_center(p: Vector2) -> Vector2:
	var c := hmap.cell_of(p)
	var bc := c
	if not hmap.walkable.get(c, false):
		var bd := INF; var found := false
		for dx in range(-14, 15):
			for dy in range(-14, 15):
				var cc := Vector2i(c.x + dx, c.y + dy)
				if hmap.walkable.get(cc, false):
					var ctr := Vector2(cc.x + 0.5, cc.y + 0.5) * CELL
					var d := ctr.distance_squared_to(p)
					if d < bd: bd = d; bc = cc; found = true
		if not found: return p
	var pos := Vector2(bc.x + 0.5, bc.y + 0.5) * CELL
	if not hmap.walkable.get(Vector2i(bc.x, bc.y + 1), false) and hmap.walkable.get(Vector2i(bc.x, bc.y - 1), false):
		pos.y += 0.4 * CELL   # ô MÉP NAM → đứng lệch xuống, gần mép nước nam hơn
	return pos

func command_gather(node: Node2D) -> void:   # đi lấy resource: đổi anim theo công cụ + rung/chớp node
	_ungarrison()
	_attack_target = null
	_gather_node = node
	_gather_tool = str(node.get_meta("tool"))
	_gather_side = 1.0 if position.x >= node.global_position.x else -1.0   # đứng phía gần pawn
	_cmd_target = _stand_pos()
	_hit_cd = 0.3; _hit_count = 0; _carry = false; _build_node = null
	_path.clear(); _repath = 0.0; _pf_stuck = 0.0; _idle_block_t = 0.0

# Resource CÙNG LOẠI (cùng công cụ) còn hàng, gần nhất — để khai thác tiếp khi cái cũ cạn.
func _find_resource(tool: String):
	var best = null; var bd := INF
	for r in get_tree().get_nodes_in_group("resource"):
		if not is_instance_valid(r): continue
		if str(r.get_meta("tool", "")) != tool: continue
		var amt = r.get("amount")
		if amt != null and amt <= 0: continue
		var dd: float = position.distance_squared_to(r.global_position)
		if dd < bd: bd = dd; best = r
	return best

# Cái đang khai thác cạn → tự chuyển sang cái cùng loại gần nhất. true nếu tìm được.
func _retarget_resource() -> bool:
	var nxt = _find_resource(_gather_tool)
	if nxt == null: return false
	_gather_node = nxt
	_gather_side = 1.0 if position.x >= nxt.global_position.x else -1.0
	_hit_count = 0; _cmd_target = _stand_pos()
	_path.clear(); _repath = 0.0; _pf_stuck = 0.0; _idle_block_t = 0.0; _stuck = 0
	return true

func command_build(b) -> void:   # đi XÂY công trình b (gõ búa)
	_ungarrison()
	_build_node = b
	_build_stand = b.build_stand(position)   # chọn BÊN gần nông dân (ko phải lúc nào cũng bên phải)
	_gather_tool = ""; _gather_node = null; _attack_target = null; _cmd_target = null; _carry = false
	_path.clear(); _repath = 0.0; _pf_stuck = 0.0; _idle_block_t = 0.0

# Điểm ĐỨNG khi khai thác: NGANG resource (lệch ~0.6 ô sang bên) + HƠI SAU (lên trên ~0.25 ô),
# KHÔNG đứng phía trước (dưới) → công cụ mới chạm resource.
func _stand_pos() -> Vector2:
	var rp: Vector2 = _gather_node.global_position
	return rp + Vector2(_gather_side * 0.6 * CELL, -0.25 * CELL)

func _nearest_depot():   # nhà chứa resource gần nhất CÙNG ĐỘI
	var best = null; var bd := INF
	for d in get_tree().get_nodes_in_group("depot"):
		if not is_instance_valid(d) or d.team != team: continue
		var dd: float = position.distance_squared_to(d.global_position)
		if dd < bd: bd = dd; best = d
	return best

func _carry_type(tool: String) -> String:   # công cụ → loại resource vác
	match tool:
		"Pickaxe": return "Gold"
		"Axe": return "Wood"
		"Knife": return "Meat"
	return "Gold"

func set_selected(b: bool) -> void:      # bật/tắt viền trắng quanh sprite
	if b and _sel_mat == null:
		_sel_mat = ShaderMaterial.new()
		_sel_mat.shader = load("res://outline.gdshader")
	_spr.material = (_sel_mat if b else null)

func _manual(delta: float) -> void:
	if _spr.modulate != Color.WHITE:
		_spr.modulate = _spr.modulate.lerp(Color.WHITE, delta * 8.0)
	_repath -= delta; _cd -= delta; _busy -= delta; _fx_cd -= delta
	# ===== CHÒI CANH: trèo lên đỉnh → đứng yên (cao nguyên ảo) → tự bắn địch trong tầm =====
	if _garr_tower != null:
		if not is_instance_valid(_garr_tower):       # chòi nổ → rớt xuống, điều khiển lại bình thường
			_garr_tower = null; garrisoned = false; z_index = 0; _set_anim("idle"); return
		if not garrisoned:
			if position.distance_to(_garr_pos) < 1.4 * CELL:
				position = _garr_pos; garrisoned = true   # tới chân chòi → nhảy lên đỉnh
			else:
				_move_toward(_garr_pos, delta, "run"); return
		position = _garr_pos; z_index = 60; _level = 1   # đứng trên chòi = cao nguyên (+tầm/+dmg)
		var ge := _nearest_enemy(eff_range())
		if ge != null:
			_spr.flip_h = ge.position.x < position.x
			_attack(ge)
		else:
			_set_anim("idle")
		return
	# ===== XÂY công trình: tới cạnh → gõ búa → góp tiến độ (nhiều nông dân → nhanh hơn) =====
	if _build_node != null:
		if not is_instance_valid(_build_node) or not _build_node.needs_work():
			_build_node = null; z_index = 0; _set_anim("idle"); return
		var wp2: Vector2 = _build_stand                  # chỗ đứng xây (bên gần nông dân)
		if position.distance_to(wp2) < 0.6 * CELL:        # tới chỗ đứng → XÂY
			_cmd_target = null; _path.clear(); _stuck = 0; z_index = 0
			_spr.flip_h = _build_node.global_position.x < position.x
			_set_anim("int_Hammer")
			_build_node.add_build(delta)
			_build_fx -= delta
			if _build_fx <= 0.0:
				_build_fx = 0.55
				if builder != null:
					builder.float_build_icon(_build_node.global_position)
					builder.play_sfx("hammer", position)
			return
		var b1 := position
		_move_toward(wp2, delta, "run_Hammer")
		if position.distance_to(b1) < 0.4:
			_stuck += 1
			if _stuck > 80: _build_node = null; _set_anim("idle")   # kẹt lâu → bỏ
		else: _stuck = 0
		return
	# ===== KINH TẾ: khai thác 5 phát → +1 resource → VÁC về nhà dân (depot) → +1 tổng → quay lại =====
	if _gather_tool != "":
		if _carry:                                        # đang VÁC → đem về nhà gần nhất
			var depot = _nearest_depot()
			if depot == null:                             # ko có nhà → bỏ vác
				_carry = false; _set_anim("idle"); return
			z_index = 0
			var dp: Vector2 = depot.global_position
			var wc := _walkable_center(dp)                # ô đi-được CẠNH nhà (nhà to như castle bị chặn giữa)
			# GIAO HÀNG khi tới ô cạnh nhà (hoặc sát tâm với nhà nhỏ) — castle to ko đứng sát tâm được
			if position.distance_to(wc) < 0.8 * CELL or position.distance_to(dp) < 1.3 * CELL:
				_carry = false
				if builder != null:
					builder.deliver(team, _carry_anim, 1, dp)   # +1 đúng loại, đúng ĐỘI (XANH: HUD; ĐỎ: kho AI)
				return
			var bd0 := position
			_move_toward(wc, delta, "carry_" + _carry_anim)
			if position.distance_to(bd0) < 0.4:           # kẹt (vây ở depot) → vẫn GIAO để khỏi đứng chết
				_stuck += 1
				if _stuck > 30:
					_stuck = 0; _carry = false
					if builder != null: builder.deliver(team, _carry_anim, 1, dp)
			else: _stuck = 0
			return
		if not is_instance_valid(_gather_node):                       # cái cũ cạn/biến mất → tìm cái cùng loại gần nhất
			if not _retarget_resource(): _gather_tool = ""; z_index = 0; _set_anim("idle"); return
		var sp := _stand_pos()                            # chỗ đứng CẠNH + HƠI SAU resource
		if position.distance_to(sp) < 0.5 * CELL:         # ĐẾN ĐÚNG chỗ đứng → khai thác
			_cmd_target = null; _path.clear(); _stuck = 0
			z_index = 10                                  # đè lên resource
			_spr.flip_h = _gather_node.global_position.x < position.x
			_set_anim("int_" + _gather_tool)
			_hit_cd -= delta
			if _hit_cd <= 0.0:
				_hit_cd = 0.6
				if _gather_node.has_method("hit"): _gather_node.hit(_gather_tool)
				if builder != null:
					var gs := {"Axe": "axe", "Pickaxe": "pickaxe", "Knife": "meat"}.get(_gather_tool, "axe")
					builder.play_sfx(gs, position)
				_hit_count += 1
				if _hit_count >= 10:                      # đủ 10 phát → rút 1 resource khỏi node
					_hit_count = 0
					if _gather_node.has_method("extract") and _gather_node.extract():
						_carry = true; _carry_anim = _carry_type(_gather_tool)   # vác về nhà
					elif not _retarget_resource():                               # cạn → chuyển sang cái cùng loại gần nhất
						_gather_tool = ""; _gather_node = null; _set_anim("idle")
			return
		z_index = 0
		_cmd_target = sp                                  # đi tới chỗ đứng (đuổi theo cừu)
		var b0 := position
		_move_toward(sp, delta, "run_" + _gather_tool)
		if position.distance_to(b0) < 0.4:
			_stuck += 1
			if _stuck > 40: _gather_tool = ""; _gather_node = null; _set_anim("idle")  # kẹt lâu → bỏ
		else: _stuck = 0
		return
	# ===== ĐÁNH ĐỊCH ĐƯỢC CHỈ ĐỊNH: đuổi tới đánh tới khi nó chết =====
	if _attack_target != null:
		if not is_instance_valid(_attack_target) or _attack_target.is_dead():
			_attack_target = null; _set_anim("idle")
		else:
			z_index = 0
			_fight(_attack_target, delta)
			return
	# ===== ĐI THƯỜNG / GIAO CHIẾN =====
	z_index = 0
	if _cmd_target == null:
		_engage_or_idle(delta); return        # rảnh: có địch gần thì TỰ ĐÁNH, ko thì đứng yên
	var before := position
	var mv_anim: String = ("carry_" + _carry_anim) if _carry else "run"   # ĐANG VÁC → giữ anim vác
	_move_toward(_cmd_target, delta, mv_anim)
	if position.distance_to(_cmd_target) < 0.3 * CELL:
		_arrive(); return
	if position.distance_to(before) < 0.4:
		_stuck += 1
		if _stuck > 10: _arrive()
	else:
		_stuck = 0

# Khi rảnh: lính chiến (dmg>0) tự đánh ĐỊCH trong tầm ENGAGE; Monk heal đồng đội; còn lại đứng yên.
func _engage_or_idle(delta: float) -> void:
	if _carry:                                # đang vác mà rảnh → đứng giữ resource (ko đi đánh)
		_set_anim("cidle_" + _carry_anim); return
	if kind == "Monk":
		var hurt := _enemy_cache_hurt()
		if hurt != null:
			var hd: float = (hurt.position - position).length() / CELL
			if hd <= HEAL_RANGE:
				_spr.flip_h = hurt.position.x < position.x
				_set_anim("attack"); hurt.heal(delta * 6.0)
				if _fx_cd <= 0.0: _fx_cd = 0.55; _spawn_heal_fx(hurt)   # hiệu ứng heal trên đồng đội
				return
			elif hd <= MONK_DETECT:
				_move_toward(hurt.position, delta); return   # phát hiện từ xa → đi tới heal
		_set_anim("idle"); return
	if dmg <= 0:
		_set_anim("idle"); return            # Pawn ko địch quanh: đứng yên
	var target := _enemy_cache()
	if target == null or (target.position - position).length() / CELL > ENGAGE:
		_set_anim("idle"); return
	_fight(target, delta)

func _arrive() -> void:
	_cmd_target = null; _path.clear(); _stuck = 0
	_set_anim("cidle_" + _carry_anim if _carry else "idle")   # đứng vẫn vác (nếu đang vác)

# Địch đã cache (null nếu chết/biến mất) — tránh quét O(N) mỗi frame.
func _enemy_cache() -> Fighter:
	if _cached_enemy != null and (not is_instance_valid(_cached_enemy) or _cached_enemy.is_dead()):
		_cached_enemy = null
	return _cached_enemy

func _enemy_cache_hurt() -> Fighter:
	if _cached_hurt != null and (not is_instance_valid(_cached_hurt) or _cached_hurt.is_dead() or _cached_hurt.hp >= _cached_hurt.max_hp - 0.5):
		_cached_hurt = null
	return _cached_hurt

# Tính vector tách (O(N²)) — gọi GIÃN NHỊP, KO mỗi frame. Lưu vào _sep_vec để áp MƯỢT mỗi frame.
func _compute_sep() -> Vector2:
	var min_d := 0.6 * CELL
	var push := Vector2.ZERO
	for o in get_tree().get_nodes_in_group("fighter"):
		if o == self or not is_instance_valid(o) or o.is_dead(): continue
		var diff: Vector2 = position - o.position
		var L: float = diff.length()
		if L >= min_d: continue
		if L < 0.001:                       # trùng KHÍT → đẩy theo hướng cố định riêng (theo id)
			diff = Vector2.from_angle(float(int(get_instance_id()) % 628) / 100.0); L = 0.001
		push += diff / L * (min_d - L)
	push *= 0.5                              # con kia cũng tự dịch → mỗi bên chỉ gánh NỬA phần chồng
	if push.length() < 3.0: return Vector2.ZERO   # DEADZONE
	return push.limit_length(0.5 * CELL)

# Áp tách MƯỢT mỗi frame (dịch dần) → KO nhảy giật Y → hết "chớp chớp" do y-sort đổi thứ tự liên tục.
func _apply_sep(delta: float) -> void:
	if _sep_vec.length() < 0.5: return
	var step: Vector2 = _sep_vec * minf(delta * 8.0, 0.5)
	if hmap.walkable.get(hmap.cell_of(position + step), false):
		position += step
	elif hmap.walkable.get(hmap.cell_of(position + Vector2(step.x, 0)), false):
		position += Vector2(step.x, 0)
	elif hmap.walkable.get(hmap.cell_of(position + Vector2(0, step.y)), false):
		position += Vector2(0, step.y)
	_sep_vec = _sep_vec.lerp(Vector2.ZERO, minf(delta * 8.0, 1.0))   # tiêu dần (tick sau tính lại)

# ---------- tick ----------
func _process(delta: float) -> void:
	if _dead: return
	if _idle_block_t > 0.0: _idle_block_t -= delta   # đếm lùi "nghỉ do bị vây" (luôn hồi, kể cả ko gọi _move_toward)
	if _spr != null and _spr.position.y != 0.0:   # hạ "nẩy dốc" về 0 khi ko đi trên dốc
		_spr.position.y = move_toward(_spr.position.y, 0.0, delta * 90.0)
	if demo:                          # chế độ xem: đứng yên, lặp động tác đánh
		_set_anim("attack"); return
	# QUÉT địch/đồng đội + TÁCH: ko làm mỗi frame (O(N²)) — giãn nhịp + so le giữa các lính
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.25
		_cached_enemy = _nearest_enemy(INF)
		if kind == "Monk": _cached_hurt = _nearest_hurt_ally()
	# TÁCH chỉ khi GIỮ CHỖ (đứng/đánh), KO tách khi đang ĐI (đi mà bị đẩy ngang → giằng co → chớp).
	# Đang đi (_moving frame trước) / đang khai thác (_gather_tool) / nghỉ-bị-vây → bỏ qua tách.
	var was_moving := _moving
	_moving = false                   # reset; logic phía dưới (_move_toward) sẽ bật lại nếu đang đi
	if not was_moving and _gather_tool == "" and _build_node == null and _idle_block_t <= 0.0:
		_sep_t -= delta
		if _sep_t <= 0.0:
			_sep_t = 0.1
			_sep_vec = _compute_sep() # TÍNH lực tách 10 lần/giây (O(N²))
		_apply_sep(delta)             # ÁP mượt mỗi frame
	if manual:                        # điều khiển tay: đi theo lệnh, ko thì đứng yên
		_manual(delta); return
	if _spr.modulate != Color.WHITE:
		_spr.modulate = _spr.modulate.lerp(Color.WHITE, delta * 8.0)
	_level = hmap.lvl_at(position)
	_cd -= delta; _busy -= delta; _repath -= delta; _fx_cd -= delta

	if kind == "Monk":
		_monk(delta); return

	var target := _enemy_cache()   # ĐỊCH gần nhất (đã cache) → 2 phe xáp lá cà
	if target == null:
		_set_anim("idle"); return
	_fight(target, delta)

# Đánh 1 mục tiêu: Lancer phải CÙNG HÀNG (đâm ngang) mới đánh, chưa thì đi ngang-hàng cạnh địch; còn lại đánh khi vào tầm.
func _fight(target, delta: float) -> void:
	_level = hmap.lvl_at(position)
	_spr.flip_h = target.position.x < position.x
	# Mục tiêu là NHÀ (đứng yên, to): ô gốc nhà bị chặn nên ko path thẳng vào.
	if target.has_method("needs_work"):
		# Cận chiến (Lancer/Pawn/Warrior): đứng NGANG bên hông nhà (sát tường) → mũi giáo/đòn chạm tường.
		# Cung: bắn từ ô đi-được gần nhà.
		if kind != "Archer" and target.has_method("build_stand"):
			var sp: Vector2 = target.build_stand(position)        # ô bên hông, ngang hàng, nhích sát tường
			if position.distance_to(sp) < 0.6 * CELL:
				_spr.flip_h = target.position.x < position.x       # quay mặt vào tường
				_attack(target)
			else:
				_move_toward(sp, delta, "run")
			return
		var dn: float = position.distance_to(target.position) / CELL
		if dn <= eff_range() + 1.2:
			_attack(target)
		else:
			_move_toward(_walkable_center(target.position), delta, "run")
		return
	# Lancer & Pawn (dao): phải NGANG HÀNG (đứng bằng/gần bằng target) mới đánh — giống thịt cừu.
	var tpos: Vector2 = target.position
	if kind == "Lancer" or kind == "Pawn":
		var dy: float = abs(tpos.y - position.y)
		var dx: float = abs(tpos.x - position.x)
		var near: float = (tpos - position).length() / CELL
		var aligned: bool = dy < 0.65 * CELL and dx <= eff_range() * CELL
		if kind == "Lancer" and near <= 1.15: aligned = true   # lao sát người mọi hướng (riêng Lancer)
		if aligned:
			if _can_melee(target): _attack(target)
			else: _move_toward(tpos, delta, "run")   # khác cao độ → đi vòng qua DỐC
		else:
			var side := 1.0 if position.x >= tpos.x else -1.0
			_move_toward(tpos + Vector2(side * (eff_range() - 0.6) * CELL, 0), delta, "run")
		return
	var dist: float = (tpos - position).length() / CELL
	if dist > eff_range() or (kind != "Archer" and not _can_melee(target)):
		_move_toward(target.position, delta, "run")
	else:
		_attack(target)

# Cận chiến (mọi unit TRỪ cung): KO đánh được qua chênh cao độ (đồi vs dưới đồi); chỉ đánh khi
# mình HOẶC địch đứng trên DỐC (ramp). Cung (Archer) thì bắn xuyên cao độ thoải mái.
func _can_melee(target) -> bool:
	if kind == "Archer": return true
	var ml := hmap.lvl_at(position)
	var tl := hmap.lvl_at(target.position)
	if ml == tl: return true
	return hmap.ramp.has(hmap.cell_of(position)) or hmap.ramp.has(hmap.cell_of(target.position))

# Cung đứng trên ĐỒI (level 1): bắn XA hơn (+2 ô) và MẠNH hơn (+2 dmg).
func eff_range() -> float: return atk_range + (2.0 if (kind == "Archer" and _level == 1) else 0.0)
func eff_dmg() -> float: return dmg + (2.0 if (kind == "Archer" and _level == 1) else 0.0)

func _attack(target) -> void:   # target: Fighter HOẶC Building (đều có take_damage)
	_set_anim("int_Knife" if kind == "Pawn" else "attack")   # nông dân: vung DAO như thịt cừu
	if _cd > 0: return
	_cd = interval; _busy = 0.6
	_spr.frame = 0; _spr.play()   # CHƠI LẠI đòn đánh từ đầu mỗi nhịp → khớp anim với phát đánh
	if kind == "Archer":
		if builder != null: builder.play_sfx("bow", position)
		var tgt = target
		var t := create_tween()
		t.tween_interval(0.28)    # BUÔNG cung giữa anim (sau khi giương) → tên ra khớp
		t.tween_callback(func(): if is_instance_valid(tgt) and not tgt.is_dead(): _shoot(tgt))
	else:
		target.take_damage(dmg)
		if builder != null:
			var snd := "spear" if kind == "Lancer" else ("meat" if kind == "Pawn" else "sword")
			builder.play_sfx(snd, position)

func _shoot(target) -> void:   # target: Fighter HOẶC Building
	var arrow := Sprite2D.new()
	arrow.texture = load(ART + "Units/Extra/Arrow/Arrow.png")
	arrow.z_index = 500                       # bay trên mọi thứ
	var start: Vector2 = position + Vector2(0, -34)
	arrow.position = start
	get_parent().add_child(arrow)
	var tgt = target
	var dest: Vector2 = target.position + Vector2(0, -26)
	var d := eff_dmg()
	var arc := 95.0                           # độ cao vòng cung
	var dur := 0.55
	var tw := arrow.create_tween()
	# bay theo PARABOL (vòng lên cao rồi rơi), xoay theo hướng bay
	tw.tween_method(func(t: float):
		if not is_instance_valid(arrow): return
		var b := start.lerp(dest, t)
		var p := Vector2(b.x, b.y - arc * sin(t * PI))
		var t2 := minf(t + 0.03, 1.0)
		var b2 := start.lerp(dest, t2)
		var p2 := Vector2(b2.x, b2.y - arc * sin(t2 * PI))
		if p2 != p: arrow.rotation = (p2 - p).angle()
		arrow.position = p
	, 0.0, 1.0, dur)
	tw.tween_callback(func():
		if not is_instance_valid(arrow): return
		# trúng người chỉ khi địch CÒN Ở GẦN điểm rơi (ko né kịp); né đi rồi → cắm xuống ĐẤT
		if is_instance_valid(tgt) and not tgt.is_dead() and tgt.position.distance_to(dest) < 0.8 * CELL:
			tgt.take_damage(d)
			if builder != null: builder.play_sfx("arrow_hit", dest)
			_stick_in_person(arrow, tgt)        # CẮM vào người (đầu ghim, nửa đuôi thò ra)
		else:
			_stick_in_ground(arrow, dest))      # CẮM xuống đất (nửa đuôi thò lên)

# Chỉ vẽ NỬA SAU mũi tên (đuôi) — nửa trước (đầu) coi như ghim chìm vào người/đất.
func _half_arrow(arrow: Sprite2D, rot: float, impact: Vector2) -> void:
	arrow.region_enabled = true
	arrow.region_rect = Rect2(0, 0, 32, 64)    # nửa TRÁI texture = đuôi (đầu mũi ở nửa phải, bỏ)
	arrow.rotation = rot
	arrow.position = impact - 16.0 * Vector2.from_angle(rot)   # mép cắt (đầu) tại điểm trúng, đuôi thò ngược ra

# Cắm vào người: arrow thành CON của target (đi theo), chỉ thấy nửa đuôi thò ra.
func _stick_in_person(arrow: Sprite2D, tgt) -> void:   # tgt: Fighter HOẶC Building
	var rot := arrow.rotation
	arrow.get_parent().remove_child(arrow)
	tgt.add_child(arrow)
	arrow.z_index = 50
	_half_arrow(arrow, rot, Vector2(0, -30))
	var t := arrow.create_tween()
	t.tween_interval(0.8)
	t.tween_property(arrow, "modulate:a", 0.0, 0.3)
	t.tween_callback(func(): if is_instance_valid(arrow): arrow.queue_free())

# Cắm xuống đất: chúi xuống, chỉ thấy nửa đuôi thò lên mặt đất.
func _stick_in_ground(arrow: Sprite2D, dest: Vector2) -> void:
	arrow.z_index = 50
	_half_arrow(arrow, PI * 0.5 + 0.45, dest)  # chúi xuống đất
	var t := arrow.create_tween()
	t.tween_interval(1.3)
	t.tween_property(arrow, "modulate:a", 0.0, 0.4)
	t.tween_callback(func(): if is_instance_valid(arrow): arrow.queue_free())

func _monk(delta: float) -> void:
	var hurt := _enemy_cache_hurt()
	if hurt != null:
		var dist: float = (hurt.position - position).length() / CELL
		_spr.flip_h = (hurt.position - position).x < 0
		if dist > HEAL_RANGE:
			_move_toward(hurt.position, delta)
		else:
			_set_anim("attack"); hurt.heal(delta * 6.0)
			if _fx_cd <= 0.0: _fx_cd = 0.55; _spawn_heal_fx(hurt)   # hiệu ứng heal trên đồng đội
	else:
		# ko ai cần heal → bám theo đội (tiến gần địch nhưng giữ khoảng ~4 ô, ko lao vào)
		var enemy := _enemy_cache()
		if enemy != null and (enemy.position - position).length() / CELL > 4.0:
			_move_toward(enemy.position, delta)
		else:
			_set_anim("idle")

# ---------- di chuyển ----------
func _move_toward(goal: Vector2, delta: float, run_anim := "run") -> void:
	# Tính lại đường khi: chưa có đường / đích dời >1 ô / ô kế tiếp BỊ CHẶN (vd nhà vừa xây chắn đường).
	var blocked_ahead: bool = not _path.is_empty() and not hmap.passable(hmap.cell_of(_path[0]), ghost)
	if _path.is_empty() or _path_goal.distance_to(goal) > CELL or blocked_ahead:
		_path = hmap.find_path(position, goal, ghost)
		_path.append(goal)
		_path_goal = goal
		_pf_stuck = 0.0
	if _path.is_empty(): return
	# BỊ VÂY (quân mình quá đông chắn lối) → ĐỨNG YÊN hẳn 1 lúc (idle, ko rung), rồi mới thử lại.
	if _idle_block_t > 0.0:
		_set_anim("idle")
		return
	_moving = true                    # đang path-move frame này → frame sau KO tách (tránh giằng co)
	var wp: Vector2 = _path[0]
	if position.distance_to(wp) <= 0.3 * CELL:
		_path.remove_at(0)
		if _path.is_empty(): return
		wp = _path[0]
	var dir := (wp - position).normalized()
	_spr.flip_h = dir.x < 0
	var on_ramp := hmap.ramp.has(hmap.cell_of(position))
	var spd: float = speed * (0.5 if on_ramp else 1.0)   # lên/xuống DỐC → đi CHẬM hơn
	var step := dir * spd * CELL * delta
	var nxt := position + step
	var before := position
	var fromc := hmap.cell_of(position)
	# tôn trọng chặn; CÙNG ô thì luôn cho đi (để THOÁT khi đang đứng trên ô bị chặn, vd nhà xây đè lên).
	# bước chéo bị chặn → TRƯỢT theo 1 trục (men tường, tránh kẹt góc vách)
	if hmap.cell_of(nxt) == fromc or hmap.step_ok(fromc, hmap.cell_of(nxt), ghost):
		position = nxt
	else:
		var nx := position + Vector2(step.x, 0.0)
		var ny := position + Vector2(0.0, step.y)
		if step.x != 0.0 and (hmap.cell_of(nx) == fromc or hmap.step_ok(fromc, hmap.cell_of(nx), ghost)):
			position = nx
		elif step.y != 0.0 and (hmap.cell_of(ny) == fromc or hmap.step_ok(fromc, hmap.cell_of(ny), ghost)):
			position = ny
	# TẮC: đếm thời gian ko nhúc nhích. Nếu ô kế tiếp là ĐẤT (bị QUÂN chắn) → để _pf_stuck dồn → đứng idle (xử ở trên).
	# Nếu ô kế tiếp BỊ CHẶN cứng (terrain/nhà) thì blocked_ahead ở trên đã lo tính lại đường.
	if position.distance_to(before) < 0.05:
		_pf_stuck += delta
		if _pf_stuck > 0.15:               # tắc ~0.15s → nghỉ idle 0.7s (hết jitter), rồi thử lại
			_pf_stuck = 0.0; _idle_block_t = 0.7
	else:
		_pf_stuck = 0.0
	# lên/xuống DỐC → nẩy CAO hơn (đi chậm, nhấp nhô rõ)
	if hmap.ramp.has(hmap.cell_of(position)):
		_bob_t += delta
		_spr.position.y = -absf(sin(_bob_t * 13.0)) * 10.0
	_set_anim(run_anim)

func _set_anim(a: String) -> void:
	if a == "idle" and _busy > 0: a = "attack"
	if _spr.animation != a:
		_spr.animation = a
		_spr.play()

# ---------- truy vấn ----------
func _nearest_enemy(rng: float) -> Fighter:
	var best: Fighter = null
	var bd := rng * rng * CELL * CELL
	for f in get_tree().get_nodes_in_group("fighter"):
		if f == self or f.team == team or f.is_dead(): continue
		var dd: float = position.distance_squared_to(f.position)
		if dd < bd: bd = dd; best = f
	return best

func _nearest_hurt_ally() -> Fighter:
	var best: Fighter = null
	var bd := INF
	for f in get_tree().get_nodes_in_group("fighter"):
		if f == self or f.team != team or f.is_dead(): continue
		if f.hp >= f.max_hp - 0.5: continue
		var dd: float = position.distance_squared_to(f.position)
		if dd < bd: bd = dd; best = f
	return best
