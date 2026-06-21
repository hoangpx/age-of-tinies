class_name ResNode extends Node2D
# Node resource (cây/vàng/nhà). hit(tool) → phản ứng KHI KHAI THÁC:
#  - Axe (CÂY): nghiêng quanh gốc → ngọn rung phía trên.
#  - Pickaxe (VÀNG) / Hammer (NHÀ): lún xuống rồi nảy lên.
# (vàng còn tự LẤP LÁNH liên tục bằng anim riêng — ko liên quan hit).
var _spr                       # Sprite2D / AnimatedSprite2D
var _base := Vector2.ZERO
# ----- kinh tế: mỗi node chứa 50 đơn vị resource -----
var res_kind := ""             # "wood" | "gold" ("" = nhà, ko khai thác)
var amount := 50
var stump_tex: Texture2D       # (gỗ) ảnh gốc cây khi hết
var stump_off := 0.0
var hmap = null                # để mở lại ô đi được khi resource biến mất
var cell := Vector2i.ZERO
var builder = null             # để spawn resource MỚI ở chỗ khác khi cạn

func set_visual(s) -> void:
	_spr = s
	_base = s.offset
	add_child(s)

# Lấy 1 đơn vị resource. Trả false nếu đã cạn. Tự biến đổi (cục nhỏ / gốc cây / biến mất) + dust.
func extract() -> bool:
	if amount <= 0: return false
	amount -= 1
	if res_kind == "gold":
		if amount == 10 and is_instance_valid(_spr):     # còn 10 → cục TO thành cục NHỎ
			_spr.scale = Vector2(0.58, 0.58)
			ResNode.spawn_dust(get_parent(), global_position)
		elif amount <= 0:                                # hết → dust + biến mất + mọc vàng chỗ khác
			ResNode.spawn_dust(get_parent(), global_position)
			if builder != null: builder.respawn_resource("gold")
			_remove()
	elif res_kind == "wood":
		if amount <= 0:                                  # hết → chỉ còn GỐC CÂY + dust + mọc cây chỗ khác
			ResNode.spawn_dust(get_parent(), global_position)
			if builder != null: builder.respawn_resource("tree")
			_to_stump()
	return true

func _remove() -> void:
	if hmap != null: hmap.walkable[cell] = true   # chỗ trống → đi được
	queue_free()

func _to_stump() -> void:
	remove_from_group("resource"); remove_from_group("occluder")
	if is_instance_valid(_spr): _spr.queue_free()
	var s := Sprite2D.new(); s.texture = stump_tex; s.offset = Vector2(0, stump_off)
	_spr = s; add_child(s)
	if hmap != null: hmap.walkable[cell] = true   # gốc cây = đi qua được

# Dust dùng chung (cây/vàng/cừu khi biến đổi). Dust_02 = 10 frame 64x64.
static func spawn_dust(parent: Node, pos: Vector2) -> void:
	if parent == null or not is_instance_valid(parent): return
	var tex: Texture2D = load("res://art/Particle FX/Dust_02.png")
	var sf := SpriteFrames.new()
	sf.add_animation("a"); sf.set_animation_speed("a", 18.0); sf.set_animation_loop("a", false)
	for i in range(10):
		var at := AtlasTexture.new(); at.atlas = tex; at.region = Rect2(i * 64, 0, 64, 64)
		sf.add_frame("a", at)
	var fx := AnimatedSprite2D.new()
	fx.sprite_frames = sf; fx.animation = "a"; fx.play()
	fx.z_index = 700; fx.scale = Vector2(2.0, 2.0); fx.position = pos + Vector2(0, -16)
	parent.add_child(fx)
	fx.animation_finished.connect(func(): if is_instance_valid(fx): fx.queue_free())

func hit(tool: String) -> void:
	if not is_instance_valid(_spr): return
	var tw := create_tween()
	match tool:
		"Axe":   # cây: nghiêng quanh gốc (ngọn rung)
			tw.tween_property(_spr, "rotation", 0.11, 0.05)
			tw.tween_property(_spr, "rotation", -0.11, 0.08)
			tw.tween_property(_spr, "rotation", 0.0, 0.07)
		_:   # Pickaxe (vàng) / Hammer (nhà): SQUASH nhẹ quanh CHÂN (chân giữ nguyên, ngọn lún 1 chút)
			tw.tween_property(_spr, "scale:y", 0.93, 0.06)
			tw.tween_property(_spr, "scale:y", 1.02, 0.08)
			tw.tween_property(_spr, "scale:y", 1.0, 0.07)
