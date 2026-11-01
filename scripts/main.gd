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
const SOIL_TOP := Color("3a2417")
const SOIL_BOTTOM := Color("130904")
const TRUNK := Color("652300")
const LEAVES_DARK := Color("2f6b2a")
const LEAVES := Color("3f8a36")
const LEAVES_LIGHT := Color("58a84a")

const WATER_COLOR := Color("2980b9")
const WATER_EDGE := Color("1f5f8b")
const ROOT_COLOR := Color("652300")

# Retro Pixel-Art Bitmask Root Palette (Ağaç Gövdesi #652300 İle Birebir Uyumlu)
const ROOT_BARK_DARK := Color("1b0800")
const ROOT_BARK_SHADOW := Color("381300")
const ROOT_WOOD_CORE := Color("652300")
const ROOT_WOOD_GRAIN := Color("4e1a00")
const ROOT_WOOD_LIGHT := Color("853609")
const ROOT_TIP_COLOR := Color("aa4d18")
const ROOT_WATER_FLOW := Color("54d6ff")

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
# Tracks recent brush centers along the active drag so self-overlap is allowed while foreign roots keep a 1-cell gap
var _active_drag_Safe_tiles: Dictionary = {}
var _active_drag_history: Array = []
var _soil_scroll_y: float = 0.0

# Water collection & Leaf spritesheet configuration
const SPRITE_SIZE := 40
const SPRITE_RECT_SMALLROOT := Rect2(0, 0, 40, 40)
const SPRITE_RECT_BIGROOT := Rect2(40, 0, 40, 40)
const SPRITE_RECT_MIDLEAVES := Rect2(80, 0, 40, 40)
const SPRITE_RECT_LARGELEAVES := Rect2(0, 40, 40, 40)
const SPRITE_RECT_SMALLLEAVES := Rect2(40, 40, 40, 40)
const SPRITE_RECT_DRYLEAVES := Rect2(80, 40, 40, 40)

const INITIAL_WATER := 50.0
const MAX_WATER_STORED := 200.0
const DRY_WATER_THRESHOLD := 50.0

const MAX_TREE_HEALTH := 100.0
# Health decay rate per second when disconnected from water
const HEALTH_DECAY_RATE := 3.0
# Health recovery rate per second when sucking water
const HEALTH_REGEN_RATE := 8.0

const MAX_AIR_POLLUTION := 100.0
# Pollution rise rate per second when leaves are dry
const POLLUTION_RISE_RATE := 2.5
# Pollution decrease rates per second for green leaf sizes (small, mid, large)
const POLLUTION_DECAY_SMALL := 1.2
const POLLUTION_DECAY_MID := 2.8
const POLLUTION_DECAY_LARGE := 5.0

var _tree_texture: Texture2D = null
var _vt323_font: Font = null
var _root_grow_player: AudioStreamPlayer = null
const ROOT_SFX_HOLD_TIME := 0.14
var _root_sfx_timer: float = 0.0

# Game state machine & Intro cinematic configuration
enum GameState {
	INTRO_PEACEFUL,
	INTRO_FIRE,
	INTRO_AFTERMATH,
	INTRO_READY,
	PLAYING
}
var _game_state: GameState = GameState.INTRO_PEACEFUL
var _intro_timer: float = 0.0
var _intro_fire_particles: Array = []
var _intro_smoke_particles: Array = []
var _intro_ash_particles: Array = []

var _water_stored: float = INITIAL_WATER # Starts at 50L (equivalent to 50px of water source)
var _tree_health: float = 25.0 # Starts at initial stage (small tree)
var _air_pollution: float = 35.0
var _is_game_over: bool = false
var _game_over_reason: String = ""
var _is_grow_btn_hovered: bool = false
var _is_connected_to_water: bool = false
var _active_water_intake_rate: float = 0.0
var _water_pulse_time: float = 0.0
var _water_flow_cells: Dictionary = {} # Vector2i -> int (distance from water contact)

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
	if ResourceLoader.exists("res://assets/root_grow.mp3"):
		var sfx_stream := load("res://assets/root_grow.mp3")
		if sfx_stream is AudioStreamMP3:
			sfx_stream.loop = true
		_root_grow_player = AudioStreamPlayer.new()
		_root_grow_player.stream = sfx_stream
		add_child(_root_grow_player)
	_wind_rng.randomize()
	get_viewport().size_changed.connect(_on_size_changed)
	_generate_world()
	_init_wind_particles()


func _process(delta: float) -> void:
	if _game_state != GameState.PLAYING:
		_process_intro(delta)
		return

	if _is_game_over:
		if _root_grow_player and _root_grow_player.playing:
			_root_grow_player.stop()
		return

	if _root_sfx_timer > 0.0:
		_root_sfx_timer = maxf(0.0, _root_sfx_timer - delta)
		if _root_sfx_timer <= 0.0 or not _is_lmb_down:
			_root_sfx_timer = 0.0
			if _root_grow_player and _root_grow_player.playing:
				_root_grow_player.stop()

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
			# Drain rate in water cells per second = width / layer_time = 1.0 / 0.4 = 2.5 cells/sec (1px = 1L)
			var cells_per_second: float = float(rect.size.x) / layer_time
			var absorbed: float = cells_per_second * delta
			_water_stored = minf(_water_stored + absorbed, MAX_WATER_STORED)
			intake_this_frame += cells_per_second

			bank["drain_timer"] += delta
			while bank["drain_timer"] >= layer_time and bank["drained_layers"] < rect.size.y:
				bank["drain_timer"] -= layer_time
				bank["drained_layers"] += 1

			needs_redraw = true

	_is_connected_to_water = connected_now
	_active_water_intake_rate = intake_this_frame
	if _is_connected_to_water:
		_water_pulse_time += delta
		_update_water_flow_path()
		needs_redraw = true
	else:
		_water_flow_cells.clear()

	# Tree health decreases continuously over time (even when drawing water), and only increases via GROW TREE
	var old_hp := _tree_health
	_tree_health = maxf(0.0, _tree_health - HEALTH_DECAY_RATE * delta)
	if not is_equal_approx(old_hp, _tree_health):
		needs_redraw = true

	# Update air pollution based on tree health & leaf state:
	# When health > 20, the tree has green leaves and decreases air pollution at a rate scaled by tree health
	# (slowly at 20-40 HP, faster as health approaches 80-100 HP). When <= 20 HP (dry leaves), pollution rises.
	var old_pollution := _air_pollution
	if _tree_health <= 20.0:
		_air_pollution = minf(MAX_AIR_POLLUTION, _air_pollution + POLLUTION_RISE_RATE * delta)
	else:
		var health_factor := clampf((_tree_health - 20.0) / 80.0, 0.0, 1.0)
		var decay_rate := lerpf(POLLUTION_DECAY_SMALL, POLLUTION_DECAY_LARGE, health_factor)
		_air_pollution = maxf(0.0, _air_pollution - decay_rate * delta)

	if not is_equal_approx(old_pollution, _air_pollution):
		needs_redraw = true

	# Check Game Over conditions: air pollution reaches max or water reaches 0
	if _air_pollution >= MAX_AIR_POLLUTION:
		_is_game_over = true
		_game_over_reason = "AIR POLLUTION REACHED 100%"
		needs_redraw = true
	elif _water_stored <= 0.0:
		_water_stored = 0.0
		_is_game_over = true
		_game_over_reason = "WATER DEPLETED (0L)"
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
	# When tree health is <= 20, leaves are dry; beyond 20, sprites are green leaves scaled by health
	if _tree_health <= 20.0:
		return SPRITE_RECT_DRYLEAVES
	elif _tree_health < 50.0:
		return SPRITE_RECT_SMALLLEAVES
	elif _tree_health < 80.0:
		return SPRITE_RECT_MIDLEAVES
	else:
		return SPRITE_RECT_LARGELEAVES


