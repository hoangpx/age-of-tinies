class_name Sheep extends Node2D
# Cừu trung lập: lang thang ngẫu nhiên trên cỏ, dừng lại gặm cỏ / đứng yên. Y-sort theo chân.
const ART := "res://art/Pawn and Resources/Meat/Sheep/"
const CELL := 64
const SPEED := 26.0   # px/giây (chậm, thong thả)

var _spr: AnimatedSprite2D
var _rng := RandomNumberGenerator.new()
var _allowed: Dictionary       # Vector2i -> true (ô cỏ được đi)
var _state := "rest"
var _t := 0.0
var _target := Vector2.ZERO

func setup(allowed: Dictionary, seed_v: int) -> void:
	_allowed = allowed
	_rng.seed = seed_v
	var sf := SpriteFrames.new()
	_add(sf, "idle", "Sheep_Idle", 6, 8.0)
	_add(sf, "move", "Sheep_Move", 4, 10.0)
	_add(sf, "grass", "Sheep_Grass", 12, 10.0)
	_spr = AnimatedSprite2D.new()
	_spr.sprite_frames = sf
	_spr.offset = Vector2(0, _feet())
	add_child(_spr)
	_rest()

func _add(sf: SpriteFrames, anim: String, sheet: String, n: int, fps: float) -> void:
	var tex: Texture2D = load(ART + sheet + ".png")
	sf.add_animation(anim); sf.set_animation_speed(anim, fps); sf.set_animation_loop(anim, true)
	for i in range(n):
		var at := AtlasTexture.new(); at.atlas = tex; at.region = Rect2(i * 128, 0, 128, 128)
		sf.add_frame(anim, at)

func _feet() -> float:
	var img: Image = (load(ART + "Sheep_Idle.png") as Texture2D).get_image()
	if img == null: return -24.0
	for y in range(127, -1, -1):
		for x in range(0, 128, 3):
			if img.get_pixel(x, y).a > 0.3: return -(y - 64.0)
	return -24.0

func _play(a: String) -> void:
	if _spr.animation != a: _spr.animation = a; _spr.play()

func _rest() -> void:
	_state = "rest"; _t = _rng.randf_range(2.0, 5.0)
	_play("grass" if _rng.randf() < 0.6 else "idle")   # phần lớn thời gian gặm cỏ

func _roam() -> void:
	# chọn 1 ô cỏ trong bán kính ~3 ô quanh vị trí hiện tại
	var here := Vector2i(int(position.x / CELL), int(position.y / CELL))
	var picks: Array = []
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var c := Vector2i(here.x + dx, here.y + dy)
			if _allowed.has(c): picks.append(c)
	if picks.is_empty(): _rest(); return
	var p: Vector2i = picks[_rng.randi() % picks.size()]
	_target = Vector2(p.x + 0.5, p.y + 0.5) * CELL
	_state = "move"; _play("move")

var amount := 50   # 50 thịt; hết → BIẾN MẤT (ko chết), có dust
var builder = null # spawn cừu mới chỗ khác khi cạn

func extract() -> bool:   # lấy 1 thịt; cừu ko chết, chỉ biến mất khi cạn (dust như người chết)
	if amount <= 0: return false
	amount -= 1
	if amount <= 0:
		ResNode.spawn_dust(get_parent(), global_position)
		if builder != null:
			if builder.has_method("play_sfx"): builder.play_sfx("sheep", global_position)   # kêu "be" lúc biến mất
			builder.respawn_resource("sheep")
		queue_free()
	return true

func hit(_tool: String) -> void:   # bị chém: STRETCH nhẹ quanh CHÂN (chân giữ, thân giãn lên 1 chút) + CHỚP HỒNG + dừng
	if _spr == null: return
	_state = "rest"; _t = 1.2
	var tw := create_tween()
	tw.tween_property(_spr, "scale:y", 1.06, 0.07)
	tw.tween_property(_spr, "scale:y", 0.98, 0.07)
	tw.tween_property(_spr, "scale:y", 1.0, 0.06)
	_spr.modulate = Color(1.0, 0.45, 0.7)
	var t2 := create_tween()
	t2.tween_property(_spr, "modulate", Color.WHITE, 0.3)

func _process(delta: float) -> void:
	_t -= delta
	if _state == "move":
		var to := _target - position
		if to.length() < 4.0:
			position = _target; _rest()
		else:
			_spr.flip_h = to.x < 0.0
			position += to.normalized() * SPEED * delta
	elif _t <= 0.0:
		_roam()
