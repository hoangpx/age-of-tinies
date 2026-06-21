class_name Building extends Node2D
# Công trình: xây dần (mờ→rõ, máu tăng), bị đánh như người (take_damage), hết máu → dust + biến mất.
const CELL := 64
var _spr: Sprite2D
var team := 0
var btype := ""
var max_hp := 100.0
var hp := 0.0
var build_time := 20.0     # giây (1 nông dân); N nông dân → /N
var _progress := 0.0       # giây-công đã xây
var built := false
var is_depot := false
var builder = null         # Builder ref (để +cap khi xong nhà dân)
var hmap = null
var cell := Vector2i.ZERO
var foot := 1              # nửa bề ngang footprint (ô) để mở/chặn đường
var work_pos := Vector2.ZERO   # chỗ nông dân ĐỨNG gõ búa (sát chân nhà)
var _texw := 0.0; var _texh := 0.0; var _offy := 0.0   # để bắt click trúng HÌNH nhà
var _fires: Array = []         # ngọn lửa khi nhà bị thương
var queue: Array = []          # hàng đợi sản xuất: {kind, time}
var prod_t := 0.0              # thời gian còn lại của unit đầu hàng
var prod_total := 1.0
# Nhà BẮN TÊN phòng thủ: Castle dmg 4 (2×archer) tầm 7.5 (1.5×); Chòi canh dmg 3 (archer+1) tầm 5 (=archer).
const TOWER_INTERVAL := 1.4
var _tower_cd := 0.0
var garrison: Array = []          # archer đứng trên CHÒI CANH (≤2) — coi như đứng cao nguyên

func garrison_full() -> bool:
	garrison = garrison.filter(func(a): return is_instance_valid(a) and not a.is_dead())
	return garrison.size() >= 2

# Vị trí slot trên đỉnh chòi cho archer thứ idx (0/1).
func garrison_slot(idx: int) -> Vector2:
	var sx: float = -20.0 if idx == 0 else 20.0
	return global_position + Vector2(sx, _offy * 0.6)

func _shooter() -> bool: return built and (btype == "castle" or btype == "tower")
func _shoot_dmg() -> float: return 4.0 if btype == "castle" else 3.0
func _shoot_range() -> float: return 7.5 if btype == "castle" else 5.0

func _process(delta: float) -> void:
	if _shooter():                           # castle / chòi canh tự bắn địch trong tầm
		_tower_cd -= delta
		if _tower_cd <= 0.0:
			var tgt = _tower_target()
			if tgt != null: _tower_cd = TOWER_INTERVAL; _tower_shoot(tgt)
	if not built or queue.is_empty(): return
	prod_t -= delta
	if prod_t <= 0.0:
		var item: Dictionary = queue.pop_front()
		if builder != null and builder.has_method("spawn_unit_front"): builder.spawn_unit_front(self, item["kind"])
		if not queue.is_empty():
			prod_total = float(queue[0]["time"]); prod_t = prod_total

# Địch (khác đội) còn sống gần nhất trong tầm bắn.
func _tower_target():
	var rng: float = _shoot_range()
	var best = null; var bd: float = rng * rng * CELL * CELL
	for f in get_tree().get_nodes_in_group("fighter"):
		if not is_instance_valid(f) or f.team == team or f.is_dead(): continue
		var dd: float = global_position.distance_squared_to(f.position)
		if dd < bd: bd = dd; best = f
	return best

# Bắn 1 mũi tên vòng cung → trúng thì gây dmg theo loại nhà.
func _tower_shoot(target) -> void:
	var par := get_parent()
	if par == null or not is_instance_valid(par): return
	var arrow := Sprite2D.new()
	arrow.texture = load("res://art/Units/Extra/Arrow/Arrow.png")
	arrow.z_index = 500
	var start: Vector2 = global_position + Vector2(0, _offy * 0.7)   # từ thân/đỉnh castle
	arrow.position = start
	par.add_child(arrow)
	var tgt = target
	var dmg := _shoot_dmg()
	var dest: Vector2 = target.position + Vector2(0, -26)
	var arc := 130.0; var dur := 0.55
	var tw := arrow.create_tween()
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
		if is_instance_valid(tgt) and not tgt.is_dead() and tgt.position.distance_to(dest) < 0.9 * CELL:
			tgt.take_damage(dmg)
		arrow.queue_free())

func enqueue(kind: String, time: float) -> void:
	queue.append({"kind": kind, "time": time})
	if queue.size() == 1: prod_total = time; prod_t = time

func queue_count(kind: String) -> int:
	var n := 0
	for it in queue:
		if it["kind"] == kind: n += 1
	return n

