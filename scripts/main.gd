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

# Rocks in soil:
# _rocks: Array of Dictionary { "pos": Vector2i(col, row), "src_rect": Rect2 }
var _rocks: Array = []
# Solid cells occupied by rock pixels: Vector2i(col, row) -> true
var _rock_cells: Dictionary = {}
const ROCK_SPRITE_SIZE := 16
const ROCK_SCALE := 1.0 / 3.0
const ROCK_GRID_SPAN := 6 # ceil(16 / 3)
# Only plain stone variants without orange or green/teal colors around them
const VALID_ROCK_VARIANTS := [
	Vector2i(0, 0),
	Vector2i(0, 1),
	Vector2i(1, 1),
	Vector2i(2, 1),
	Vector2i(3, 1)
]
var _rocks_texture: Texture2D = null
var _rocks_image: Image = null

var _is_lmb_down: bool = false
var _is_mmb_down: bool = false
var _has_last_drag_cell: bool = false
var _last_drag_cell: Vector2i = Vector2i.ZERO
var _soil_scroll_y: float = 0.0

# Water collection & Leaf spritesheet configuration
const SPRITE_SIZE := 40
const SPRITE_RECT_SMALLROOT := Rect2(0, 0, 40, 40)
const SPRITE_RECT_BIGROOT := Rect2(40, 0, 40, 40)
const SPRITE_RECT_MIDLEAVES := Rect2(80, 0, 40, 40)
const SPRITE_RECT_LARGELEAVES := Rect2(0, 40, 40, 40)
const SPRITE_RECT_SMALLLEAVES := Rect2(40, 40, 40, 40)
const SPRITE_RECT_DRYLEAVES := Rect2(80, 40, 40, 40)

# Water depletion rate when no active connection to water:
# Tree loses 1.5 water per second when not actively connected to water.
const WATER_DECAY_RATE := 1.5

const MAX_TREE_HEALTH := 100.0
# Health decay rate per second when disconnected from water
const HEALTH_DECAY_RATE := 3.0
# Health recovery rate per second when sucking water
const HEALTH_REGEN_RATE := 8.0

var _tree_texture: Texture2D = null
var _vt323_font: Font = null
var _water_stored: float = 0.0
var _tree_health: float = 25.0 # Starts at initial stage (small dry tree)
var _is_connected_to_water: bool = false
var _active_water_intake_rate: float = 0.0

# Wind & Leaf oscillation configuration
const WIND_SWAY_FREQ := 5.5
const WIND_MAX_SWAY_PX := 2.5 # Max leaf sway in sprite pixels
var _wind_time: float = 0.0
var _wind_strength: float = 0.0
var _wind_target_strength: float = 0.8
var _wind_direction: float = 1.0 # 1.0 = blowing right, -1.0 = blowing left
var _wind_state_timer: float = 4.0
var _wind_gust_particles: Array = []
var _leaf_particles: Array = []
var _leaf_spawn_timer: float = 0.0
var _wind_rng := RandomNumberGenerator.new()

# Exact leaf sprite colors from tree.png
const SPRITE_LEAF_GREEN := Color8(143, 222, 93, 255)
const SPRITE_LEAF_DRY_YELLOW := Color8(237, 193, 62, 255)
const SPRITE_LEAF_DRY_ORANGE := Color8(242, 166, 94, 255)

# Cross-dissolve state for smooth leaf and trunk transitions
const DISSOLVE_DURATION := 0.55
var _current_leaf_rect: Rect2 = SPRITE_RECT_SMALLLEAVES
var _prev_leaf_rect: Rect2 = SPRITE_RECT_SMALLLEAVES
var _current_leaf_offset_px: float = 0.0
var _prev_leaf_offset_px: float = 0.0
var _leaf_dissolve_t: float = 1.0

var _current_trunk_rect: Rect2 = SPRITE_RECT_SMALLROOT
var _prev_trunk_rect: Rect2 = SPRITE_RECT_SMALLROOT
var _trunk_dissolve_t: float = 1.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	if ResourceLoader.exists("res://assets/tree.png"):
		_tree_texture = load("res://assets/tree.png")
	if ResourceLoader.exists("res://assets/Rocks.png"):
		_rocks_texture = load("res://assets/Rocks.png")
		if _rocks_texture:
			_rocks_image = _rocks_texture.get_image()
	_vt323_font = load("res://assets/VT323-Regular.ttf")
	_wind_rng.randomize()
	get_viewport().size_changed.connect(_on_size_changed)
	_generate_world()
	_init_wind_particles()