func _grow_tree_to_next_state() -> void:
	if _is_game_over:
		return
	# Require strictly more than 50L of water to grow, and consume 50L
	if _water_stored <= 50.0:
		return

	_water_stored -= 50.0

	if _tree_health <= 20.0:
		_tree_health = 35.0
	elif _tree_health < 50.0:
		_tree_health = 65.0
	elif _tree_health < 80.0:
		_tree_health = 90.0
	else:
		_tree_health = MAX_TREE_HEALTH
	queue_redraw()


func _get_grow_button_rect(size: Vector2, mid: float) -> Rect2:
	var btn_side := 84.0
	var margin := 16.0
	return Rect2(Vector2(size.x - btn_side - margin, mid - btn_side - margin), Vector2(btn_side, btn_side))


func _restart_game() -> void:
	_game_state = GameState.PLAYING
	_water_stored = INITIAL_WATER
	_tree_health = 25.0
	_air_pollution = 35.0
	_is_game_over = false
	_game_over_reason = ""
	_current_leaf_rect = _get_target_leaf_rect()
	_prev_leaf_rect = _current_leaf_rect
	_current_trunk_rect = _get_target_trunk_rect()
	_prev_trunk_rect = _current_trunk_rect
	_leaf_dissolve_t = 1.0
	_trunk_dissolve_t = 1.0
	_soil_scroll_y = 0.0
	_generate_world()
	queue_redraw()


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
	if _get_target_leaf_rect() == SPRITE_RECT_DRYLEAVES:
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
	if _game_state != GameState.PLAYING:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
				_start_gameplay()
				return
			elif event.keycode == KEY_ESCAPE:
				var mode := DisplayServer.window_get_mode()
				if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				else:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
				return
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _game_state == GameState.INTRO_READY:
				_start_gameplay()
				return
		return

	var size := get_viewport_rect().size
	var mid := size.y * 0.5
	var grow_btn_rect := _get_grow_button_rect(size, mid)

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _is_game_over:
				if event.pressed:
					_restart_game()
				return

			if event.pressed and grow_btn_rect.has_point(event.position):
				_is_lmb_down = false
				_grow_tree_to_next_state()
				return

			_is_lmb_down = event.pressed
			if _is_lmb_down:
				_has_last_drag_cell = false
				_active_drag_Safe_tiles.clear()
				_active_drag_history.clear()
				_interact_at_pos(event.position)
			else:
				_has_last_drag_cell = false
				_active_drag_Safe_tiles.clear()
				_active_drag_history.clear()
				_root_sfx_timer = 0.0
				if _root_grow_player and _root_grow_player.playing:
					_root_grow_player.stop()

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
		var hovered := grow_btn_rect.has_point(event.position)
		if hovered != _is_grow_btn_hovered:
			_is_grow_btn_hovered = hovered
			queue_redraw()

		if _is_game_over:
			return

		if _is_lmb_down:
			_interact_at_pos(event.position)
		if _is_mmb_down and event.position.y >= mid:
			_soil_scroll_y -= event.relative.y
			_clamp_scroll()
			queue_redraw()

	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R and _is_game_over:
			_restart_game()
		elif event.keycode == KEY_ESCAPE:
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
		_root_sfx_timer = ROOT_SFX_HOLD_TIME
		if _root_grow_player and not _root_grow_player.playing:
			_root_grow_player.play()
		queue_redraw()


func _try_extend_root_at_cell(cell: Vector2i) -> bool:
	if cell.y < 0 or cell.y >= TOTAL_SOIL_ROWS:
		return false
	if _water_stored < 1.0:
		return false
	if _is_cell_water(cell) or _rock_cells.has(cell):
		return false

	# If this is the start of a drag and the user clicks on or next to an existing root,
	# seed the safe zone around the starting root connection point so we can branch out cleanly.
	var is_branch_start := _active_drag_history.is_empty()

	# Find minimum depth among existing root tiles in or adjacent to this cell
	var parent_depth := _get_neighbor_min_depth(cell)
	if _initial_root_tiles.has(cell):
		parent_depth = 0
	elif _root_tiles.has(cell):
		var self_d: int = _root_tiles[cell]
		if parent_depth == -1 or self_d < parent_depth:
			parent_depth = self_d

	if parent_depth == -1:
		return false

	# When already dragging (not the initial branch connection point), only allow extending
	# from the tip of the active drag so you cannot jump across onto a separate root.
	if not is_branch_start:
		var connected_to_active_tip := _active_drag_Safe_tiles.has(cell)
		if not connected_to_active_tip:
			for ro in range(-1, 2):
				for co in range(-1, 2):
					if _active_drag_Safe_tiles.has(cell + Vector2i(co, ro)):
						connected_to_active_tip = true
						break
				if connected_to_active_tip:
					break
		if not connected_to_active_tip:
			return false

	var new_depth := parent_depth + 1
	if new_depth > MAX_ROOT_STEPS:
		return false

	var w := _get_width_for_depth(new_depth)
	if w <= 0:
		return false

	var half_w := int(w / 2)

	# If starting a new branch, mark existing root tiles within a 2-cell radius of the start point
	# as safe so the new branch can emerge from its parent root, while still blocking other roots.
	if is_branch_start:
		var start_safe := {}
		for ro in range(-half_w - 2, -half_w + w + 2):
			for co in range(-half_w - 2, -half_w + w + 2):
				var p := cell + Vector2i(co, ro)
				if _initial_root_tiles.has(p) or _root_tiles.has(p):
					start_safe[p] = true
		_active_drag_history.append(start_safe)
		_rebuild_active_drag_safe_tiles()

	# Collect candidate cells that this brush step will paint
	var candidate_cells: Array[Vector2i] = []
	for r_offset in range(-half_w, -half_w + w):
		for c_offset in range(-half_w, -half_w + w):
			var target := cell + Vector2i(c_offset, r_offset)
			if target.y < 0 or target.y >= TOTAL_SOIL_ROWS:
				continue
			if _is_cell_water(target) or _rock_cells.has(target) or _initial_root_tiles.has(target):
				continue
			if not _root_tiles.has(target):
				candidate_cells.append(target)

	if candidate_cells.is_empty():
		return false

	# Enforce at least 1px (1 soil cell) space from any other root (including earlier parts of this root if looping back)
	for target in candidate_cells:
		for nr in range(-1, 2):
			for nc in range(-1, 2):
				var neighbor := target + Vector2i(nc, nr)
				if _initial_root_tiles.has(neighbor) or _root_tiles.has(neighbor):
					if not _active_drag_Safe_tiles.has(neighbor):
						return false

	# Paint the validated cells and record them in the sliding active-tip window
	var step_painted := {}
	for target in candidate_cells:
		_root_tiles[target] = new_depth
		step_painted[target] = true

	# Extending the root by 1 step (1px along path) draws 1L of water
	_water_stored = maxf(0.0, _water_stored - 1.0)

	_active_drag_history.append(step_painted)
	# Keep only the most recent 6 steps in the safe set so looping the same root back on itself is also blocked with a 1-cell gap
	while _active_drag_history.size() > 6:
		_active_drag_history.pop_front()
	_rebuild_active_drag_safe_tiles()

	return true


func _rebuild_active_drag_safe_tiles() -> void:
	_active_drag_Safe_tiles.clear()
	for step_dict in _active_drag_history:
		for k in step_dict:
			_active_drag_Safe_tiles[k] = true


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


