extends Node2D
## Draws the split-screen scene procedurally:
## upper half = landscape with a tree, lower half = 8x8 soil grid with roots and large water banks.
## Supports vertical scrolling into deeper soil layers via mouse wheel (or MMB drag).
## Roots follow a tapering width rule:
## - Initial tree roots: natural organic spread, initial main root width 4 cells.
## - Extended roots: width 4 (length 10) -> width 3 (length 15) -> width 2 (length 20) -> width 1 (length 25).
## When roots touch a water bank, water drains smoothly from top to down:
## Layer drain time = width * 0.4 seconds.
## Each active layer's pixels smoothly shrink/fade down from their top.

const SKY_TOP := Color("4a90d9")
const SKY_HORIZON := Color("bfe3f5")
const SUN := Color("fff2a8")
const HILL_FAR := Color("7fae6a")
const HILL_NEAR := Color("5e9a4c")
const GRASS := Color("4f8a3c")
const SOIL_TOP := Color("7a4e2d")
const SOIL_BOTTOM := Color("2c1508")
const TRUNK := Color("6b4423")
const LEAVES_DARK := Color("2f6b2a")
const LEAVES := Color("3f8a36")
const LEAVES_LIGHT := Color("58a84a")

const WATER_COLOR := Color("2980b9")
const WATER_EDGE := Color("1f5f8b")
const ROOT_COLOR := Color("d8a36a")

const TILE_SIZE := 8.0
const TOTAL_SOIL_ROWS := 100
const SCROLL_SPEED := 24.0

const LEN_W4 := 10
const LEN_W3 := 15
const LEN_W2 := 20
const LEN_W1 := 25
const MAX_ROOT_STEPS := LEN_W4 + LEN_W3 + LEN_W2 + LEN_W1

# Water banks: array of Dictionary:
# {
#   "rect": Rect2i(x, y, w, h), # in cell coordinates
#   "drained_layers": int,       # fully disappeared top layers
#   "drain_timer": float,        # timer accumulator for current top layer (0.0 to layer_time)
#   "layer_time": float          # time per layer = w * 0.4
# }
var _water_banks: Array = []
# Fast lookup of original water cells: Vector2i -> bank_index
var _water_bank_lookup: Dictionary = {}

# Initial root cells: Vector2i -> true
var _initial_root_tiles: Dictionary = {}
# Extension nodes: Dictionary of Vector2i -> int (depth: 1 to 70)
var _root_tiles: Dictionary = {}

var _is_lmb_down: bool = false
var _is_mmb_down: bool = false
var _soil_scroll_y: float = 0.0


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	get_viewport().size_changed.connect(_on_size_changed)
	_generate_world()


func _process(delta: float) -> void:
	var needs_redraw := false

	for bank in _water_banks:
		var rect: Rect2i = bank["rect"]
		var drained: int = bank["drained_layers"]
		if drained >= rect.size.y:
			continue # Bank is fully drained

		if _is_root_touching_bank(bank):
			bank["drain_timer"] += delta
			var layer_time: float = bank["layer_time"]

			while bank["drain_timer"] >= layer_time and bank["drained_layers"] < rect.size.y:
				bank["drain_timer"] -= layer_time
				bank["drained_layers"] += 1

			needs_redraw = true

	if needs_redraw:
		queue_redraw()


func _is_root_touching_bank(bank: Dictionary) -> bool:
	var rect: Rect2i = bank["rect"]
	var drained: int = bank["drained_layers"]
	var water_min_y := rect.position.y + drained
	var water_max_y := rect.position.y + rect.size.y - 1
	var water_min_x := rect.position.x
	var water_max_x := rect.position.x + rect.size.x - 1

	if water_min_y > water_max_y:
		return false

	# Check the 1-cell perimeter / neighbors around the remaining water area
	for y in range(water_min_y - 1, water_max_y + 2):
		for x in range(water_min_x - 1, water_max_x + 2):
			if x >= water_min_x and x <= water_max_x and y >= water_min_y and y <= water_max_y:
				continue
			var cell := Vector2i(x, y)
			if _initial_root_tiles.has(cell) or _root_tiles.has(cell):
				return true

	return false


func _on_size_changed() -> void:
	_generate_world()
	_clamp_scroll()
	queue_redraw()


func _max_scroll_y() -> float:
	var size := get_viewport_rect().size
	var mid := size.y * 0.5
	var visible_soil_height := size.y - mid
	var total_height := TOTAL_SOIL_ROWS * TILE_SIZE
	return maxf(0.0, total_height - visible_soil_height)