func _process(delta: float) -> void:
	var needs_redraw := false
	var intake_this_frame := 0.0
	var connected_now := false

	for bank in _water_banks:
		var rect: Rect2i = bank["rect"]
		var drained: int = bank["drained_layers"]
		if drained >= rect.size.y:
			continue # Bank is fully drained

		if _is_root_touching_bank(bank):
			connected_now = true
			var layer_time: float = bank["layer_time"]
			# Drain rate in water cells per second = width / layer_time = 1.0 / 0.4 = 2.5 cells/sec
			var cells_per_second: float = float(rect.size.x) / layer_time
			var absorbed: float = cells_per_second * delta
			_water_stored = minf(_water_stored + absorbed, 200.0)
			intake_this_frame += cells_per_second

			bank["drain_timer"] += delta
			while bank["drain_timer"] >= layer_time and bank["drained_layers"] < rect.size.y:
				bank["drain_timer"] -= layer_time
				bank["drained_layers"] += 1

			needs_redraw = true

	_is_connected_to_water = connected_now
	_active_water_intake_rate = intake_this_frame

	# When connected to water, health increases; when disconnected, health decreases over time
	if connected_now:
		var old_hp := _tree_health
		_tree_health = minf(MAX_TREE_HEALTH, _tree_health + HEALTH_REGEN_RATE * delta)
		if not is_equal_approx(old_hp, _tree_health):
			needs_redraw = true
	else:
		if _water_stored > 0.0:
			_water_stored = maxf(0.0, _water_stored - WATER_DECAY_RATE * delta)
		var old_hp := _tree_health
		_tree_health = maxf(0.0, _tree_health - HEALTH_DECAY_RATE * delta)
		if not is_equal_approx(old_hp, _tree_health):
			needs_redraw = true

	if _update_wind(delta):
		needs_redraw = true

	if _update_tree_transitions(delta):
		needs_redraw = true

	if _update_leaf_particles(delta):
		needs_redraw = true

	if needs_redraw:
		queue_redraw()


func _get_target_leaf_rect() -> Rect2:
	if _tree_health <= 15.0:
		return SPRITE_RECT_DRYLEAVES
	elif _tree_health < 50.0:
		return SPRITE_RECT_SMALLLEAVES
	elif _tree_health < 85.0:
		return SPRITE_RECT_MIDLEAVES
	else:
		return SPRITE_RECT_LARGELEAVES


func _get_target_trunk_rect() -> Rect2:
	return SPRITE_RECT_BIGROOT if _tree_health >= 50.0 else SPRITE_RECT_SMALLROOT


func _get_target_leaf_offset_px(leaf_rect: Rect2, is_big_root: bool) -> float:
	if not is_big_root:
		return 0.0
	return 3.0 if leaf_rect == SPRITE_RECT_MIDLEAVES else 5.0


func _update_tree_transitions(delta: float) -> bool:
	var changed := false
	var target_leaf := _get_target_leaf_rect()
	var target_trunk := _get_target_trunk_rect()
	var is_big_root := target_trunk == SPRITE_RECT_BIGROOT
	var target_offset_px := _get_target_leaf_offset_px(target_leaf, is_big_root)

	if target_leaf != _current_leaf_rect or not is_equal_approx(target_offset_px, _current_leaf_offset_px):
		_prev_leaf_rect = _current_leaf_rect
		_prev_leaf_offset_px = _current_leaf_offset_px
		_current_leaf_rect = target_leaf
		_current_leaf_offset_px = target_offset_px
		_leaf_dissolve_t = 0.0
		changed = true

	if target_trunk != _current_trunk_rect:
		_prev_trunk_rect = _current_trunk_rect
		_current_trunk_rect = target_trunk
		_trunk_dissolve_t = 0.0
		changed = true

	if _leaf_dissolve_t < 1.0:
		_leaf_dissolve_t = minf(1.0, _leaf_dissolve_t + delta / DISSOLVE_DURATION)
		changed = true

	if _trunk_dissolve_t < 1.0:
		_trunk_dissolve_t = minf(1.0, _trunk_dissolve_t + delta / DISSOLVE_DURATION)
		changed = true

	return changed