func _process_intro(delta: float) -> void:
	_intro_timer += delta
	if _intro_timer < 5.0:
		_game_state = GameState.INTRO_PEACEFUL
	elif _intro_timer < 11.0:
		_game_state = GameState.INTRO_FIRE
	elif _intro_timer < 15.0:
		_game_state = GameState.INTRO_AFTERMATH
	else:
		_game_state = GameState.INTRO_READY

	var size := get_viewport_rect().size
	var mid := size.y * 0.5
	_update_intro_particles(delta, size, mid)
	_update_wind(delta)
	queue_redraw()


func _start_gameplay() -> void:
	_game_state = GameState.PLAYING
	_intro_fire_particles.clear()
	_intro_smoke_particles.clear()
	_intro_ash_particles.clear()
	queue_redraw()


func _update_intro_particles(delta: float, size: Vector2, mid: float) -> void:
	var bbq_x := size.x * 0.58 + 10.0
	var spark_land_x := size.x * 0.58 + 28.0

	# 1. Peaceful smoke puffs from grill (0.0s - 5.0s)
	if _intro_timer < 5.0:
		if _wind_rng.randf() < delta * 4.5:
			_intro_smoke_particles.append({
				"pos": Vector2(bbq_x + _wind_rng.randf_range(-3.0, 3.0), mid - 20.0),
				"vel": Vector2(_wind_rng.randf_range(-6.0, 10.0), _wind_rng.randf_range(-22.0, -38.0)),
				"radius": _wind_rng.randf_range(3.0, 5.0),
				"max_radius": _wind_rng.randf_range(10.0, 18.0),
				"color": Color(0.92, 0.94, 0.96, 0.45),
				"age": 0.0,
				"max_age": _wind_rng.randf_range(2.0, 3.2)
			})

	# 2. Fire and dark billowing smoke (5.8s - 11.5s)
	if _intro_timer >= 5.8 and _intro_timer < 11.5:
		var left_t := clampf((_intro_timer - 5.8) / 3.8, 0.0, 1.0)
		var fire_left := lerpf(spark_land_x, size.x * 0.06, left_t)
		var right_t := clampf((_intro_timer - 5.8) / 2.8, 0.0, 1.0)
		var fire_right := lerpf(spark_land_x, size.x * 0.94, right_t)

		var fire_intensity := 1.0
		if _intro_timer > 10.0:
			fire_intensity = clampf((11.5 - _intro_timer) / 1.5, 0.0, 1.0)

		# Ground fire sparks/particles
		var spawn_count := int(fire_intensity * 7.0)
		for k in spawn_count:
			var fx := _wind_rng.randf_range(fire_left, fire_right)
			if absf(fx - size.x * 0.5) < 14.0:
				continue
			var col_choice := _wind_rng.randf()
			var p_col: Color
			if col_choice < 0.35:
				p_col = Color("fff59d")
			elif col_choice < 0.7:
				p_col = Color("ff9800")
			else:
				p_col = Color("f44336")

			_intro_fire_particles.append({
				"pos": Vector2(fx, mid - _wind_rng.randf_range(0.0, 10.0)),
				"vel": Vector2(_wind_rng.randf_range(-15.0, 15.0) + _wind_direction * 10.0, _wind_rng.randf_range(-45.0, -110.0)),
				"size": _wind_rng.randf_range(3.0, 7.0),
				"color": p_col,
				"age": 0.0,
				"max_age": _wind_rng.randf_range(0.25, 0.55)
			})

		# Dark billowing smoke
		for k in 3:
			var sx := _wind_rng.randf_range(fire_left, fire_right)
			_intro_smoke_particles.append({
				"pos": Vector2(sx, mid - _wind_rng.randf_range(5.0, 18.0)),
				"vel": Vector2(_wind_rng.randf_range(10.0, 35.0) * _wind_direction, _wind_rng.randf_range(-35.0, -75.0)),
				"radius": _wind_rng.randf_range(6.0, 12.0),
				"max_radius": _wind_rng.randf_range(28.0, 52.0),
				"color": Color(_wind_rng.randf_range(0.12, 0.22), _wind_rng.randf_range(0.10, 0.16), _wind_rng.randf_range(0.08, 0.14), 0.55 * fire_intensity),
				"age": 0.0,
				"max_age": _wind_rng.randf_range(2.5, 4.2)
			})

	# 3. Ash flakes drifting in the aftermath (10.5s+)
	if _intro_timer >= 10.5:
		if _wind_rng.randf() < 0.45:
			_intro_ash_particles.append({
				"pos": Vector2(_wind_rng.randf_range(-20.0, size.x + 20.0), -10.0),
				"vel": Vector2(_wind_rng.randf_range(-12.0, 12.0), _wind_rng.randf_range(22.0, 48.0)),
				"size": _wind_rng.randf_range(1.5, 3.5),
				"alpha": _wind_rng.randf_range(0.35, 0.75),
				"phase": _wind_rng.randf_range(0.0, TAU),
				"age": 0.0,
				"max_age": _wind_rng.randf_range(8.0, 15.0)
			})

		var stump_xs := [size.x * 0.14, size.x * 0.28, size.x * 0.72, size.x * 0.86]
		for sx in stump_xs:
			if _wind_rng.randf() < delta * 1.8:
				_intro_smoke_particles.append({
					"pos": Vector2(sx + _wind_rng.randf_range(-4.0, 4.0), mid - 14.0),
					"vel": Vector2(_wind_rng.randf_range(-6.0, 10.0), _wind_rng.randf_range(-18.0, -32.0)),
					"radius": _wind_rng.randf_range(3.0, 5.0),
					"max_radius": _wind_rng.randf_range(10.0, 16.0),
					"color": Color(0.65, 0.65, 0.65, 0.35),
					"age": 0.0,
					"max_age": _wind_rng.randf_range(1.8, 2.8)
				})

	# Update smoke particles
	for i in range(_intro_smoke_particles.size() - 1, -1, -1):
		var p: Dictionary = _intro_smoke_particles[i]
		p["age"] += delta
		if p["age"] >= p["max_age"]:
			_intro_smoke_particles.remove_at(i)
		else:
			p["pos"] += p["vel"] * delta

	# Update fire particles
	for i in range(_intro_fire_particles.size() - 1, -1, -1):
		var p: Dictionary = _intro_fire_particles[i]
		p["age"] += delta
		if p["age"] >= p["max_age"]:
			_intro_fire_particles.remove_at(i)
		else:
			p["pos"] += p["vel"] * delta

	# Update ash particles
	for i in range(_intro_ash_particles.size() - 1, -1, -1):
		var p: Dictionary = _intro_ash_particles[i]
		p["age"] += delta
		if p["age"] >= p["max_age"] or p["pos"].y > size.y + 10.0:
			_intro_ash_particles.remove_at(i)
		else:
			p["pos"].x += (p["vel"].x + sin(p["age"] * 2.2 + p["phase"]) * 14.0) * delta
			p["pos"].y += p["vel"].y * delta


