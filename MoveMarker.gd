class_name MoveMarker extends Node2D
# Hiệu ứng "marker" vẽ bằng code. 3 kiểu:
#   "move"   : vòng XANH loang + chevron chỉ xuống (đi thường)
#   "attack" : vòng ĐỎ loang + chevron (đánh địch / nhà địch)
#   "tool"   : vòng VÀNG loang + ICON công cụ (rìu/cuốc/búa/dao) rơi vào (nông dân lấy resource)
const DUR := 0.55
var _t := 0.0
var mode := "move"     # "move" | "attack" | "tool"
var tool := ""         # khi mode=="tool": Axe | Pickaxe | Hammer | Knife
var _col := Color(0.45, 1.0, 0.55)

func _ready() -> void:
	if mode == "attack": _col = Color(1.0, 0.32, 0.30)
	elif mode == "tool": _col = Color(1.0, 0.82, 0.30)

func _process(delta: float) -> void:
	_t += delta / DUR
	if _t >= 1.0:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var a: float = 1.0 - _t
	# vòng tròn loang ra rồi mờ
	var r: float = 10.0 + _t * 34.0
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(_col.r, _col.g, _col.b, a * 0.9), 4.0, true)
	var drop: float = -34.0 * (1.0 - _t)
	if mode == "tool":
		_draw_tool(Vector2(0.0, drop - 6.0), a)
	else:
		# chevron chỉ XUỐNG, rơi từ trên vào điểm
		var tip := Vector2(0.0, drop)
		var pts := PackedVector2Array([tip + Vector2(-13, -16), tip, tip + Vector2(13, -16)])
		draw_polyline(pts, Color(_col.r, _col.g, _col.b, a), 6.0, true)

# Vẽ icon công cụ đơn giản, tâm icon ở `c`.
func _draw_tool(c: Vector2, a: float) -> void:
	var wood := Color(0.58, 0.38, 0.20, a)
	var metal := Color(0.84, 0.87, 0.92, a)
	match tool:
		"Axe":   # rìu: cán chéo + lưỡi tam giác
			draw_line(c + Vector2(-7, 11), c + Vector2(5, -9), wood, 4.0, true)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(3, -12), c + Vector2(14, -7), c + Vector2(11, 1), c + Vector2(1, -4)]), metal)
		"Pickaxe":   # cuốc/mỏ: cán dọc + đầu hình V hai mũi
			draw_line(c + Vector2(0, 12), c + Vector2(0, -7), wood, 4.0, true)
			draw_polyline(PackedVector2Array([
				c + Vector2(-13, -3), c + Vector2(0, -9), c + Vector2(13, -3)]), metal, 4.0, true)
		"Hammer":   # búa: cán dọc + đầu chữ nhật
			draw_line(c + Vector2(0, 12), c + Vector2(0, -6), wood, 4.0, true)
			draw_rect(Rect2(c + Vector2(-10, -13), Vector2(20, 9)), metal)
		"Knife":   # dao nhỏ: cán + lưỡi nhọn
			draw_line(c + Vector2(-7, 11), c + Vector2(-1, 3), wood, 4.0, true)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-2, 5), c + Vector2(2, 1), c + Vector2(11, -12), c + Vector2(3, -7)]), metal)
		_:
			draw_circle(c, 6.0, metal)