func _clamp_scroll() -> void:
	_soil_scroll_y = clampf(_soil_scroll_y, 0.0, _max_scroll_y())


func _unhandled_input(event: InputEvent) -> void:
	var size := get_viewport_rect().size
	var mid := size.y * 0.5

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_is_lmb_down = event.pressed
			if _is_lmb_down:
				_interact_at_pos(event.position)

		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_mmb_down = event.pressed

		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if event.position.y >= mid:
				_soil_scroll_y += SCROLL_SPEED
				_clamp_scroll()
				queue_redraw()

		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if event.position.y >= mid:
				_soil_scroll_y -= SCROLL_SPEED
				_clamp_scroll()
				queue_redraw()

	elif event is InputEventMouseMotion:
		if _is_lmb_down:
			_interact_at_pos(event.position)
		if _is_mmb_down and event.position.y >= mid:
			_soil_scroll_y -= event.relative.y
			_clamp_scroll()
			queue_redraw()

	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			var mode := DisplayServer.window_get_mode()
			if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _get_neighbor_min_depth(cell: Vector2i) -> int:
	var min_d := 999999
	var found := false

	var neighbors := [
		cell + Vector2i(1, 0),
		cell + Vector2i(-1, 0),
		cell + Vector2i(0, 1),
		cell + Vector2i(0, -1),
		cell + Vector2i(1, 1),
		cell + Vector2i(-1, 1),
		cell + Vector2i(1, -1),
		cell + Vector2i(-1, -1)
	]

	for n in neighbors:
		if _initial_root_tiles.has(n):
			return 0
		if _root_tiles.has(n):
			var d: int = _root_tiles[n]
			if d < min_d:
				min_d = d
			found = true

	return min_d if found else -1


func _get_width_for_depth(depth: int) -> int:
	if depth <= LEN_W4:
		return 4
	elif depth <= LEN_W4 + LEN_W3:
		return 3
	elif depth <= LEN_W4 + LEN_W3 + LEN_W2:
		return 2
	elif depth <= MAX_ROOT_STEPS:
		return 1
	else:
		return 0


func _is_cell_water(cell: Vector2i) -> bool:
	if not _water_bank_lookup.has(cell):
		return false
	var bank_idx: int = _water_bank_lookup[cell]
	var bank: Dictionary = _water_banks[bank_idx]
	var rect: Rect2i = bank["rect"]
	var current_top: int = rect.position.y + bank["drained_layers"]
	# If this cell's row is above current top, water has already faded away
	return cell.y >= current_top


func _interact_at_pos(screen_pos: Vector2) -> void:
	var size := get_viewport_rect().size
	var mid := size.y * 0.5
	if screen_pos.y < mid or screen_pos.y >= size.y or screen_pos.x < 0 or screen_pos.x >= size.x:
		return

	var soil_relative_y := (screen_pos.y - mid) + _soil_scroll_y
	var col := int(screen_pos.x / TILE_SIZE)
	var row := int(soil_relative_y / TILE_SIZE)
	if row < 0 or row >= TOTAL_SOIL_ROWS:
		return

	var cell := Vector2i(col, row)

	if _is_cell_water(cell) or _initial_root_tiles.has(cell) or _root_tiles.has(cell):
		return

	var parent_depth := _get_neighbor_min_depth(cell)
	if parent_depth == -1:
		return

	var new_depth := parent_depth + 1
	if new_depth > MAX_ROOT_STEPS:
		return

	var w := _get_width_for_depth(new_depth)
	if w <= 0:
		return

	var half_w := int(w / 2)
	var changed := false
	for r_offset in range(-half_w, -half_w + w):
		for c_offset in range(-half_w, -half_w + w):
			var target := cell + Vector2i(c_offset, r_offset)
			if target.y < 0 or target.y >= TOTAL_SOIL_ROWS:
				continue
			if _is_cell_water(target) or _initial_root_tiles.has(target):
				continue
			if not _root_tiles.has(target):
				_root_tiles[target] = new_depth
				changed = true

	if changed:
		queue_redraw()


func _generate_world() -> void:
	var size := get_viewport_rect().size
	var cols := int(ceil(size.x / TILE_SIZE))
	var rows := TOTAL_SOIL_ROWS
	if cols <= 10 or rows <= 10:
		return

	_generate_water_sources(cols, rows)
	_generate_initial_roots(cols)