func progress_of(kind: String) -> float:
	if queue.is_empty() or queue[0]["kind"] != kind or prod_total <= 0.0: return 0.0
	return clampf(1.0 - prod_t / prod_total, 0.0, 1.0)

# Hủy 1 unit loại kind (cái đầu-hàng nhất) → trả về true nếu hủy được.
func cancel_one(kind: String) -> bool:
	for i in range(queue.size()):
		if queue[i]["kind"] == kind:
			queue.remove_at(i)
			if i == 0 and not queue.is_empty():
				prod_total = float(queue[0]["time"]); prod_t = prod_total
			return true
	return false
var _bar: ColorRect
var _bar_bg: ColorRect

func setup_b(tex: Texture2D, off: float, type: String, mhp: float, btime: float, tm: int, depot: bool, done := false) -> void:
	btype = type; max_hp = mhp; build_time = btime; team = tm; is_depot = done and depot
	_spr = Sprite2D.new(); _spr.texture = tex; _spr.offset = Vector2(0, off)
	_texw = tex.get_width(); _texh = tex.get_height(); _offy = off
	add_child(_spr)
	add_to_group("building")
	if done:                       # Castle: dựng sẵn, đủ máu
		built = true; hp = max_hp; _progress = build_time
		if depot: add_to_group("depot")
	else:                          # công trình đang XÂY: mờ, máu 0
		hp = 0.0; _spr.modulate.a = 0.4
		add_to_group("construction")
	_build_bar()

func is_built() -> bool: return built
func is_dead() -> bool: return hp <= 0.0

# Chỗ đứng xây theo BÊN gần nông dân (trái/phải cùng hàng); fallback work_pos (nam).
func build_stand(from: Vector2) -> Vector2:
	var lc := Vector2i(cell.x - foot - 1, cell.y)
	var rc := Vector2i(cell.x + foot + 1, cell.y)
	var lw: bool = (hmap == null) or hmap.walkable.get(lc, false)
	var rw: bool = (hmap == null) or hmap.walkable.get(rc, false)
	# nhích SÁT vào tường nhà (0.45 ô về phía nhà) → búa chạm, ko bị hở 1 ô
	var left := Vector2(lc.x + 0.5, lc.y + 0.5) * CELL + Vector2(0.45 * CELL, 0)
	var right := Vector2(rc.x + 0.5, rc.y + 0.5) * CELL - Vector2(0.45 * CELL, 0)
	var want_left: bool = from.x < global_position.x
	if want_left and lw: return left
	if (not want_left) and rw: return right
	if lw: return left
	if rw: return right
	return work_pos

# Click có trúng HÌNH nhà ko (cả phần thân cao, ko chỉ ô gốc).
func contains_point(p: Vector2) -> bool:
	var cy: float = global_position.y + _offy   # tâm sprite (centered) theo y
	return absf(p.x - global_position.x) <= _texw * 0.5 and absf(p.y - cy) <= _texh * 0.5

# Còn cần thợ (đang xây HOẶC đã xây nhưng máu chưa đầy = cần SỬA).
func needs_work() -> bool:
	return (not built) or hp < max_hp - 0.5

# Góp công xây/SỬA (mỗi nông dân gọi mỗi frame → N nông dân nhanh N lần). Tốc độ sửa = tốc độ xây.
func add_build(amount: float) -> void:
	if not built:
		_progress += amount
		var t: float = clampf(_progress / build_time, 0.0, 1.0)
		hp = max_hp * t
		_spr.modulate.a = lerpf(0.4, 1.0, t)   # mờ → rõ dần
		_update_bar()
		if _progress >= build_time:
			built = true; hp = max_hp; _spr.modulate.a = 1.0
			remove_from_group("construction")
			_update_bar(); _update_fires()
			if is_depot or btype == "house": add_to_group("depot")
			if team == 0 and builder != null and builder.has_method("bake_light"):
				builder.bake_light(global_position)   # nhà mình xây xong → chỗ đó có ánh sáng
			if builder != null and builder.has_method("play_sfx"): builder.play_sfx("build_done", global_position)
			if btype == "house" and builder != null and builder.has_method("on_house_built"):
				builder.on_house_built()
	elif hp < max_hp:                          # SỬA NHÀ: 5 máu/giây mỗi nông dân
		hp = minf(max_hp, hp + 5.0 * amount)
		_update_bar(); _update_fires()

func take_damage(d: float) -> void:
	hp -= d
	_spr.modulate = Color(1, 0.5, 0.5)
	var tw := create_tween(); tw.tween_property(_spr, "modulate", Color(1, 1, 1, _spr.modulate.a), 0.3)
	_update_bar(); _update_fires()
	if hp <= 0.0: _destroy()