func _draw_tree_standalone(pos: Vector2, leaf_rect: Rect2, trunk_rect: Rect2, leaf_offset_px: float = 0.0, sway_mult: float = 1.0, color_mod: Color = Color.WHITE, burn_progress: float = 0.0) -> void:
	if not _tree_texture:
		var col := color_mod if burn_progress <= 0.0 else color_mod.lerp(Color("22110a"), burn_progress)
		draw_rect(Rect2(pos - Vector2(8.0, 40.0), Vector2(16.0, 40.0)), col)
		return

	var tree_pixel_scale := TILE_SIZE
	var scaled_size := Vector2(SPRITE_SIZE, SPRITE_SIZE) * tree_pixel_scale
	var dest_pos := Vector2(pos.x - 19.0 * tree_pixel_scale, pos.y - 37.0 * tree_pixel_scale)

	var sway_px := (sin(_wind_time * WIND_SWAY_FREQ + pos.x * 0.015) * WIND_MAX_SWAY_PX + _wind_direction * 0.6) * _wind_strength * sway_mult
	var base_oscillation_x := sway_px * tree_pixel_scale
	var leaf_offset_x := base_oscillation_x * 0.75

	if burn_progress >= 1.0:
		# Fully burnt tree: only lower charred trunk stump (rows 31..36)
		var burnt_trunk_col := Color("140905")
		for row_y in range(31, SPRITE_SIZE):
			var dst_row_rect := Rect2(
				dest_pos.x,
				dest_pos.y + float(row_y) * tree_pixel_scale,
				scaled_size.x,
				tree_pixel_scale
			)
			var src_row := Rect2(trunk_rect.position.x, trunk_rect.position.y + row_y, SPRITE_SIZE, 1.0)
			draw_texture_rect_region(_tree_texture, dst_row_rect, src_row, burnt_trunk_col)
		return

	var trunk_col := color_mod
	if burn_progress > 0.0:
		trunk_col = color_mod.lerp(Color("160a06"), burn_progress)

	for row_y in SPRITE_SIZE:
		var height_t := clampf((36.0 - float(row_y)) / 32.0, 0.0, 1.0)
		var trunk_row_offset_x := base_oscillation_x * 0.5 * (height_t * height_t)
		var dst_row_rect := Rect2(
			dest_pos.x + trunk_row_offset_x,
			dest_pos.y + float(row_y) * tree_pixel_scale,
			scaled_size.x,
			tree_pixel_scale
		)
		var src_row := Rect2(trunk_rect.position.x, trunk_rect.position.y + row_y, SPRITE_SIZE, 1.0)
		draw_texture_rect_region(_tree_texture, dst_row_rect, src_row, trunk_col)

	# Leaves
	if burn_progress < 1.0:
		var leaf_alpha := 1.0
		var leaf_tint := color_mod
		if burn_progress > 0.0:
			leaf_alpha = clampf((1.0 - burn_progress) * 1.25, 0.0, 1.0)
			leaf_tint = color_mod.lerp(Color("ff4500"), burn_progress)
		leaf_tint.a *= leaf_alpha
		if leaf_tint.a > 0.01:
			var leaf_dest := Rect2(dest_pos + Vector2(leaf_offset_x, -leaf_offset_px * tree_pixel_scale), scaled_size)
			draw_texture_rect_region(_tree_texture, leaf_dest, leaf_rect, leaf_tint)


func _draw_intro_picnic(pos: Vector2, burn_progress: float) -> void:
	var bbq_x := pos.x + 10.0
	var bbq_base_y := pos.y

	# Ground shadow
	draw_line(Vector2(bbq_x - 8.0, bbq_base_y), Vector2(bbq_x + 8.0, bbq_base_y), Color(0.0, 0.0, 0.0, 0.35), 2.0)
	# Grill legs
	var leg_col := Color("141414")
	draw_line(Vector2(bbq_x - 7.0, bbq_base_y), Vector2(bbq_x - 3.0, bbq_base_y - 12.0), leg_col, 2.0)
	draw_line(Vector2(bbq_x + 7.0, bbq_base_y), Vector2(bbq_x + 3.0, bbq_base_y - 12.0), leg_col, 2.0)
	draw_line(Vector2(bbq_x, bbq_base_y), Vector2(bbq_x, bbq_base_y - 12.0), leg_col, 2.0)

	# Kettle bowl
	var bowl_rect := Rect2(bbq_x - 8.0, bbq_base_y - 20.0, 16.0, 10.0)
	draw_rect(bowl_rect, Color("222222"))
	draw_rect(Rect2(bbq_x - 9.0, bbq_base_y - 21.0, 18.0, 3.0), Color("333333"))

	# Glowing coals inside
	var coal_glow := (sin(_intro_timer * 6.0) + 1.0) * 0.5
	var coal_col := Color("ff5722").lerp(Color("ffeb3b"), coal_glow * 0.6)
	draw_rect(Rect2(bbq_x - 6.0, bbq_base_y - 19.0, 12.0, 4.0), coal_col)

	# Spark flying out from grill (5.0s to 5.8s)
	if _intro_timer >= 5.0 and _intro_timer < 5.8:
		var spark_t := (_intro_timer - 5.0) / 0.8
		var target_x := pos.x + 28.0
		var sx := lerpf(bbq_x, target_x, spark_t)
		var sy := lerpf(bbq_base_y - 19.0, bbq_base_y, spark_t) - sin(spark_t * PI) * 26.0
		draw_rect(Rect2(Vector2(sx - 2.0, sy - 2.0), Vector2(4.0, 4.0)), Color("fff59d"))
		draw_rect(Rect2(Vector2(sx - 1.0, sy - 1.0), Vector2(2.0, 2.0)), Color.WHITE)

	# Picnic Blanket & Basket at pos + Vector2(24.0, 0.0)
	var blk_x := pos.x + 24.0
	var blk_w := 48.0
	var blk_h := 10.0

	if burn_progress < 1.0:
		var blk_mod := Color.WHITE.lerp(Color("1a100a"), burn_progress)
		var tile_w := 8.0
		var tile_h := 5.0
		for row in 2:
			for col in 6:
				var is_red := (col + row) % 2 == 0
				var t_col := Color("d32f2f") if is_red else Color("f5f5f5")
				t_col = t_col * blk_mod
				draw_rect(Rect2(blk_x + float(col) * tile_w, bbq_base_y - 4.0 + float(row) * tile_h, tile_w, tile_h), t_col)

		# Picnic Basket
		var basket_col := Color("8d5524").lerp(Color("160b06"), burn_progress)
		var basket_rect := Rect2(blk_x + 8.0, bbq_base_y - 16.0, 14.0, 12.0)
		draw_rect(basket_rect, basket_col)
		draw_line(Vector2(basket_rect.position.x, basket_rect.position.y), Vector2(basket_rect.position.x + basket_rect.size.x, basket_rect.position.y), Color("a06530") * blk_mod, 1.0)
		# Basket cloth
		draw_rect(Rect2(blk_x + 12.0, bbq_base_y - 16.0, 6.0, 5.0), Color.WHITE * blk_mod)
		# Small fruit on blanket
		draw_rect(Rect2(blk_x + 32.0, bbq_base_y - 7.0, 4.0, 4.0), Color("e53935") * blk_mod)
	else:
		# Burnt ash smudge
		draw_rect(Rect2(blk_x, bbq_base_y - 2.0, blk_w, 4.0), Color("170f0a"))


func _draw_intro_smoke_particles() -> void:
	for p in _intro_smoke_particles:
		var progress: float = p["age"] / p["max_age"]
		var r: float = lerpf(p["radius"], p["max_radius"], progress)
		var col: Color = p["color"]
		col.a *= (1.0 - progress)
		draw_circle(p["pos"], r, col)


func _draw_intro_fire_particles() -> void:
	for p in _intro_fire_particles:
		var progress: float = p["age"] / p["max_age"]
		var s: float = lerpf(p["size"], 1.5, progress)
		var col: Color = p["color"]
		col.a *= (1.0 - progress)
		draw_rect(Rect2(p["pos"].x - s * 0.5, p["pos"].y - s * 0.5, s, s), col)


func _draw_intro_ash_particles() -> void:
	for p in _intro_ash_particles:
		var progress: float = p["age"] / p["max_age"]
		var s: float = p["size"]
		var a: float = p["alpha"] * (1.0 - progress * 0.6)
		draw_rect(Rect2(p["pos"].x, p["pos"].y, s, s), Color(0.88, 0.88, 0.90, a))


