class_name TSHeight extends RefCounted
# Lưới cao độ + chặn + dốc cho gameplay (giống HeightMap.cs bên Unity).
# cell = world/64 (Vector2i). level 0/1 (cao nguyên cho cung +tầm/+dmg). blocked = đá/nước/mép. ramp = ô dốc (đổi cao độ).

const CELL := 64

var level := {}     # Vector2i -> int
var blocked := {}   # Vector2i -> bool (đá/mép — ko đi)
var ramp := {}      # Vector2i -> bool
var walkable := {}  # Vector2i -> bool (ô ĐI ĐƯỢC: đất, ko đá/nước/mép)
var bldg := {}      # Vector2i -> bool (ô bị NHÀ chiếm — lính "ghost" (nông dân AI) đi xuyên được)

# Ô đi được; ghost=true thì coi cả ô NHÀ là đi được (đi xuyên nhà).
func passable(c: Vector2i, ghost: bool) -> bool:
	return walkable.get(c, false) or (ghost and bldg.has(c))

func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))

func center(c: Vector2i) -> Vector2:
	return Vector2(c.x + 0.5, c.y + 0.5) * CELL

func lvl(c: Vector2i) -> int: return level.get(c, 0)
func is_blocked(c: Vector2i) -> bool: return blocked.get(c, false)
func is_ramp(c: Vector2i) -> bool: return ramp.get(c, false)

func lvl_at(p: Vector2) -> int: return lvl(cell_of(p))

func step_ok(a: Vector2i, b: Vector2i, ghost := false) -> bool:
	if not passable(b, ghost): return false   # nước/đá/mép/ngoài đảo (ghost: bỏ qua nhà)
	if lvl(a) != lvl(b) and not is_ramp(a) and not is_ramp(b): return false
	return true

# A* 8 hướng từ start→goal (world). Trả Array[Vector2] tâm-ô; [] nếu ko tới / quá xa.
# A* (có heuristic) chỉ duyệt ~theo hướng đích → rẻ hơn BFS NHIỀU trên map to (BFS flood cả vùng).
const PF_CAP := 3500   # trần số ô duyệt → đích ko tới được (nước/đảo khác) ko làm flood cả map

func _heur(a: Vector2i, b: Vector2i) -> float:
	var dx: float = abs(a.x - b.x); var dy: float = abs(a.y - b.y)
	return maxf(dx, dy) + 0.414 * minf(dx, dy)   # octile (8 hướng)

func _hpush(h: Array, f: float, c: Vector2i) -> void:
	h.append([f, c])
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if h[p][0] <= h[i][0]: break
		var t = h[p]; h[p] = h[i]; h[i] = t; i = p

func _hpop(h: Array) -> Array:
	var top = h[0]
	var last = h.pop_back()
	if not h.is_empty():
		h[0] = last
		var i := 0; var n := h.size()
		while true:
			var l := 2 * i + 1; var r := 2 * i + 2; var s := i
			if l < n and h[l][0] < h[s][0]: s = l
			if r < n and h[r][0] < h[s][0]: s = r
			if s == i: break
			var t = h[s]; h[s] = h[i]; h[i] = t; i = s
	return top

func find_path(start_w: Vector2, goal_w: Vector2, ghost := false) -> Array:
	var si := cell_of(start_w)
	var gi := cell_of(goal_w)
	if si == gi or not passable(gi, ghost):
		return []
	var dirs := [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),
				 Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]
	var g := {si: 0.0}
	var prev := {si: si}
	var closed := {}
	var open: Array = []
	_hpush(open, _heur(si, gi), si)
	var found := false
	var visited := 0
	while not open.is_empty():
		var cur: Vector2i = _hpop(open)[1]
		if cur == gi: found = true; break
		if closed.has(cur): continue
		closed[cur] = true
		visited += 1
		if visited > PF_CAP: break   # đích ko tới được → bỏ (tránh flood cả map)
		var gc: float = g[cur]
		for d in dirs:
			var nb: Vector2i = cur + d
			if closed.has(nb) or not step_ok(cur, nb, ghost): continue
			if d.x != 0 and d.y != 0:
				if not step_ok(cur, Vector2i(cur.x + d.x, cur.y), ghost) and not step_ok(cur, Vector2i(cur.x, cur.y + d.y), ghost):
					continue
			var ng: float = gc + (1.414 if (d.x != 0 and d.y != 0) else 1.0)
			if not g.has(nb) or ng < g[nb]:
				g[nb] = ng; prev[nb] = cur
				_hpush(open, ng + _heur(nb, gi), nb)
	if not found: return []
	var path: Array = []
	var c := gi
	while c != si:
		path.append(center(c))
		c = prev[c]
	path.reverse()
	return path

# Ô cao nguyên (level1, ko dốc) gần nhất tới được từ 'from' — cho archer leo lên. null nếu ko có.
func nearest_high(from_w: Vector2):
	var si := cell_of(from_w)
	var seen := {si: true}
	var q: Array[Vector2i] = [si]
	var head := 0
	var dirs := [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]
	while head < q.size():
		var cur: Vector2i = q[head]; head += 1
		if lvl(cur) == 1 and not is_ramp(cur):
			return center(cur)
		for d in dirs:
			var nb: Vector2i = cur + d
			if seen.has(nb) or not step_ok(cur, nb): continue
			seen[nb] = true; q.append(nb)
	return null
