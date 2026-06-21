class_name DebugNumbers extends Node2D
# Overlay debug: vẽ INDEX tile lên từng ô để user chỉ chính xác ô nào sai.
var items: Array = []   # mỗi item: {pos:Vector2, t:String, c:Color, s:int}
var _font: Font

func _draw() -> void:
	if _font == null: _font = load("res://fonts/MorrisRomanBlack.ttf")
	var font: Font = _font if _font != null else ThemeDB.fallback_font
	for it in items:
		draw_string(font, it.pos + Vector2(1, 1), it.t, HORIZONTAL_ALIGNMENT_LEFT, -1, it.s, Color(0, 0, 0, 0.85))
		draw_string(font, it.pos, it.t, HORIZONTAL_ALIGNMENT_LEFT, -1, it.s, it.c)