func _draw_intro_narrative(size: Vector2) -> void:
	if not _vt323_font:
		return

	var text := ""
	var alpha := 0.0
	var is_final := false
	var subtext := ""

	if _intro_timer < 5.0:
		text = "A peaceful forest, full of beautiful life..."
		if _intro_timer < 0.8:
			alpha = _intro_timer / 0.8
		elif _intro_timer > 4.4:
			alpha = clampf((5.0 - _intro_timer) / 0.6, 0.0, 1.0)
		else:
			alpha = 1.0
	elif _intro_timer < 11.0:
		text = "A single careless spark... turned forest to ashes."
		if _intro_timer < 5.8:
			alpha = (_intro_timer - 5.0) / 0.8
		elif _intro_timer > 10.4:
			alpha = clampf((11.0 - _intro_timer) / 0.6, 0.0, 1.0)
		else:
			alpha = 1.0
	else:
		text = "The fate of the forest is now in your hands."
		alpha = clampf((_intro_timer - 11.0) / 0.8, 0.0, 1.0)
		is_final = true
		if _intro_timer >= 15.0:
			subtext = "[ PRESS SPACE TO BEGIN ]"

	if alpha > 0.01 and text != "":
		# Letterbox banner at top
		var bar_rect := Rect2(0.0, 36.0, size.x, 68.0)
		draw_rect(bar_rect, Color(0.04, 0.04, 0.06, 0.72 * alpha))
		draw_line(Vector2(0.0, 36.0), Vector2(size.x, 36.0), Color(0.95, 0.82, 0.5, 0.45 * alpha), 1.0)
		draw_line(Vector2(0.0, 104.0), Vector2(size.x, 104.0), Color(0.95, 0.82, 0.5, 0.45 * alpha), 1.0)

		var text_color := Color.WHITE if not is_final else Color("ffd54f")
		text_color.a *= alpha
		# Crisp drop shadow
		draw_string(_vt323_font, Vector2(2.0, 81.0), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 38, Color(0.0, 0.0, 0.0, 0.85 * alpha))
		draw_string(_vt323_font, Vector2(0.0, 79.0), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 38, text_color)

	if subtext != "":
		# Pulsing call to action box at center bottom
		var pulse := (sin(_intro_timer * 4.8) + 1.0) * 0.5
		var sub_color := Color("ffd54f").lerp(Color.WHITE, pulse)
		var box_w := 360.0
		var box_h := 46.0
		var box_pos := Vector2((size.x - box_w) * 0.5, size.y * 0.74)
		draw_rect(Rect2(box_pos, Vector2(box_w, box_h)), Color(0.0, 0.0, 0.0, 0.75))
		draw_rect(Rect2(box_pos, Vector2(box_w, box_h)), sub_color, false, 2.0)
		draw_string(_vt323_font, Vector2(box_pos.x, box_pos.y + 32.0), subtext, HORIZONTAL_ALIGNMENT_CENTER, box_w, 32, sub_color)

	# Skip prompt in bottom right
	if _game_state != GameState.PLAYING and _game_state != GameState.INTRO_READY:
		draw_string(_vt323_font, Vector2(size.x - 170.0, size.y - 24.0), "[ SPACE ] SKIP", HORIZONTAL_ALIGNMENT_RIGHT, 150.0, 22, Color(1.0, 1.0, 1.0, 0.65))


func _draw_intro(size: Vector2, mid: float) -> void:
	# 1. Sky background
	var cur_sky_top: Color = SKY_TOP
	var cur_sky_horiz: Color = SKY_HORIZON
	var cur_sun_col: Color = SUN
	var sun_alpha: float = 1.0

	if _intro_timer < 5.0:
		cur_sky_top = SKY_TOP
		cur_sky_horiz = SKY_HORIZON
		cur_sun_col = SUN
		sun_alpha = 1.0
	elif _intro_timer < 11.0:
		var fire_t := clampf((_intro_timer - 5.0) / 4.5, 0.0, 1.0)
		cur_sky_top = SKY_TOP.lerp(Color("160805"), fire_t)
		cur_sky_horiz = SKY_HORIZON.lerp(Color("9e320f"), fire_t)
		cur_sun_col = SUN.lerp(Color("d84315"), fire_t)
		sun_alpha = lerpf(1.0, 0.25, fire_t)
	else:
		var after_t := clampf((_intro_timer - 11.0) / 3.0, 0.0, 1.0)
		cur_sky_top = Color("160805").lerp(Color("1b2028"), after_t)
		cur_sky_horiz = Color("9e320f").lerp(Color("4f4347"), after_t)
		sun_alpha = 0.0

	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, mid), Vector2(0, mid)]),
		PackedColorArray([cur_sky_top, cur_sky_top, cur_sky_horiz, cur_sky_horiz])
	)

	# Sun
	if sun_alpha > 0.02:
		var sun_pos := Vector2(size.x * 0.82, mid * 0.25)
		var r := mid * 0.1
		var c := cur_sun_col
		c.a *= sun_alpha
		draw_circle(sun_pos, r, c)
		var c_ring := cur_sun_col
		c_ring.a *= 0.2 * sun_alpha
		draw_circle(sun_pos, r * 1.35, c_ring)

	# 2. Rolling hills
	var far_col := HILL_FAR
	var near_col := HILL_NEAR
	if _intro_timer >= 5.0 and _intro_timer < 11.0:
		var ht := clampf((_intro_timer - 5.0) / 4.5, 0.0, 1.0)
		far_col = HILL_FAR.lerp(Color("3d2016"), ht)
		near_col = HILL_NEAR.lerp(Color("2a170f"), ht)
	elif _intro_timer >= 11.0:
		var ht := clampf((_intro_timer - 11.0) / 3.0, 0.0, 1.0)
		far_col = Color("3d2016").lerp(Color("23272e"), ht)
		near_col = Color("2a170f").lerp(Color("1b1e24"), ht)

	_draw_wave(size.x, mid, mid * 0.72, mid * 0.08, 1.3, 0.0, far_col)
	_draw_wave(size.x, mid, mid * 0.82, mid * 0.06, 2.1, 1.7, near_col)

	# 3. Ground meadow (grassline at mid)
	var grass_col := GRASS
	if _intro_timer >= 5.8 and _intro_timer < 11.0:
		var gt := clampf((_intro_timer - 5.8) / 3.5, 0.0, 1.0)
		grass_col = GRASS.lerp(Color("22150e"), gt)
	elif _intro_timer >= 11.0:
		grass_col = Color("1e140d")

	draw_rect(Rect2(0, mid * 0.94, size.x, mid * 0.06), grass_col)

	# Below mid: Soil / Underground
	if _intro_timer < 11.0:
		draw_rect(Rect2(0, mid, size.x, size.y - mid), Color("22140b"))
	else:
		_draw_soil_grid(size, mid)
		var soil_cover_alpha := clampf(1.0 - (_intro_timer - 11.0) / 2.0, 0.0, 1.0)
		if soil_cover_alpha > 0.0:
			draw_rect(Rect2(0, mid, size.x, size.y - mid), Color(0.13, 0.08, 0.04, soil_cover_alpha))

	# 4. Smoke & particles behind/around trees
	_draw_intro_smoke_particles()

	# 5. Picnic Area & Barbecue
	var picnic_pos := Vector2(size.x * 0.58, mid)
	var picnic_burn := 0.0
	if _intro_timer >= 5.8:
		picnic_burn = clampf((_intro_timer - 5.8) / 1.8, 0.0, 1.0)
	_draw_intro_picnic(picnic_pos, picnic_burn)

	# 6. Trees
	var burn_t3 := clampf((_intro_timer - 6.2) / 2.0, 0.0, 1.0) if _intro_timer >= 6.2 else 0.0
	var burn_t4 := clampf((_intro_timer - 7.2) / 2.0, 0.0, 1.0) if _intro_timer >= 7.2 else 0.0
	var burn_t1 := clampf((_intro_timer - 8.0) / 2.0, 0.0, 1.0) if _intro_timer >= 8.0 else 0.0
	var burn_t0 := clampf((_intro_timer - 9.0) / 2.0, 0.0, 1.0) if _intro_timer >= 9.0 else 0.0

	# Tree 0 (Left Far)
	_draw_tree_standalone(Vector2(size.x * 0.14, mid), SPRITE_RECT_MIDLEAVES, SPRITE_RECT_SMALLROOT, 0.0, 0.85, Color.WHITE, burn_t0)
	# Tree 1 (Left Near)
	_draw_tree_standalone(Vector2(size.x * 0.28, mid), SPRITE_RECT_MIDLEAVES, SPRITE_RECT_SMALLROOT, 0.0, 1.1, Color.WHITE, burn_t1)
	# Tree 3 (Right Near)
	_draw_tree_standalone(Vector2(size.x * 0.72, mid), SPRITE_RECT_MIDLEAVES, SPRITE_RECT_SMALLROOT, 0.0, 1.05, Color.WHITE, burn_t3)
	# Tree 4 (Right Far)
	_draw_tree_standalone(Vector2(size.x * 0.86, mid), SPRITE_RECT_MIDLEAVES, SPRITE_RECT_SMALLROOT, 0.0, 0.9, Color.WHITE, burn_t4)

	# Center Protagonist Tree (NEVER burns!)
	_draw_tree_standalone(Vector2(size.x * 0.50, mid), SPRITE_RECT_SMALLLEAVES, SPRITE_RECT_SMALLROOT, 0.0, 1.0, Color.WHITE, 0.0)

	# 7. Flames & Fire Line on the grass
	if _intro_timer >= 5.8 and _intro_timer < 11.5:
		var spark_land_x := size.x * 0.58 + 28.0
		var left_t := clampf((_intro_timer - 5.8) / 3.8, 0.0, 1.0)
		var fire_left := lerpf(spark_land_x, size.x * 0.06, left_t)
		var right_t := clampf((_intro_timer - 5.8) / 2.8, 0.0, 1.0)
		var fire_right := lerpf(spark_land_x, size.x * 0.94, right_t)

		var fire_alpha := 1.0
		if _intro_timer > 10.0:
			fire_alpha = clampf((11.5 - _intro_timer) / 1.5, 0.0, 1.0)

		var step_x := 8.0
		var num_steps := int((fire_right - fire_left) / step_x)
		for s in num_steps:
			var fx := fire_left + float(s) * step_x
			if absf(fx - size.x * 0.5) < 16.0:
				continue
			var jitter := sin(fx * 0.35 + _intro_timer * 16.0) * 0.5 + 0.5
			var flame_h := jitter * 14.0 + 4.0
			var col_outer := Color("f44336")
			col_outer.a *= fire_alpha
			var col_inner := Color("ffeb3b")
			col_inner.a *= fire_alpha
			draw_rect(Rect2(fx, mid - flame_h, step_x, flame_h), col_outer)
			draw_rect(Rect2(fx + 2.0, mid - flame_h * 0.65, step_x - 4.0, flame_h * 0.65), col_inner)

	# 8. Draw Fire particles and Ash flakes on top
	_draw_intro_fire_particles()
	_draw_intro_ash_particles()

	# 9. Narrative text and prompts
	_draw_intro_narrative(size)