# Lửa cháy theo mức MẤT máu: mất ≥20% →1, ≥50% →2, ≥80% →3 ngọn lửa.
func _update_fires() -> void:
	if not built:
		for f in _fires:
			if is_instance_valid(f): f.queue_free()
		_fires.clear(); return
	var lost: float = 1.0 - hp / max_hp
	var want := 0
	if lost >= 0.2: want += 1
	if lost >= 0.5: want += 1
	if lost >= 0.8: want += 1
	var had: int = _fires.size()
	while _fires.size() < want: _add_fire(_fires.size())
	if _fires.size() > had and builder != null and builder.has_method("play_sfx"):
		builder.play_sfx("fire", global_position)   # vừa bùng thêm lửa → tiếng cháy
	while _fires.size() > want:
		var f = _fires.pop_back()
		if is_instance_valid(f): f.queue_free()

func _add_fire(idx: int) -> void:
	var sheets := ["Fire_01", "Fire_02", "Fire_03"]; var nfr := [8, 10, 12]
	var k: int = idx % 3
	var tex: Texture2D = load("res://art/Particle FX/%s.png" % sheets[k])
	var sf := SpriteFrames.new(); sf.add_animation("a"); sf.set_animation_speed("a", 12.0); sf.set_animation_loop("a", true)
	for i in range(nfr[k]):
		var at := AtlasTexture.new(); at.atlas = tex; at.region = Rect2(i * 64, 0, 64, 64)
		sf.add_frame("a", at)
	var fx := AnimatedSprite2D.new(); fx.sprite_frames = sf; fx.animation = "a"; fx.frame = idx; fx.play()
	fx.scale = Vector2(1.8, 1.8); fx.z_index = 6
	# cháy ở GIỮA thân nhà (quanh tâm hình = _offy theo y), tỏa ngang theo bề rộng nhà — KO ở chân
	var cx: float = _texw * 0.22
	var offs := [Vector2(0, _offy + 8), Vector2(-cx, _offy - 16), Vector2(cx, _offy + 20)]
	fx.position = offs[idx % 3]
	add_child(fx); _fires.append(fx)

func _destroy() -> void:
	var big: bool = btype == "castle" or btype == "barracks" or btype == "monk"
	if builder != null and builder.has_method("play_sfx"): builder.play_sfx("explode", global_position)
	_spawn_explosion(Vector2(0, -30))
	if big: _spawn_explosion(Vector2(-50, -80))   # nhà to → 2 vụ nổ
	if hmap != null:
		for dy in range(-3, 1):                       # nhả CẢ thân nhà (bắc) — ô nào của nhà thì mở lại
			for dx in range(-foot, foot + 1):
				var fc := Vector2i(cell.x + dx, cell.y + dy)
				if hmap.bldg.has(fc):
					hmap.bldg.erase(fc); hmap.walkable[fc] = true   # chỗ trống → đi được
	queue_free()

func _spawn_explosion(off: Vector2) -> void:
	var par := get_parent()
	if par == null or not is_instance_valid(par): return
	var tex: Texture2D = load("res://art/Particle FX/Explosion_02.png")
	var sf := SpriteFrames.new(); sf.add_animation("a"); sf.set_animation_speed("a", 18.0); sf.set_animation_loop("a", false)
	for i in range(10):
		var at := AtlasTexture.new(); at.atlas = tex; at.region = Rect2(i * 192, 0, 192, 192)
		sf.add_frame("a", at)
	var fx := AnimatedSprite2D.new(); fx.sprite_frames = sf; fx.animation = "a"; fx.play()
	fx.z_index = 800; fx.scale = Vector2(1.5, 1.5); fx.position = global_position + off
	par.add_child(fx)
	fx.animation_finished.connect(func(): if is_instance_valid(fx): fx.queue_free())

func _build_bar() -> void:
	_bar_bg = ColorRect.new(); _bar_bg.color = Color(0, 0, 0, 0.6)
	_bar_bg.size = Vector2(44, 6); _bar_bg.position = Vector2(-22, -90)
	add_child(_bar_bg)
	_bar = ColorRect.new(); _bar.color = Color(0.3, 0.85, 0.3)
	_bar.size = Vector2(44, 6); _bar.position = Vector2(-22, -90)
	add_child(_bar)
	_update_bar()

func _update_bar() -> void:
	if _bar == null: return
	var f: float = clampf(hp / max_hp, 0.0, 1.0)
	_bar.size.x = 44.0 * f
	# ẩn thanh máu khi đã xây xong & đầy máu
	var show := (not built) or hp < max_hp - 0.5
	_bar.visible = show; _bar_bg.visible = show