func _add_brush_tiles(cx: int, cy: int, width: int) -> void:
	var half := int(width / 2)
	for ro in range(-half, -half + width):
		for co in range(-half, -half + width):
			var pos := Vector2i(cx + co, cy + ro)
			if pos.y >= 0 and pos.y < TOTAL_SOIL_ROWS:
				_initial_root_tiles[pos] = true


func _generate_initial_roots(cols: int) -> void:
	_initial_root_tiles.clear()
	_root_tiles.clear()
	var center_col := int(cols * 0.5)

	# Main stem root: 4 cells wide at the top, naturally tapering and descending
	for r in 15:
		var w := 4 if r < 7 else (3 if r < 12 else 2)
		_add_brush_tiles(center_col, r, w)

	# Left lateral root branch
	var lx := center_col - 2
	for r in range(2, 13):
		if r % 2 == 0:
			lx -= 1
		var w := 3 if r < 6 else 2
		_add_brush_tiles(lx, r, w)

	# Left secondary fork
	var lfx := center_col - 4
	for r in range(6, 12):
		lfx -= 1
		_add_brush_tiles(lfx, r, 2)

	# Right lateral root branch
	var rx := center_col + 2
	for r in range(3, 14):
		if r % 2 == 1:
			rx += 1
		var w := 3 if r < 7 else 2
		_add_brush_tiles(rx, r, w)

	# Right secondary fork
	var rfx := center_col + 4
	for r in range(7, 13):
		rfx += 1
		_add_brush_tiles(rfx, r, 2)


func _generate_water_sources(cols: int, rows: int) -> void:
	_water_banks.clear()
	_water_bank_lookup.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337

	var num_sources := clampi(int(cols * rows / 400), 5, 18)

	for s in num_sources:
		var w := rng.randi_range(8, 14)
		var min_h := int(ceil(64.0 / float(w)))
		var h := rng.randi_range(min_h, min_h + 3)

		var origin_x := rng.randi_range(2, maxi(cols - w - 2, 2))
		var origin_y := rng.randi_range(16, maxi(rows - h - 2, 16))

		var rect := Rect2i(origin_x, origin_y, w, h)
		var layer_time := float(w) * 0.4
		var bank_idx := _water_banks.size()

		_water_banks.append({
			"rect": rect,
			"drained_layers": 0,
			"drain_timer": 0.0,
			"layer_time": layer_time
		})

		for r in h:
			for c in w:
				_water_bank_lookup[Vector2i(origin_x + c, origin_y + r)] = bank_idx


func _draw() -> void:
	var size := get_viewport_rect().size
	var mid := size.y * 0.5
	_draw_sky(size, mid)
	_draw_hills(size, mid)
	_draw_tree(Vector2(size.x * 0.5, mid), mid)
	_draw_soil_grid(size, mid)


func _draw_sky(size: Vector2, mid: float) -> void:
	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, mid), Vector2(0, mid)]),
		PackedColorArray([SKY_TOP, SKY_TOP, SKY_HORIZON, SKY_HORIZON])
	)
	var sun_pos := Vector2(size.x * 0.82, mid * 0.25)
	var r := mid * 0.1
	draw_circle(sun_pos, r * 1.5, Color(SUN, 0.25))
	draw_circle(sun_pos, r, SUN)


func _draw_hills(size: Vector2, mid: float) -> void:
	_draw_wave(size.x, mid, mid * 0.72, mid * 0.08, 1.3, 0.0, HILL_FAR)
	_draw_wave(size.x, mid, mid * 0.82, mid * 0.06, 2.1, 1.7, HILL_NEAR)
	draw_rect(Rect2(0, mid * 0.94, size.x, mid * 0.06), GRASS)


func _draw_wave(width: float, bottom: float, base_y: float, amp: float, freq: float, phase: float, color: Color) -> void:
	var pts := PackedVector2Array()
	var steps := 48
	for i in steps + 1:
		var x := width * i / steps
		pts.append(Vector2(x, base_y - sin(x / width * TAU * freq + phase) * amp))
	pts.append(Vector2(width, bottom))
	pts.append(Vector2(0, bottom))
	draw_colored_polygon(pts, color)