func _draw() -> void:
	var size := get_viewport_rect().size
	var mid := size.y * 0.5
	if _game_state != GameState.PLAYING:
		_draw_intro(size, mid)
		return

	_draw_sky(size, mid)
	_draw_hills(size, mid)
	_draw_wind_gusts(mid)
	_draw_tree(Vector2(size.x * 0.5, mid), mid)
	_draw_leaf_particles(mid)
	_draw_soil_grid(size, mid)
	_draw_health_bar(size)
	_draw_grow_button(size, mid)
	if _is_game_over:
		_draw_game_over_overlay(size)


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

	# --- WATER BAR (right below the health bar) ---
	var water_bar_pos := Vector2(20.0, 68.0)

	# Title text above the water bar
	draw_string(_vt323_font, water_bar_pos + Vector2(0.0, -6.0), "WATER", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

	# Water amount in Liters on the right (1px water source = 1L)
	var water_str := "%dL" % int(roundf(_water_stored))
	draw_string(_vt323_font, water_bar_pos + Vector2(bar_w - 60.0, -6.0), water_str, HORIZONTAL_ALIGNMENT_RIGHT, 60.0, font_size, Color("bfe3f5"))

	# Outer border/drop shadow
	draw_rect(Rect2(water_bar_pos - Vector2(border_w, border_w), Vector2(bar_w + border_w * 2.0, bar_h + border_w * 2.0)), Color(0, 0, 0, 0.7))
	# Inner dark background
	draw_rect(Rect2(water_bar_pos, Vector2(bar_w, bar_h)), Color(0.12, 0.12, 0.12, 0.85))

	var water_ratio := clampf(_water_stored / MAX_WATER_STORED, 0.0, 1.0)
	var water_fill_w := bar_w * water_ratio
	if water_fill_w > 0.0:
		var water_fill_color := WATER_COLOR.lerp(Color("5dade2"), water_ratio)
		draw_rect(Rect2(water_bar_pos, Vector2(water_fill_w, bar_h)), water_fill_color)
		draw_rect(Rect2(water_bar_pos, Vector2(water_fill_w, bar_h * 0.4)), Color(1.0, 1.0, 1.0, 0.25))

	# Inner outline
	draw_rect(Rect2(water_bar_pos, Vector2(bar_w, bar_h)), Color(1.0, 1.0, 1.0, 0.2), false, 1.0)

	# --- AIR POLLUTION BAR (right below the water bar) ---
	var poll_bar_pos := Vector2(20.0, 110.0)

	# Title text above the air pollution bar
	draw_string(_vt323_font, poll_bar_pos + Vector2(0.0, -6.0), "AIR POLLUTION", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

	# Pollution percentage on the right
	var poll_ratio := clampf(_air_pollution / MAX_AIR_POLLUTION, 0.0, 1.0)
	var poll_str := "%d%%" % int(roundf(poll_ratio * 100.0))
	draw_string(_vt323_font, poll_bar_pos + Vector2(bar_w - 60.0, -6.0), poll_str, HORIZONTAL_ALIGNMENT_RIGHT, 60.0, font_size, Color("dcdde1"))

	# Outer border/drop shadow
	draw_rect(Rect2(poll_bar_pos - Vector2(border_w, border_w), Vector2(bar_w + border_w * 2.0, bar_h + border_w * 2.0)), Color(0, 0, 0, 0.7))
	# Inner dark background
	draw_rect(Rect2(poll_bar_pos, Vector2(bar_w, bar_h)), Color(0.12, 0.12, 0.12, 0.85))

	var poll_fill_w := bar_w * poll_ratio
	if poll_fill_w > 0.0:
		# Smog gray/purple shifting to hazard red as pollution approaches 100%
		var poll_color: Color
		if poll_ratio < 0.6:
			poll_color = Color("7f8fa6").lerp(Color("c23616"), poll_ratio / 0.6 * 0.5)
		else:
			poll_color = Color("a05d43").lerp(Color("e84118"), (poll_ratio - 0.6) / 0.4)
		draw_rect(Rect2(poll_bar_pos, Vector2(poll_fill_w, bar_h)), poll_color)
		draw_rect(Rect2(poll_bar_pos, Vector2(poll_fill_w, bar_h * 0.4)), Color(1.0, 1.0, 1.0, 0.2))

	# Inner outline
	draw_rect(Rect2(poll_bar_pos, Vector2(bar_w, bar_h)), Color(1.0, 1.0, 1.0, 0.2), false, 1.0)


func _draw_grow_button(size: Vector2, mid: float) -> void:
	if not _vt323_font:
		return

	var btn_rect := _get_grow_button_rect(size, mid)
	var border_w := 2.0

	# Drop shadow / outer border
	draw_rect(
		Rect2(btn_rect.position - Vector2(border_w, border_w), btn_rect.size + Vector2(border_w * 2.0, border_w * 2.0)),
		Color(0.0, 0.0, 0.0, 0.75)
	)

	var can_grow := _water_stored > 50.0
	var bg_col: Color
	if not can_grow:
		bg_col = Color("4a4a4a")
	else:
		bg_col = Color("4ea83b") if _is_grow_btn_hovered else Color("3b852c")
	draw_rect(btn_rect, bg_col)
	# Top highlight
	draw_rect(Rect2(btn_rect.position, Vector2(btn_rect.size.x, btn_rect.size.y * 0.25)), Color(1.0, 1.0, 1.0, 0.18))
	# Inner border
	draw_rect(btn_rect, Color(1.0, 1.0, 1.0, 0.35), false, 1.0)

	# Centered label "GROW" / "TREE" / "(50L)"
	var text_col := Color.WHITE if can_grow else Color(0.7, 0.7, 0.7, 0.85)
	draw_string(_vt323_font, btn_rect.position + Vector2(0.0, 28.0), "GROW", HORIZONTAL_ALIGNMENT_CENTER, btn_rect.size.x, 22, text_col)
	draw_string(_vt323_font, btn_rect.position + Vector2(0.0, 50.0), "TREE", HORIZONTAL_ALIGNMENT_CENTER, btn_rect.size.x, 22, text_col)
	draw_string(_vt323_font, btn_rect.position + Vector2(0.0, 72.0), "(50L)", HORIZONTAL_ALIGNMENT_CENTER, btn_rect.size.x, 18, Color("bfe3f5") if can_grow else text_col)


func _draw_game_over_overlay(size: Vector2) -> void:
	if not _vt323_font:
		return

	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.72))

	var center_y := size.y * 0.45
	draw_string(_vt323_font, Vector2(0.0, center_y), "GAME OVER", HORIZONTAL_ALIGNMENT_CENTER, size.x, 72, Color("ff5252"))
	draw_string(_vt323_font, Vector2(0.0, center_y + 45.0), _game_over_reason, HORIZONTAL_ALIGNMENT_CENTER, size.x, 32, Color.WHITE)
	draw_string(_vt323_font, Vector2(0.0, center_y + 90.0), "CLICK OR PRESS R TO RESTART", HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, Color("bfe3f5"))


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
			if is_root:
				# Render retro pixel-art connective bitmask root tile
				_draw_pixel_art_root(cell, Vector2(x, y), base_row_color)
			else:
				# 1. Base soil tile rendering
				draw_rect(tile_rect, base_row_color)

				# 2. Bevel lines for soil grid (only on soil, never cutting through roots)
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