func _pick_current_leaf_color() -> Color:
	if _tree_health <= 15.0:
		var r := _wind_rng.randf()
		if r < 0.55:
			return SPRITE_LEAF_DRY_YELLOW
		elif r < 0.88:
			return SPRITE_LEAF_DRY_ORANGE
		else:
			return SPRITE_LEAF_GREEN
	return SPRITE_LEAF_GREEN


func _update_leaf_particles(delta: float) -> bool:
	var size := get_viewport_rect().size
	var mid := size.y * 0.5
	var changed := false

	# Spawn flying leaves from canopy when wind is active
	if _wind_strength > 0.12 and size.x > 10.0:
		var spawn_rate := 1.5 + _wind_strength * 6.5
		_leaf_spawn_timer += delta * spawn_rate
		while _leaf_spawn_timer >= 1.0:
			_leaf_spawn_timer -= 1.0
			var cols := int(ceil(size.x / TILE_SIZE))
			var center_col := int(cols * 0.5)
			var root_left_screen_x := float(center_col - 2) * TILE_SIZE
			var dest_pos := Vector2(root_left_screen_x - 17.0 * TILE_SIZE, mid - 37.0 * TILE_SIZE)
			# Canopy area in sprite coordinates is roughly x: 5..35, y: 4..25
			var spawn_x := dest_pos.x + _wind_rng.randf_range(6.0, 34.0) * TILE_SIZE
			var spawn_y := dest_pos.y + _wind_rng.randf_range(5.0, 24.0) * TILE_SIZE - _current_leaf_offset_px * TILE_SIZE
			_leaf_particles.append({
				"x": spawn_x,
				"y": spawn_y,
				"vx": _wind_rng.randf_range(90.0, 175.0),
				"vy": _wind_rng.randf_range(12.0, 36.0),
				"phase": _wind_rng.randf_range(0.0, TAU),
				"freq": _wind_rng.randf_range(3.5, 6.5),
				"color": _pick_current_leaf_color(),
				"age": 0.0,
				"max_age": _wind_rng.randf_range(3.0, 5.5)
			})
			changed = true

	for i in range(_leaf_particles.size() - 1, -1, -1):
		var lp: Dictionary = _leaf_particles[i]
		lp["age"] += delta
		var wind_drive := maxf(_wind_strength, 0.2)
		lp["x"] += _wind_direction * lp["vx"] * wind_drive * delta
		lp["y"] += (lp["vy"] + sin(_wind_time * lp["freq"] + lp["phase"]) * 28.0) * delta
		changed = true

		if lp["age"] >= lp["max_age"] or lp["y"] >= mid - TILE_SIZE * 0.5 or lp["x"] < -32.0 or lp["x"] > size.x + 32.0:
			_leaf_particles.remove_at(i)

	return changed


func _init_wind_particles() -> void:
	_wind_gust_particles.clear()
	var size := get_viewport_rect().size
	var mid := maxf(size.y * 0.5, 200.0)
	var width := maxf(size.x, 400.0)
	for i in 14:
		_wind_gust_particles.append({
			"x": _wind_rng.randf_range(0.0, width),
			"y": _wind_rng.randf_range(mid * 0.1, mid * 0.9),
			"len": _wind_rng.randf_range(28.0, 65.0),
			"speed": _wind_rng.randf_range(140.0, 260.0),
			"alpha": _wind_rng.randf_range(0.18, 0.42)
		})