func _draw_tree(base: Vector2, mid: float) -> void:
	var h := mid * 0.6
	var w := h * 0.1
	# Trunk (slightly tapered)
	draw_colored_polygon(PackedVector2Array([
		base + Vector2(-w * 0.7, 0), base + Vector2(w * 0.7, 0),
		base + Vector2(w * 0.4, -h * 0.6), base + Vector2(-w * 0.4, -h * 0.6),
	]), TRUNK)
	# Canopy: layered circles for depth
	var c := base + Vector2(0, -h * 0.72)
	var r := h * 0.22
	for o in [Vector2(-1.1, 0.4), Vector2(1.1, 0.4), Vector2(0, 0.6)]:
		draw_circle(c + o * r, r, LEAVES_DARK)
	for o in [Vector2(-0.7, -0.3), Vector2(0.7, -0.3), Vector2(0, -0.9), Vector2(0, 0.1)]:
		draw_circle(c + o * r, r, LEAVES)
	draw_circle(c + Vector2(-0.3, -0.8) * r, r * 0.5, LEAVES_LIGHT)


func _draw_soil_grid(size: Vector2, mid: float) -> void:
	var cols := int(ceil(size.x / TILE_SIZE))
	var visible_soil_height := size.y - mid

	var start_row := maxi(0, int(floor(_soil_scroll_y / TILE_SIZE)))
	var end_row := mini(TOTAL_SOIL_ROWS - 1, int(ceil((_soil_scroll_y + visible_soil_height) / TILE_SIZE)))

	var grid_edge_color := Color(0.0, 0.0, 0.0, 0.12)
	var highlight_edge_color := Color(1.0, 1.0, 1.0, 0.05)

	for row in range(start_row, end_row + 1):
		var y := mid + (row * TILE_SIZE - _soil_scroll_y)
		var t_vertical := float(row) / float(TOTAL_SOIL_ROWS - 1)
		var base_row_color := SOIL_TOP.lerp(SOIL_BOTTOM, clampf(t_vertical, 0.0, 1.0))

		for col in cols:
			var x := col * TILE_SIZE
			var cell := Vector2i(col, row)
			var tile_rect := Rect2(Vector2(x, y), Vector2(TILE_SIZE, TILE_SIZE))

			var is_root: bool = _initial_root_tiles.has(cell) or _root_tiles.has(cell)

			# 1. Base tile rendering: Soil or Root
			var base_tile_color := ROOT_COLOR if is_root else base_row_color
			draw_rect(tile_rect, base_tile_color)

			# 2. Bevel lines for soil/root
			draw_line(Vector2(x, y), Vector2(x + TILE_SIZE, y), highlight_edge_color, 1.0)
			draw_line(Vector2(x, y), Vector2(x, y + TILE_SIZE), highlight_edge_color, 1.0)
			draw_line(Vector2(x, y + TILE_SIZE), Vector2(x + TILE_SIZE, y + TILE_SIZE), grid_edge_color, 1.0)
			draw_line(Vector2(x + TILE_SIZE, y), Vector2(x + TILE_SIZE, y + TILE_SIZE), grid_edge_color, 1.0)

			# 3. Water overlay with top-to-bottom pixel fade/shrink
			if _water_bank_lookup.has(cell):
				var bank_idx: int = _water_bank_lookup[cell]
				var bank: Dictionary = _water_banks[bank_idx]
				var rect: Rect2i = bank["rect"]
				var current_top_layer: int = rect.position.y + bank["drained_layers"]

				if row < current_top_layer:
					# Layer is already fully drained, soil below shows through
					pass
				elif row == current_top_layer:
					# Actively draining layer: recedes down from top with constant solid water color
					var drain_ratio := clampf(bank["drain_timer"] / bank["layer_time"], 0.0, 1.0)
					var remaining_fraction := 1.0 - drain_ratio
					var h := TILE_SIZE * remaining_fraction
					var offset_y := TILE_SIZE * drain_ratio # shrinks downward from the top

					if h > 0.001:
						var water_subrect := Rect2(Vector2(x, y + offset_y), Vector2(TILE_SIZE, h))
						draw_rect(water_subrect, WATER_COLOR)
						draw_rect(water_subrect, WATER_EDGE, false, 0.75)
				else:
					# Untouched water layers below
					draw_rect(tile_rect, WATER_COLOR)
					draw_rect(tile_rect, WATER_EDGE, false, 0.75)

	# Scrollbar indicator on the right edge
	var scroll_track_h := visible_soil_height
	var max_s := _max_scroll_y()
	if max_s > 0.0:
		var thumb_h := maxf(24.0, scroll_track_h * (visible_soil_height / (TOTAL_SOIL_ROWS * TILE_SIZE)))
		var thumb_y := mid + (_soil_scroll_y / max_s) * (scroll_track_h - thumb_h)
		draw_rect(Rect2(size.x - 5.0, thumb_y, 4.0, thumb_h), Color(1, 1, 1, 0.35))