func _is_root_cell(c: Vector2i) -> bool:
	if c.y < 0:
		# Row 0 top connects seamlessly to the tree trunk base
		var size := get_viewport_rect().size
		var cols := int(ceil(size.x / TILE_SIZE))
		var center_col := int(cols * 0.5)
		return c.x >= center_col - 2 and c.x <= center_col + 1
	return _initial_root_tiles.has(c) or _root_tiles.has(c)


func _draw_pixel_art_root(cell: Vector2i, pos: Vector2, soil_col: Color) -> void:
	var u: bool = _is_root_cell(cell + Vector2i(0, -1))
	var d: bool = _is_root_cell(cell + Vector2i(0, 1))
	var l: bool = _is_root_cell(cell + Vector2i(-1, 0))
	var r: bool = _is_root_cell(cell + Vector2i(1, 0))

	var ul: bool = _is_root_cell(cell + Vector2i(-1, -1))
	var ur: bool = _is_root_cell(cell + Vector2i(1, -1))
	var dl: bool = _is_root_cell(cell + Vector2i(-1, 1))
	var dr: bool = _is_root_cell(cell + Vector2i(1, 1))

	var px: float = pos.x
	var py: float = pos.y

	# 1. Base wood core fill (8x8)
	draw_rect(Rect2(px, py, TILE_SIZE, TILE_SIZE), ROOT_WOOD_CORE)

	# 2. Natural wood grain fiber & subtle light texture
	if (u or d) and not (l and r):
		# Vertical flow dominant: highlight on left, darker fiber on right
		draw_rect(Rect2(px + 2.0, py, 1.0, 8.0), ROOT_WOOD_LIGHT)
		draw_rect(Rect2(px + 5.0, py, 1.0, 8.0), ROOT_WOOD_GRAIN)
	elif (l or r) and not (u and d):
		# Horizontal flow dominant: highlight on top, darker fiber on bottom
		draw_rect(Rect2(px, py + 2.0, 8.0, 1.0), ROOT_WOOD_LIGHT)
		draw_rect(Rect2(px, py + 5.0, 8.0, 1.0), ROOT_WOOD_GRAIN)
	else:
		# Cross / center junction: gentle organic knot pattern
		var knot_hash := posmod(cell.x * 37 + cell.y * 19, 7)
		if knot_hash == 0 or knot_hash == 3:
			draw_rect(Rect2(px + 3.0, py + 3.0, 2.0, 2.0), ROOT_WOOD_GRAIN)
			draw_rect(Rect2(px + 2.0, py + 2.0, 1.0, 1.0), ROOT_WOOD_LIGHT)

	# 3. Outer dark bark boundaries with directional light & shadow (Matching tree trunk)
	# Top edge (light from top-left): 1px dark bark + 1px light highlight
	if not u:
		draw_rect(Rect2(px, py, 8.0, 1.0), ROOT_BARK_DARK)
		draw_rect(Rect2(px, py + 1.0, 8.0, 1.0), ROOT_WOOD_LIGHT)
	# Left edge (sunlit side): 1px dark bark + 1px light highlight
	if not l:
		draw_rect(Rect2(px, py, 1.0, 8.0), ROOT_BARK_DARK)
		draw_rect(Rect2(px + 1.0, py, 1.0, 8.0), ROOT_WOOD_LIGHT)
	# Bottom edge (shaded side): 1px dark bark + 1px shadow bevel
	if not d:
		draw_rect(Rect2(px, py + 7.0, 8.0, 1.0), ROOT_BARK_DARK)
		draw_rect(Rect2(px, py + 6.0, 8.0, 1.0), ROOT_BARK_SHADOW)
	# Right edge (shaded side): 1px dark bark + 1px shadow bevel
	if not r:
		draw_rect(Rect2(px + 7.0, py, 1.0, 8.0), ROOT_BARK_DARK)
		draw_rect(Rect2(px + 6.0, py, 1.0, 8.0), ROOT_BARK_SHADOW)

	# 4. Convex Outer Corners (Pixel Art Corner Rounding into soil)
	if not u and not l:
		draw_rect(Rect2(px, py, 1.0, 1.0), soil_col)
		draw_rect(Rect2(px + 1.0, py, 1.0, 1.0), ROOT_BARK_DARK)
		draw_rect(Rect2(px, py + 1.0, 1.0, 1.0), ROOT_BARK_DARK)
		draw_rect(Rect2(px + 1.0, py + 1.0, 1.0, 1.0), ROOT_WOOD_LIGHT)
	if not u and not r:
		draw_rect(Rect2(px + 7.0, py, 1.0, 1.0), soil_col)
		draw_rect(Rect2(px + 6.0, py, 1.0, 1.0), ROOT_BARK_DARK)
		draw_rect(Rect2(px + 7.0, py + 1.0, 1.0, 1.0), ROOT_BARK_DARK)
		draw_rect(Rect2(px + 6.0, py + 1.0, 1.0, 1.0), ROOT_BARK_SHADOW)
	if not d and not l:
		draw_rect(Rect2(px, py + 7.0, 1.0, 1.0), soil_col)
		draw_rect(Rect2(px + 1.0, py + 7.0, 1.0, 1.0), ROOT_BARK_DARK)
		draw_rect(Rect2(px, py + 6.0, 1.0, 1.0), ROOT_BARK_DARK)
		draw_rect(Rect2(px + 1.0, py + 6.0, 1.0, 1.0), ROOT_WOOD_LIGHT)
	if not d and not r:
		draw_rect(Rect2(px + 7.0, py + 7.0, 1.0, 1.0), soil_col)
		draw_rect(Rect2(px + 6.0, py + 7.0, 1.0, 1.0), ROOT_BARK_DARK)
		draw_rect(Rect2(px + 7.0, py + 6.0, 1.0, 1.0), ROOT_BARK_DARK)
		draw_rect(Rect2(px + 6.0, py + 6.0, 1.0, 1.0), ROOT_BARK_SHADOW)

	# 5. Concave Inner Corners (Elbow Branch Notches)
	if u and l and not ul:
		draw_rect(Rect2(px, py, 1.0, 1.0), ROOT_BARK_DARK)
		draw_rect(Rect2(px + 1.0, py + 1.0, 1.0, 1.0), ROOT_BARK_SHADOW)
	if u and r and not ur:
		draw_rect(Rect2(px + 7.0, py, 1.0, 1.0), ROOT_BARK_DARK)
		draw_rect(Rect2(px + 6.0, py + 1.0, 1.0, 1.0), ROOT_BARK_SHADOW)
	if d and l and not dl:
		draw_rect(Rect2(px, py + 7.0, 1.0, 1.0), ROOT_BARK_DARK)
		draw_rect(Rect2(px + 1.0, py + 6.0, 1.0, 1.0), ROOT_BARK_SHADOW)
	if d and r and not dr:
		draw_rect(Rect2(px + 7.0, py + 7.0, 1.0, 1.0), ROOT_BARK_DARK)
		draw_rect(Rect2(px + 6.0, py + 6.0, 1.0, 1.0), ROOT_BARK_SHADOW)

	# 6. Terminal Tip / Active Growth Point
	var neighbor_count: int = (1 if u else 0) + (1 if d else 0) + (1 if l else 0) + (1 if r else 0)
	var depth: int = _root_tiles.get(cell, 0)
	if neighbor_count <= 1 and depth > 0:
		draw_rect(Rect2(px + 3.0, py + 3.0, 2.0, 2.0), ROOT_TIP_COLOR)

	# 7. Animated Water Absorption Pulse (Aşağıdan yukarıya, 5 piksel akış + yarım saniye duraksama)
	if _is_connected_to_water and _water_flow_cells.has(cell):
		var dist: int = _water_flow_cells[cell]
		# 10 hücrelik döngü (hız=10): 5 hücrelik su akışı (0.5 sn) ardından 5 hücrelik duraksama (0.5 sn)
		var wave: float = fmod(_water_pulse_time * 10.0 - float(dist), 10.0)
		if wave >= 0.0 and wave < 5.0:
			# 5 piksel boyunca ilerleyen mavi su akışı
			draw_rect(Rect2(px + 2.0, py + 2.0, 4.0, 4.0), ROOT_WATER_FLOW)
			# Dalganın öncü parlak su damlası
			if wave < 1.6:
				draw_rect(Rect2(px + 2.5, py + 2.5, 3.0, 3.0), Color.WHITE)