func _update_wind(delta: float) -> bool:
	_wind_state_timer -= delta
	if _wind_state_timer <= 0.0:
		# Alternate between windy gusts and calm intervals
		if _wind_target_strength > 0.15:
			# Switch to calm or light breeze
			_wind_target_strength = 0.0 if _wind_rng.randf() < 0.55 else _wind_rng.randf_range(0.25, 0.5)
			_wind_state_timer = _wind_rng.randf_range(2.5, 5.0)
		else:
			# Trigger a wind gust
			_wind_target_strength = _wind_rng.randf_range(0.65, 1.0)
			_wind_direction = -1.0 if _wind_rng.randf() < 0.5 else 1.0
			_wind_state_timer = _wind_rng.randf_range(3.5, 6.5)

	var prev_strength := _wind_strength
	_wind_strength = move_toward(_wind_strength, _wind_target_strength, delta * 0.65)

	if _wind_strength > 0.01:
		_wind_time += delta * (0.6 + _wind_strength * 0.8)
		var size := get_viewport_rect().size
		var mid := size.y * 0.5
		for p in _wind_gust_particles:
			p["x"] += _wind_direction * p["speed"] * _wind_strength * delta
			if _wind_direction > 0.0 and p["x"] > size.x + p["len"]:
				p["x"] = -p["len"]
				p["y"] = _wind_rng.randf_range(mid * 0.08, mid * 0.92)
			elif _wind_direction < 0.0 and p["x"] < -p["len"]:
				p["x"] = size.x + p["len"]
				p["y"] = _wind_rng.randf_range(mid * 0.08, mid * 0.92)
		return true

	return not is_equal_approx(prev_strength, _wind_strength)


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
	_init_wind_particles()
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
				_has_last_drag_cell = false
				_interact_at_pos(event.position)
			else:
				_has_last_drag_cell = false

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
		_has_last_drag_cell = false
		return

	var soil_relative_y := (screen_pos.y - mid) + _soil_scroll_y
	var col := int(screen_pos.x / TILE_SIZE)
	var row := int(soil_relative_y / TILE_SIZE)
	if row < 0 or row >= TOTAL_SOIL_ROWS:
		_has_last_drag_cell = false
		return

	var target_cell := Vector2i(col, row)
	var changed := false

	if _has_last_drag_cell:
		# Step cell-by-cell along the drag line so fast mouse movement never skips tiles
		var diff := target_cell - _last_drag_cell
		var steps := maxi(absi(diff.x), absi(diff.y))
		for s in range(1, steps + 1):
			var t := float(s) / float(steps)
			var interp_cell := Vector2i(
				roundi(lerpf(float(_last_drag_cell.x), float(target_cell.x), t)),
				roundi(lerpf(float(_last_drag_cell.y), float(target_cell.y), t))
			)
			if _try_extend_root_at_cell(interp_cell):
				changed = true
	else:
		if _try_extend_root_at_cell(target_cell):
			changed = true

	_last_drag_cell = target_cell
	_has_last_drag_cell = true

	if changed:
		queue_redraw()


func _try_extend_root_at_cell(cell: Vector2i) -> bool:
	if cell.y < 0 or cell.y >= TOTAL_SOIL_ROWS:
		return false
	if _is_cell_water(cell) or _rock_cells.has(cell):
		return false

	# Find minimum depth among existing root tiles in or adjacent to this cell
	# (Checking cell itself allows continuous extension when the previous step's brush covered this cell)
	var parent_depth := _get_neighbor_min_depth(cell)
	if _initial_root_tiles.has(cell):
		parent_depth = 0
	elif _root_tiles.has(cell):
		var self_d: int = _root_tiles[cell]
		if parent_depth == -1 or self_d < parent_depth:
			parent_depth = self_d

	if parent_depth == -1:
		return false

	var new_depth := parent_depth + 1
	if new_depth > MAX_ROOT_STEPS:
		return false

	var w := _get_width_for_depth(new_depth)
	if w <= 0:
		return false

	var half_w := int(w / 2)
	var changed := false
	for r_offset in range(-half_w, -half_w + w):
		for c_offset in range(-half_w, -half_w + w):
			var target := cell + Vector2i(c_offset, r_offset)
			if target.y < 0 or target.y >= TOTAL_SOIL_ROWS:
				continue
			if _is_cell_water(target) or _rock_cells.has(target) or _initial_root_tiles.has(target):
				continue
			if not _root_tiles.has(target):
				_root_tiles[target] = new_depth
				changed = true

	return changed


func _generate_world() -> void:
	var size := get_viewport_rect().size
	var cols := int(ceil(size.x / TILE_SIZE))
	var rows := TOTAL_SOIL_ROWS
	if cols <= 10 or rows <= 10:
		return

	_generate_water_sources(cols, rows)
	_generate_initial_roots(cols)
	_generate_rocks(cols, rows)


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


func _generate_rocks(cols: int, rows: int) -> void:
	_rocks.clear()
	_rock_cells.clear()
	if not _rocks_texture:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = 9001

	var target_rocks := clampi(int(cols * rows / 250), 18, 55)
	var attempts := 0

	while _rocks.size() < target_rocks and attempts < 600:
		attempts += 1
		var origin_x := rng.randi_range(2, maxi(cols - ROCK_GRID_SPAN - 2, 2))
		var origin_y := rng.randi_range(4, maxi(rows - ROCK_GRID_SPAN - 2, 4))

		# Check that the scaled footprint (plus a 1-cell margin) doesn't overlap water, initial roots, or other rocks
		var overlaps := false
		for r in range(-1, ROCK_GRID_SPAN + 1):
			for c in range(-1, ROCK_GRID_SPAN + 1):
				var check_cell := Vector2i(origin_x + c, origin_y + r)
				if _water_bank_lookup.has(check_cell) or _initial_root_tiles.has(check_cell) or _rock_cells.has(check_cell):
					overlaps = true
					break
			if overlaps:
				break

		if overlaps:
			continue

		var variant: Vector2i = VALID_ROCK_VARIANTS[rng.randi_range(0, VALID_ROCK_VARIANTS.size() - 1)]
		var src_x := variant.x * ROCK_SPRITE_SIZE
		var src_y := variant.y * ROCK_SPRITE_SIZE
		var src_rect := Rect2(src_x, src_y, ROCK_SPRITE_SIZE, ROCK_SPRITE_SIZE)

		_rocks.append({
			"pos": Vector2i(origin_x, origin_y),
			"src_rect": src_rect
		})

		# Mark solid grid cells where the 1/3x scaled rock sprite has opaque pixels
		for r in ROCK_SPRITE_SIZE:
			for c in ROCK_SPRITE_SIZE:
				var is_solid := true
				if _rocks_image:
					is_solid = _rocks_image.get_pixel(src_x + c, src_y + r).a > 0.1
				if is_solid:
					var cell_c := int(floor(float(c) * ROCK_SCALE))
					var cell_r := int(floor(float(r) * ROCK_SCALE))
					_rock_cells[Vector2i(origin_x + cell_c, origin_y + cell_r)] = true


func _draw() -> void:
	var size := get_viewport_rect().size
	var mid := size.y * 0.5
	_draw_sky(size, mid)
	_draw_hills(size, mid)
	_draw_wind_gusts(mid)
	_draw_tree(Vector2(size.x * 0.5, mid), mid)
	_draw_leaf_particles(mid)
	_draw_soil_grid(size, mid)
	_draw_health_bar(size)


func _draw_leaf_particles(mid: float) -> void:
	for lp in _leaf_particles:
		var x: float = lp["x"]
		var y: float = lp["y"]
		if y >= mid - TILE_SIZE:
			continue
		var age: float = lp["age"]
		var max_age: float = lp["max_age"]
		var fade := 1.0
		if age > max_age - 0.8:
			fade = clampf((max_age - age) / 0.8, 0.0, 1.0)
		var col: Color = lp["color"]
		col.a = fade
		draw_rect(Rect2(Vector2(x, y), Vector2(TILE_SIZE, TILE_SIZE)), col)


func _draw_wind_gusts(mid: float) -> void:
	if _wind_strength <= 0.05:
		return
	for p in _wind_gust_particles:
		var y: float = p["y"]
		if y >= mid:
			continue
		var x: float = p["x"]
		var length: float = p["len"] * (0.5 + 0.5 * _wind_strength)
		var alpha: float = p["alpha"] * _wind_strength
		# Subtle wave along the wind streak
		var wave_y := sin(_wind_time * 4.0 + x * 0.03) * 2.0
		var p1 := Vector2(x, y + wave_y)
		var p2 := Vector2(x + length * _wind_direction, y - wave_y)
		draw_line(p1, p2, Color(1.0, 1.0, 1.0, alpha), 1.5)