func _update_water_flow_path() -> void:
	_water_flow_cells.clear()
	if not _is_connected_to_water:
		return

	# 1. Ağaç tabanından (satır 0) tüm bağlı köklere kesintisiz BFS yol haritası kur
	var size := get_viewport_rect().size
	var cols := int(ceil(size.x / TILE_SIZE))
	var center_col := int(cols * 0.5)

	var queue: Array[Vector2i] = []
	var parent_map: Dictionary = {}
	var dist_to_trunk: Dictionary = {}

	for cx in range(center_col - 2, center_col + 2):
		var root_base := Vector2i(cx, 0)
		if _initial_root_tiles.has(root_base) or _root_tiles.has(root_base):
			queue.append(root_base)
			dist_to_trunk[root_base] = 0
			parent_map[root_base] = root_base

	var head := 0
	while head < queue.size():
		var curr: Vector2i = queue[head]
		head += 1
		var cur_d: int = dist_to_trunk[curr]

		var neighbors := [
			curr + Vector2i(0, 1),
			curr + Vector2i(0, -1),
			curr + Vector2i(1, 0),
			curr + Vector2i(-1, 0),
			curr + Vector2i(1, 1),
			curr + Vector2i(-1, 1),
			curr + Vector2i(1, -1),
			curr + Vector2i(-1, -1)
		]
		for n in neighbors:
			if not (_initial_root_tiles.has(n) or _root_tiles.has(n)):
				continue
			if not dist_to_trunk.has(n):
				dist_to_trunk[n] = cur_d + 1
				parent_map[n] = curr
				queue.append(n)

	# 2. Her aktif su kaynağından SADECE TEK BİR temas noktası seç (Kalınlığı 1 olan tek şerit akış için)
	var contact_cells: Array[Vector2i] = []
	for bank in _water_banks:
		var rect: Rect2i = bank["rect"]
		var drained: int = bank["drained_layers"]
		var water_min_y := rect.position.y + drained
		var water_max_y := rect.position.y + rect.size.y - 1
		var water_min_x := rect.position.x
		var water_max_x := rect.position.x + rect.size.x - 1
		if water_min_y > water_max_y:
			continue

		var bank_contacts: Array[Vector2i] = []
		for y in range(water_min_y - 1, water_max_y + 2):
			for x in range(water_min_x - 1, water_max_x + 2):
				if x >= water_min_x and x <= water_max_x and y >= water_min_y and y <= water_max_y:
					continue
				var c := Vector2i(x, y)
				if (_initial_root_tiles.has(c) or _root_tiles.has(c)) and parent_map.has(c):
					if not bank_contacts.has(c):
						bank_contacts.append(c)

		if bank_contacts.is_empty():
			continue

		# Suya temas eden hücreler arasından ağaca en yakın olan TEK BİR temas hücresini seç
		var best_c := bank_contacts[0]
		var min_d: int = dist_to_trunk[best_c]
		for bc in bank_contacts:
			if dist_to_trunk[bc] < min_d:
				min_d = dist_to_trunk[bc]
				best_c = bc
		contact_cells.append(best_c)

	# 3. Seçilen tek temas noktasından satır 0'a kadar tek şeritlik (kalınlığı 1) akış zincirini oluştur
	for contact in contact_cells:
		var curr := contact
		var step_count := 0
		while true:
			if not _water_flow_cells.has(curr) or _water_flow_cells[curr] > step_count:
				_water_flow_cells[curr] = step_count
			if curr.y <= 0 or parent_map[curr] == curr:
				break
			curr = parent_map[curr]
			step_count += 1