func _draw_health_bar(_size: Vector2) -> void:
	if not _vt323_font:
		return

	var bar_pos := Vector2(20.0, 26.0)
	var bar_w := 200.0
	var bar_h := 18.0
	var border_w := 2.0

	var font_size := 22

	# Title text above the bar
	draw_string(_vt323_font, bar_pos + Vector2(0.0, -6.0), "TREE HEALTH", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

	# Status text on the right (e.g. 75% or Absorbing / Drying)
	var hp_ratio := clampf(_tree_health / MAX_TREE_HEALTH, 0.0, 1.0)
	var hp_pct_str := "%d%%" % int(hp_ratio * 100.0)
	draw_string(_vt323_font, bar_pos + Vector2(bar_w - 40.0, -6.0), hp_pct_str, HORIZONTAL_ALIGNMENT_RIGHT, 40.0, font_size, Color("d0e6ff"))

	# Outer border/drop shadow
	draw_rect(Rect2(bar_pos - Vector2(border_w, border_w), Vector2(bar_w + border_w * 2.0, bar_h + border_w * 2.0)), Color(0, 0, 0, 0.7))
	# Inner dark background
	draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.12, 0.12, 0.12, 0.85))

	# Filled bar color based on health level: green -> yellow -> red
	var fill_color: Color
	if hp_ratio > 0.5:
		fill_color = Color("4caf50").lerp(Color("8bc34a"), (hp_ratio - 0.5) * 2.0)
	elif hp_ratio > 0.2:
		fill_color = Color("ff9800").lerp(Color("4caf50"), (hp_ratio - 0.2) / 0.3)
	else:
		fill_color = Color("e53935").lerp(Color("ff9800"), hp_ratio / 0.2)

	var current_w := bar_w * hp_ratio
	if current_w > 0.0:
		# Main filled bar
		draw_rect(Rect2(bar_pos, Vector2(current_w, bar_h)), fill_color)
		# Gloss highlight line on top half of the bar
		draw_rect(Rect2(bar_pos, Vector2(current_w, bar_h * 0.4)), Color(1.0, 1.0, 1.0, 0.25))

	# Inner outline
	draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(1.0, 1.0, 1.0, 0.2), false, 1.0)


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
	if _tree_texture:
		_draw_tree_spritesheet(base, mid)
	else:
		_draw_tree_procedural(base, mid)


func _draw_tree_spritesheet(base: Vector2, _mid: float) -> void:
	# 1px of the tree sprite = 8x8px on screen (exact same size as soil grid squares)
	var tree_pixel_scale := TILE_SIZE
	var scaled_size := Vector2(SPRITE_SIZE, SPRITE_SIZE) * tree_pixel_scale

	# Align the 4px-wide trunk (x=17..20 in sprite) directly on top of the 4-cell-wide main root:
	# Main root top spans columns [center_col - 2 .. center_col + 1]
	var size := get_viewport_rect().size
	var cols := int(ceil(size.x / TILE_SIZE))
	var center_col := int(cols * 0.5)
	var root_left_screen_x := float(center_col - 2) * TILE_SIZE

	# In the 40x40 sprite, the 4px-wide trunk starts at x=17 and ends at y=36 (37px tall from 0..36)
	var dest_pos := Vector2(root_left_screen_x - 17.0 * tree_pixel_scale, base.y - 37.0 * tree_pixel_scale)

	# Calculate left-right oscillation when there is wind
	var sway_px := (sin(_wind_time * WIND_SWAY_FREQ) * WIND_MAX_SWAY_PX + _wind_direction * 0.6) * _wind_strength
	var base_oscillation_x := sway_px * tree_pixel_scale
	var leaf_offset_x := base_oscillation_x * 0.75

	# Draw trunk/roots base sprite with height-dependent bending and cross-dissolve transition:
	var trunk_t := smoothstep(0.0, 1.0, _trunk_dissolve_t)
	for row_y in SPRITE_SIZE:
		# Normalized height from trunk base (0.0 at bottom y>=36, up to 1.0 at top y=0)
		var height_t := clampf((36.0 - float(row_y)) / 32.0, 0.0, 1.0)
		# Smooth quadratic bend so lower region stays almost 0 and upper reaches 0.5 * base_oscillation_x
		var trunk_row_offset_x := base_oscillation_x * 0.5 * (height_t * height_t)
		var dst_row_rect := Rect2(
			dest_pos.x + trunk_row_offset_x,
			dest_pos.y + float(row_y) * tree_pixel_scale,
			scaled_size.x,
			tree_pixel_scale
		)

		if trunk_t < 1.0 and _prev_trunk_rect != _current_trunk_rect:
			var prev_src_row := Rect2(_prev_trunk_rect.position.x, _prev_trunk_rect.position.y + row_y, SPRITE_SIZE, 1.0)
			draw_texture_rect_region(_tree_texture, dst_row_rect, prev_src_row, Color(1.0, 1.0, 1.0, 1.0 - trunk_t))

		var cur_src_row := Rect2(_current_trunk_rect.position.x, _current_trunk_rect.position.y + row_y, SPRITE_SIZE, 1.0)
		draw_texture_rect_region(_tree_texture, dst_row_rect, cur_src_row, Color(1.0, 1.0, 1.0, trunk_t))

	# Draw leaves on top with smooth cross-dissolve and interpolated vertical offset
	var leaf_t := smoothstep(0.0, 1.0, _leaf_dissolve_t)
	if leaf_t < 1.0:
		var prev_offset_y := _prev_leaf_offset_px * tree_pixel_scale
		var prev_leaf_dest := Rect2(dest_pos + Vector2(leaf_offset_x, -prev_offset_y), scaled_size)
		draw_texture_rect_region(_tree_texture, prev_leaf_dest, _prev_leaf_rect, Color(1.0, 1.0, 1.0, 1.0 - leaf_t))

	var cur_offset_y := _current_leaf_offset_px * tree_pixel_scale
	var cur_leaf_dest := Rect2(dest_pos + Vector2(leaf_offset_x, -cur_offset_y), scaled_size)
	draw_texture_rect_region(_tree_texture, cur_leaf_dest, _current_leaf_rect, Color(1.0, 1.0, 1.0, leaf_t))


func _draw_tree_procedural(base: Vector2, mid: float) -> void:
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

	# 4. Rocks rendered on the soil grid at 1/3x scale (clipped to visible soil rows)
	if _rocks_texture:
		var rock_draw_size := float(ROCK_SPRITE_SIZE) * TILE_SIZE * ROCK_SCALE
		var rock_pixel_scale := TILE_SIZE * ROCK_SCALE
		for rock in _rocks:
			var pos: Vector2i = rock["pos"]
			var src_rect: Rect2 = rock["src_rect"]
			var rock_top_row := pos.y
			var rock_bottom_row := pos.y + ROCK_GRID_SPAN
			if rock_bottom_row <= start_row or rock_top_row > end_row:
				continue

			# Clip top of rock if it scrolls above the soil horizon line (mid)
			var screen_x := float(pos.x) * TILE_SIZE
			var screen_y := mid + (float(pos.y) * TILE_SIZE - _soil_scroll_y)
			var draw_src := src_rect
			var draw_dst := Rect2(
				Vector2(screen_x, screen_y),
				Vector2(rock_draw_size, rock_draw_size)
			)

			if screen_y < mid:
				var clip_px := mid - screen_y
				var clip_tex_px := clip_px / rock_pixel_scale
				if clip_tex_px >= ROCK_SPRITE_SIZE:
					continue
				draw_src.position.y += clip_tex_px
				draw_src.size.y -= clip_tex_px
				draw_dst.position.y = mid
				draw_dst.size.y -= clip_px

			draw_texture_rect_region(_rocks_texture, draw_dst, draw_src)

	# Scrollbar indicator on the right edge
	var scroll_track_h := visible_soil_height
	var max_s := _max_scroll_y()
	if max_s > 0.0:
		var thumb_h := maxf(24.0, scroll_track_h * (visible_soil_height / (TOTAL_SOIL_ROWS * TILE_SIZE)))
		var thumb_y := mid + (_soil_scroll_y / max_s) * (scroll_track_h - thumb_h)
		draw_rect(Rect2(size.x - 5.0, thumb_y, 4.0, thumb_h), Color(1, 1, 1, 0.35))
