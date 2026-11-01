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
const SOIL_TOP := Color("4a2d18")
const SOIL_BOTTOM := Color("170a04")
const TRUNK := Color("4a240c")
const LEAVES_DARK := Color("2f6b2a")
const LEAVES := Color("3f8a36")
const LEAVES_LIGHT := Color("58a84a")

const WATER_COLOR := Color("2980b9")
const WATER_EDGE := Color("1f5f8b")
const ACID_WATER_COLOR := Color("16a05d") # Greenish dark-turquoise for acid pools
const ACID_WATER_EDGE := Color("0e6e3e")
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

const INITIAL_WATER := 100.0
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
var _tree_white_texture: Texture2D = null
var _wood_log_texture: Texture2D = null
var _recovery_fill_texture: Texture2D = null
var _leaf_btn_texture: Texture2D = null
var _vt323_font: Font = null
var _root_grow_player: AudioStreamPlayer = null
var _wind_player: AudioStreamPlayer = null
var _rain_player: AudioStreamPlayer = null
var _rock_player: AudioStreamPlayer = null
const ROOT_SFX_HOLD_TIME := 0.14
var _root_sfx_timer: float = 0.0

var _intro_cutscene: Node2D = null
var _victory_cutscene: Node2D = null
var _water_stored: float = INITIAL_WATER # Starts at 50L (equivalent to 50px of water source)
var _tree_health: float = 5.0 # Starts at 5 HP (bare small trunk, health 0-10 has no leaves)
var _air_pollution: float = 35.0
const GAME_DURATION := 60.0
var _game_timer: float = GAME_DURATION
var _is_game_won: bool = false
var _is_game_over: bool = false
var _is_paused: bool = false
var _pause_hovered_btn_idx: int = 0
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
var _wind_target_strength: float = 0.0
var _wind_direction: float = 1.0 # 1.0 = blowing right, -1.0 = blowing left
var _is_wind_active: bool = false
var _wind_state_timer: float = 1.5
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
var _current_leaf_rect: Rect2 = Rect2()
var _prev_leaf_rect: Rect2 = Rect2()
var _current_leaf_offset_px: float = 0.0
var _prev_leaf_offset_px: float = 0.0
var _leaf_dissolve_t: float = 1.0

var _current_trunk_rect: Rect2 = SPRITE_RECT_SMALLROOT
var _prev_trunk_rect: Rect2 = SPRITE_RECT_SMALLROOT
var _trunk_dissolve_t: float = 1.0

# Weather cycle (Wind -> Heat Wave -> Acid Rain)
const WEATHER_DURATION_WIND := 10.0
const WEATHER_DURATION_HEATWAVE := 5.0
const WEATHER_DURATION_ACID_RAIN := 5.0
const WEATHER_WIND := 0
const WEATHER_HEATWAVE := 1
const WEATHER_ACID_RAIN := 2
const HEATWAVE_WATER_DRAIN_RATE := 2.0 # 2L per second from water bar and all water sources
const SKY_HEAT_TOP := Color("ff9f1c")
const SKY_HEAT_HORIZON := Color("ffe66d")
const SKY_ACID_TOP := Color("555c60")
const SKY_ACID_HORIZON := Color("8b9398")
const SUN_HEAT_COLOR := Color("ffb347")
var _weather_state: int = WEATHER_WIND
var _is_heatwave: bool = false
var _is_acid_rain: bool = false
var _weather_cycle_timer: float = WEATHER_DURATION_WIND
var _heatwave_intensity: float = 0.0 # Smoothly transitions 0.0 -> 1.0 during heatwave
var _acid_rain_intensity: float = 0.0 # Smoothly transitions 0.0 -> 1.0 during acid rain
var _acid_rain_drops: Array = []

# Pixel-art gray rain clouds (one '#' = one 8x8 pixel); rain falls from their underside
const CLOUD_SHAPE_A := [
	"....####........",
	"..########.###..",
	".##############.",
	"################",
	".##############.",
]
const CLOUD_SHAPE_B := [
	"......#####.....",
	"...##########...",
	".###############",
	"################",
	"..############..",
]
const CLOUD_ROW_COLORS := [
	Color("a9b0b4"),
	Color("8e969b"),
	Color("7a8389"),
	Color("666e74"),
	Color("565d63"),
]
const CLOUD_FX := [0.08, 0.32, 0.58, 0.82]
const CLOUD_TOP_FRAC := [0.06, 0.15, 0.07, 0.14]
const CLOUD_DRIFT_SPEED := 10.0
var _cloud_drift: float = 0.0

const HUD_ICON_X := 20.0
const HUD_BAR_X := 20.0
const HUD_ICON_PIXEL := 1.5
const HUD_ICON_HEART := [
	"..ooo.ooo..",
	".o###o###o.",
	"o#ww######o",
	"o#########o",
	"o#########o",
	".o#######o.",
	"..o#####o..",
	"...o###o...",
	"....o#o....",
	".....o.....",
]
const HUD_ICON_HEART_COLORS := {"o": Color("4a0d0d"), "#": Color("e53935"), "w": Color("ff8a80")}
const HUD_ICON_DROP := [
	".....o.....",
	"....o#o....",
	"....o#o....",
	"...o###o...",
	"...o###o...",
	"..o#w###o..",
	".o##w####o.",
	".o#######o.",
	".o#######o.",
	"..o#####o..",
	"...ooooo...",
]
const HUD_ICON_DROP_COLORS := {"o": Color("1a3d5c"), "#": Color("3498db"), "w": Color("bfe3f5")}
const HUD_ICON_SMOKE := [
	"....ooo....",
	"..oo###oo..",
	".o#w#####oo",
	"o#########o",
	"o#########o",
	".ooooooooo.",
]
const HUD_ICON_SMOKE_COLORS := {"o": Color("3a3d40"), "#": Color("9aa0a6"), "w": Color("dcdde1")}
const RECOVERY_SPROUT_LEAVES := [
	".............oo.",
	"...........oo##o",
	"o........oo###vo",
	"oo.....oo###v##o",
	"o#o...o###v###o.",
	"o##o.o###v####o.",
	"o#v#o###v####o..",
	".o#vo##v####o...",
	".o##o#v####o....",
	"..ooo#####o.....",
	"...o.o###o......",
	"...o.oooo.......",
]
const RECOVERY_SPROUT_COLORS := {
	"o": Color("2a3b1c"),
	"v": Color("2f4724"),
	"#": Color("476e3f"),
}

# Water bar bubbles, pollution flash timers & HUD bar animation timer
var _water_bar_bubbles: Array = []
var _water_ghost_stored: float = INITIAL_WATER
var _water_ghost_hold: float = 0.0
var _pollution_flash_time: float = 0.0
var _hud_anim_time: float = 0.0
var _pollution_rising_tint: float = 0.0

# Grow button hover expansion, spring press animation & burst leaf particles
var _grow_btn_hover_scale: float = 1.0
var _grow_btn_spring_time: float = 0.0
var _grow_btn_leaf_particles: Array = []


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	if ResourceLoader.exists("res://assets/tree.png"):
		_tree_texture = load("res://assets/tree.png")
		if _tree_texture:
			var tree_img := _tree_texture.get_image()
			if tree_img:
				tree_img = preload("res://scripts/tree_sprite.gd").get_shaded_image()
				_tree_texture = preload("res://scripts/tree_sprite.gd").get_shaded_texture()
				var white_img := tree_img.duplicate() as Image
				for py in white_img.get_height():
					for px in white_img.get_width():
						var a := white_img.get_pixel(px, py).a
						if a > 0.0:
							white_img.set_pixel(px, py, Color(1.0, 1.0, 1.0, a))
				_tree_white_texture = ImageTexture.create_from_image(white_img)
	if ResourceLoader.exists("res://assets/Rocks.png"):
		_rocks_texture = load("res://assets/Rocks.png")
		if _rocks_texture:
			_rocks_image = _rocks_texture.get_image()
	if ResourceLoader.exists("res://assets/wood_log.png"):
		_wood_log_texture = load("res://assets/wood_log.png")
	if ResourceLoader.exists("res://assets/recovery_fill.png"):
		_recovery_fill_texture = load("res://assets/recovery_fill.png")
	if not _recovery_fill_texture and FileAccess.file_exists("res://assets/recovery_fill.png"):
		var rec_img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/recovery_fill.png"))
		if rec_img:
			_recovery_fill_texture = ImageTexture.create_from_image(rec_img)
	if ResourceLoader.exists("res://assets/leaf.png"):
		_leaf_btn_texture = load("res://assets/leaf.png")
	if not _leaf_btn_texture and FileAccess.file_exists("res://assets/leaf.png"):
		var lf_img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/leaf.png"))
		if lf_img:
			_leaf_btn_texture = ImageTexture.create_from_image(lf_img)
	_vt323_font = load("res://assets/VT323-Regular.ttf")
	if ResourceLoader.exists("res://assets/root_grow.mp3"):
		var sfx_stream := load("res://assets/root_grow.mp3")
		if sfx_stream is AudioStreamMP3:
			sfx_stream.loop = true
		_root_grow_player = AudioStreamPlayer.new()
		_root_grow_player.stream = sfx_stream
		add_child(_root_grow_player)
	if ResourceLoader.exists("res://assets/wind.mp3"):
		var wind_stream := load("res://assets/wind.mp3")
		if wind_stream is AudioStreamMP3:
			wind_stream.loop = true
		_wind_player = AudioStreamPlayer.new()
		_wind_player.stream = wind_stream
		add_child(_wind_player)
	if ResourceLoader.exists("res://assets/rain.mp3"):
		var rain_stream := load("res://assets/rain.mp3")
		if rain_stream is AudioStreamMP3:
			rain_stream.loop = true
		_rain_player = AudioStreamPlayer.new()
		_rain_player.stream = rain_stream
		add_child(_rain_player)
	if ResourceLoader.exists("res://assets/rock.mp3"):
		var rock_stream := load("res://assets/rock.mp3")
		_rock_player = AudioStreamPlayer.new()
		_rock_player.stream = rock_stream
		_rock_player.volume_db = 6.0
		add_child(_rock_player)
	_wind_rng.randomize()
	get_viewport().size_changed.connect(_on_size_changed)
	_generate_world()
	_init_wind_particles()
	_init_acid_rain_drops()
	var intro_script = load("res://scripts/intro_cutscene.gd")
	if intro_script:
		_intro_cutscene = intro_script.new()
		_intro_cutscene.finished.connect(_on_intro_finished)
		add_child(_intro_cutscene)


func _on_intro_finished() -> void:
	if _intro_cutscene:
		_intro_cutscene.queue_free()
		_intro_cutscene = null
	queue_redraw()


func _trigger_victory() -> void:
	_stop_all_looping_sfx()
	_is_lmb_down = false
	var victory_script = load("res://scripts/victory_cutscene.gd")
	if victory_script:
		_victory_cutscene = victory_script.new()
		_victory_cutscene.finished.connect(_on_victory_finished)
		add_child(_victory_cutscene)
	queue_redraw()


func _on_victory_finished() -> void:
	if _victory_cutscene:
		_victory_cutscene.queue_free()
		_victory_cutscene = null
	var tree := get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/main_menu.tscn")


func _stop_all_looping_sfx() -> void:
	if _root_grow_player and _root_grow_player.playing:
		_root_grow_player.stop()
	if _wind_player and _wind_player.playing:
		_wind_player.stop()
	if _rain_player and _rain_player.playing:
		_rain_player.stop()


func _process(delta: float) -> void:
	if _intro_cutscene != null or _victory_cutscene != null:
		return

	if _is_paused:
		_stop_all_looping_sfx()
		return

	if _is_game_over:
		_stop_all_looping_sfx()
		return

	# Wind SFX: plays when the wind is active (tree is oscillating)
	if _wind_player:
		if _is_tree_oscillating():
			if not _wind_player.playing:
				_wind_player.play()
		else:
			if _wind_player.playing:
				_wind_player.stop()

	# Rain SFX: plays during acid rain
	if _rain_player:
		if _is_acid_rain:
			if not _rain_player.playing:
				_rain_player.play()
		else:
			if _rain_player.playing:
				_rain_player.stop()

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

		var is_acid: bool = bank.get("is_acid", false)
		var layer_time: float = bank["layer_time"]
		var bank_drained_this_frame := false

		if not is_acid and _is_root_touching_bank(bank):
			connected_now = true
			# Drain rate in water cells per second = width / layer_time = 1.0 / 0.4 = 2.5 cells/sec (1px = 1L)
			var cells_per_second: float = float(rect.size.x) / layer_time
			var absorbed: float = cells_per_second * delta
			_water_stored = minf(_water_stored + absorbed, MAX_WATER_STORED)
			intake_this_frame += cells_per_second

			bank["drain_timer"] += delta
			bank_drained_this_frame = true

		# Heat wave drains 2L (2 cells) of water per second from every usable water source
		if _is_heatwave and not is_acid and bank["drained_layers"] < rect.size.y:
			var heat_timer_advance := (HEATWAVE_WATER_DRAIN_RATE / float(rect.size.x)) * layer_time * delta
			bank["drain_timer"] += heat_timer_advance
			bank_drained_this_frame = true

		if bank_drained_this_frame:
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

	# Heat wave also drains 2L of water per second from our stored water bar
	if _is_heatwave:
		var old_water := _water_stored
		_water_stored = maxf(0.0, _water_stored - HEATWAVE_WATER_DRAIN_RATE * delta)
		if not is_equal_approx(old_water, _water_stored):
			needs_redraw = true

	if _update_heatwave(delta):
		needs_redraw = true

	if _update_wind(delta):
		needs_redraw = true

	# Tree health decreases only when the tree is oscillating during the wind state (or 2x faster during a heat wave or acid rain), and only increases via GROW TREE
	# Difficulty multiplier: Easy = 1.0x, Medium = 1.125x, Hard = 1.25x
	var diff_mult := 1.0
	if GameSettings:
		diff_mult = GameSettings.get_health_decay_multiplier()

	var old_hp := _tree_health
	var current_health_decay := 0.0
	if _is_heatwave or _is_acid_rain:
		current_health_decay = HEALTH_DECAY_RATE * 2.0 * diff_mult
	elif _is_tree_oscillating():
		current_health_decay = HEALTH_DECAY_RATE * diff_mult
	_tree_health = maxf(0.0, _tree_health - current_health_decay * delta)
	if not is_equal_approx(old_hp, _tree_health):
		needs_redraw = true

	# Update air pollution based on tree health & leaf state:
	# When health > 20, the tree has green leaves and decreases air pollution at a rate scaled by tree health
	# (slowly at 20-40 HP, faster as health approaches 80-100 HP). When <= 20 HP (dry leaves), pollution rises.
	var old_pollution := _air_pollution
	var is_pollution_rising := _tree_health <= 20.0 and _air_pollution < MAX_AIR_POLLUTION
	if _tree_health <= 20.0:
		_air_pollution = minf(MAX_AIR_POLLUTION, _air_pollution + POLLUTION_RISE_RATE * delta)
	else:
		var health_factor := clampf((_tree_health - 20.0) / 80.0, 0.0, 1.0)
		var decay_rate := lerpf(POLLUTION_DECAY_SMALL, POLLUTION_DECAY_LARGE, health_factor)
		_air_pollution = maxf(0.0, _air_pollution - decay_rate * delta)

	_pollution_rising_tint = move_toward(_pollution_rising_tint, 1.0 if is_pollution_rising else 0.0, delta * 2.5)

	if not is_equal_approx(old_pollution, _air_pollution):
		needs_redraw = true

	_hud_anim_time += delta
	if _water_ghost_stored > _water_stored:
		if _water_ghost_hold > 0.0:
			_water_ghost_hold = maxf(0.0, _water_ghost_hold - delta)
		else:
			_water_ghost_stored = move_toward(_water_ghost_stored, _water_stored, 65.0 * delta)
	else:
		_water_ghost_stored = _water_stored
		_water_ghost_hold = 0.0
	needs_redraw = true

	var prev_second := int(ceilf(_game_timer))
	_game_timer = maxf(0.0, _game_timer - delta)
	if int(ceilf(_game_timer)) != prev_second:
		needs_redraw = true

	# Flash pollution bar when air pollution > 80% (80% of MAX_AIR_POLLUTION)
	if _air_pollution >= 80.0:
		_pollution_flash_time += delta
		needs_redraw = true
	else:
		_pollution_flash_time = 0.0

	# Spawn and update bubbles in the water bar when water is increasing
	var is_water_increasing := _active_water_intake_rate > 0.001
	if is_water_increasing and _water_stored < MAX_WATER_STORED:
		if _wind_rng.randf() < 0.45:
			_water_bar_bubbles.append({
				"rel_x": _wind_rng.randf_range(0.05, 0.95), # relative to water fill width
				"y": 18.0, # starts near bottom of water bar (bar_h = 18.0)
				"speed": _wind_rng.randf_range(20.0, 35.0),
				"size": 2.0 if _wind_rng.randf() < 0.65 else 3.0,
				"wobble_phase": _wind_rng.randf_range(0.0, TAU)
			})
		needs_redraw = true

	if not _water_bar_bubbles.is_empty():
		for bi in range(_water_bar_bubbles.size() - 1, -1, -1):
			var b: Dictionary = _water_bar_bubbles[bi]
			b["y"] -= b["speed"] * delta
			if b["y"] <= 1.0:
				_water_bar_bubbles.remove_at(bi)
		needs_redraw = true

	# Update grow button hover scale transition & spring animation
	var can_grow_now := _water_stored > 50.0 and not _is_game_over
	var target_hover_scale := 1.15 if (_is_grow_btn_hovered and can_grow_now) else 1.0
	_grow_btn_hover_scale = move_toward(_grow_btn_hover_scale, target_hover_scale, delta * 4.5)
	if _grow_btn_spring_time > 0.0:
		_grow_btn_spring_time = maxf(0.0, _grow_btn_spring_time - delta)
		needs_redraw = true

	# Update tiny burst leaf particles (only live on the top half of the screen)
	if not _grow_btn_leaf_particles.is_empty():
		var mid_screen := get_viewport_rect().size.y * 0.5
		for pi in range(_grow_btn_leaf_particles.size() - 1, -1, -1):
			var p: Dictionary = _grow_btn_leaf_particles[pi]
			p["age"] += delta
			if p["age"] >= p["max_age"] or p["pos"].y >= mid_screen:
				_grow_btn_leaf_particles.remove_at(pi)
			else:
				p["vel"].y += 240.0 * delta # gravity pulling down
				p["vel"].x *= (1.0 - 1.2 * delta) # air drag
				p["pos"] += p["vel"] * delta
				p["pos"].x += sin(_hud_anim_time * 8.0 + p["wobble"]) * 14.0 * delta # gentle flutter
				if p["pos"].y >= mid_screen:
					_grow_btn_leaf_particles.remove_at(pi)
		needs_redraw = true

	var is_tr := false
	if GameSettings:
		is_tr = (GameSettings.language == GameSettings.Language.TR)

	# Check Win condition: timer hits 0:00 -> Trigger Victory Outro Cutscene
	if _game_timer <= 0.0 and not _is_game_over:
		_game_timer = 0.0
		_is_game_over = true
		_is_game_won = true
		_trigger_victory()
		return

	# Check Game Over condition: air pollution reaches 100%
	if _air_pollution >= MAX_AIR_POLLUTION:
		_air_pollution = MAX_AIR_POLLUTION
		_is_game_over = true
		_is_game_won = false
		_game_over_reason = "HAVA KİRLİLİĞİ %100'E ULAŞTI" if is_tr else "AIR POLLUTION REACHED 100%"
		needs_redraw = true

	if _update_tree_transitions(delta):
		needs_redraw = true

	if _update_leaf_particles(delta):
		needs_redraw = true

	if needs_redraw:
		queue_redraw()


func _get_target_leaf_rect() -> Rect2:
	# From health 0 to 10: only small trunk, no leaves (empty Rect2)
	# Health 10 to 20: dry leaves; beyond 20: green leaves scaled by health
	if _tree_health <= 10.0:
		return Rect2()
	elif _tree_health <= 20.0:
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

	_water_ghost_stored = maxf(_water_ghost_stored, _water_stored)
	_water_ghost_hold = 0.18
	_water_stored -= 50.0

	# Trigger spring animation & spawn burst of tiny falling leaves from button center
	_grow_btn_spring_time = 0.45
	var size := get_viewport_rect().size
	var mid := size.y * 0.5
	var b_rect := _get_grow_button_rect(size, mid)
	var btn_center := b_rect.position + b_rect.size * 0.5
	for k in 14:
		var angle := _wind_rng.randf_range(-PI * 0.95, -PI * 0.05) # pop upward and outwards
		var spd := _wind_rng.randf_range(80.0, 190.0)
		_grow_btn_leaf_particles.append({
			"pos": btn_center + Vector2(_wind_rng.randf_range(-12.0, 12.0), _wind_rng.randf_range(-12.0, 12.0)),
			"vel": Vector2(cos(angle) * spd, sin(angle) * spd),
			"size": _wind_rng.randf_range(2.5, 5.0),
			"color": Color("7cb342") if _wind_rng.randf() < 0.5 else Color("558b2f"),
			"wobble": _wind_rng.randf_range(0.0, TAU),
			"age": 0.0,
			"max_age": _wind_rng.randf_range(0.85, 1.45)
		})

	if _tree_health <= 10.0:
		_tree_health = 25.0
	elif _tree_health <= 20.0:
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
	_water_stored = INITIAL_WATER
	_water_ghost_stored = INITIAL_WATER
	_water_ghost_hold = 0.0
	_tree_health = 5.0
	_air_pollution = 35.0
	_is_game_over = false
	_is_game_won = false
	_game_over_reason = ""
	_game_timer = GAME_DURATION
	_weather_state = WEATHER_WIND
	_is_heatwave = false
	_is_acid_rain = false
	_weather_cycle_timer = WEATHER_DURATION_WIND
	_heatwave_intensity = 0.0
	_acid_rain_intensity = 0.0
	_wind_strength = 0.0
	_wind_target_strength = 0.0
	_is_wind_active = false
	_wind_state_timer = 1.5
	_wind_direction = -1.0 if _wind_rng.randf() < 0.5 else 1.0
	_current_leaf_rect = _get_target_leaf_rect()
	_prev_leaf_rect = _current_leaf_rect
	_current_trunk_rect = _get_target_trunk_rect()
	_prev_trunk_rect = _current_trunk_rect
	_leaf_dissolve_t = 1.0
	_trunk_dissolve_t = 1.0
	_soil_scroll_y = 0.0
	_is_lmb_down = false
	_has_last_drag_cell = false
	_active_drag_Safe_tiles.clear()
	_active_drag_history.clear()
	_water_bar_bubbles.clear()
	_pollution_flash_time = 0.0
	_pollution_rising_tint = 0.0
	_root_sfx_timer = 0.0
	_stop_all_looping_sfx()
	_generate_world()
	queue_redraw()


func _get_weather_duration(state: int) -> float:
	match state:
		WEATHER_WIND:
			return WEATHER_DURATION_WIND
		WEATHER_HEATWAVE:
			return WEATHER_DURATION_HEATWAVE
		WEATHER_ACID_RAIN:
			return WEATHER_DURATION_ACID_RAIN
		_:
			return 5.0


func _update_heatwave(delta: float) -> bool:
	var changed := false
	_weather_cycle_timer -= delta
	if _weather_cycle_timer <= 0.0:
		# Cycle: Wind -> Heat Wave -> (Acid Rain only when air pollution > 50) -> Wind
		match _weather_state:
			WEATHER_WIND:
				_weather_state = WEATHER_HEATWAVE
			WEATHER_HEATWAVE:
				_weather_state = WEATHER_ACID_RAIN if _air_pollution > 50.0 else WEATHER_WIND
			_:
				_weather_state = WEATHER_WIND
		_weather_cycle_timer += _get_weather_duration(_weather_state)
		_is_heatwave = (_weather_state == WEATHER_HEATWAVE)
		_is_acid_rain = (_weather_state == WEATHER_ACID_RAIN)

		if _weather_state == WEATHER_WIND:
			_is_wind_active = false
			_wind_target_strength = 0.0
			_wind_state_timer = _wind_rng.randf_range(1.2, 1.8)
			_wind_direction = -1.0 if _wind_rng.randf() < 0.5 else 1.0
		elif _weather_state == WEATHER_HEATWAVE:
			_is_wind_active = false
			_wind_target_strength = 0.0
		elif _weather_state == WEATHER_ACID_RAIN:
			_is_wind_active = false
			_wind_target_strength = 0.0
			_contaminate_unconnected_water_sources()
		changed = true

	var target_heat := 1.0 if _is_heatwave else 0.0
	var prev_heat := _heatwave_intensity
	_heatwave_intensity = move_toward(_heatwave_intensity, target_heat, delta * 0.9)
	if not is_equal_approx(prev_heat, _heatwave_intensity):
		changed = true

	var target_acid := 1.0 if _is_acid_rain else 0.0
	var prev_acid := _acid_rain_intensity
	_acid_rain_intensity = move_toward(_acid_rain_intensity, target_acid, delta * 0.9)
	if not is_equal_approx(prev_acid, _acid_rain_intensity):
		changed = true

	if _acid_rain_intensity > 0.01:
		var size := get_viewport_rect().size
		var mid := size.y * 0.5
		_cloud_drift += CLOUD_DRIFT_SPEED * delta
		for drop in _acid_rain_drops:
			drop["y"] += drop["speed"] * delta
			if drop["y"] >= mid:
				_respawn_rain_drop(drop, size, mid, false)
		changed = true

	return changed


func _contaminate_unconnected_water_sources() -> void:
	# Find all remaining water sources that are neither already acid nor connected to roots
	var candidates: Array[int] = []
	for i in _water_banks.size():
		var bank: Dictionary = _water_banks[i]
		var rect: Rect2i = bank["rect"]
		if bank["drained_layers"] >= rect.size.y:
			continue
		if bank.get("is_acid", false):
			continue
		if _is_root_touching_bank(bank):
			continue
		candidates.append(i)

	if candidates.is_empty():
		return

	# Shuffle candidates and turn 1-2 unconnected water sources into unusable dark-turquoise acid pools
	var num_to_turn := mini(candidates.size(), _wind_rng.randi_range(1, 2))
	for n in num_to_turn:
		var pick_idx := _wind_rng.randi_range(0, candidates.size() - 1)
		var bank_idx: int = candidates[pick_idx]
		candidates.remove_at(pick_idx)
		_water_banks[bank_idx]["is_acid"] = true


func _init_acid_rain_drops() -> void:
	_acid_rain_drops.clear()
	var size := get_viewport_rect().size
	var mid := maxf(size.y * 0.5, 200.0)
	for i in 48:
		var drop := {
			"x": 0.0,
			"y": 0.0,
			"cloud": 0,
			"ox": 0.0,
			"len": _wind_rng.randf_range(10.0, 20.0),
			"speed": _wind_rng.randf_range(260.0, 380.0),
			"alpha": _wind_rng.randf_range(0.35, 0.7)
		}
		_respawn_rain_drop(drop, size, mid, true)
		_acid_rain_drops.append(drop)


func _get_cloud_width_px() -> float:
	return float(CLOUD_SHAPE_A[0].length()) * TILE_SIZE


func _get_cloud_left(idx: int, width: float) -> float:
	# Clouds drift slowly to the right and wrap around the screen
	var cw := _get_cloud_width_px()
	var span := maxf(width, 400.0) + cw
	return fposmod(CLOUD_FX[idx] * span + _cloud_drift, span) - cw


func _get_cloud_bottom(idx: int, mid: float) -> float:
	var shape: Array = CLOUD_SHAPE_A if idx % 2 == 0 else CLOUD_SHAPE_B
	return CLOUD_TOP_FRAC[idx] * mid + float(shape.size()) * TILE_SIZE


func _respawn_rain_drop(drop: Dictionary, size: Vector2, mid: float, scatter: bool) -> void:
	# Rain always starts at the underside of one of the clouds
	var idx := _wind_rng.randi_range(0, CLOUD_FX.size() - 1)
	var cw := _get_cloud_width_px()
	drop["cloud"] = idx
	drop["ox"] = _wind_rng.randf_range(cw * 0.15, cw * 0.85)
	var bottom := _get_cloud_bottom(idx, mid)
	drop["y"] = _wind_rng.randf_range(bottom, mid) if scatter else bottom
	drop["x"] = _get_cloud_left(idx, size.x) + drop["ox"]


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
		_refresh_roots_for_trunk()
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

	# Spawn flying leaves from canopy when wind is active (only if tree has leaves)
	if _wind_strength > 0.12 and size.x > 10.0 and _tree_health > 10.0:
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


func _is_tree_oscillating() -> bool:
	return _wind_strength > 0.05


func _update_wind(delta: float) -> bool:
	if _weather_state == WEATHER_WIND:
		_wind_state_timer -= delta
		if _wind_state_timer <= 0.0:
			_is_wind_active = not _is_wind_active
			if _is_wind_active:
				_wind_target_strength = _wind_rng.randf_range(0.75, 1.0)
				_wind_direction = -1.0 if _wind_rng.randf() < 0.5 else 1.0
				_wind_state_timer = _wind_rng.randf_range(1.8, 2.6)
			else:
				_wind_target_strength = 0.0
				_wind_state_timer = _wind_rng.randf_range(1.2, 1.8)
	else:
		_is_wind_active = false
		_wind_target_strength = 0.0

	var prev_strength := _wind_strength
	_wind_strength = move_toward(_wind_strength, _wind_target_strength, delta * 2.2)

	if _is_tree_oscillating():
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
	_init_acid_rain_drops()
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


func _get_pause_button_rects(size: Vector2, mid: float) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var btn_w := 260.0
	var btn_h := 46.0
	var lower_h := size.y - mid

	# Match the vertical margin/gap used across main menu buttons (4 buttons on the lower screen: 5 gaps)
	var main_menu_count := 4
	var total_btn_h := float(main_menu_count) * btn_h
	var margin_y := maxf(8.0, (lower_h - total_btn_h) / float(main_menu_count + 1))
	var start_x := (size.x - btn_w) * 0.5

	# Button 0 ("Continue") and Button 1 ("Main Menu") positioned with the exact main menu gap
	var count := 2
	for i in count:
		var y := mid + margin_y + float(i) * (btn_h + margin_y)
		rects.append(Rect2(Vector2(start_x, y), Vector2(btn_w, btn_h)))

	return rects


func _toggle_pause() -> void:
	_is_paused = not _is_paused
	_is_lmb_down = false
	_has_last_drag_cell = false
	_active_drag_Safe_tiles.clear()
	_active_drag_history.clear()
	_water_bar_bubbles.clear()
	_pollution_flash_time = 0.0
	_pollution_rising_tint = 0.0
	_root_sfx_timer = 0.0
	_stop_all_looping_sfx()
	_pause_hovered_btn_idx = 0
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _intro_cutscene != null or _victory_cutscene != null:
		return

	var size := get_viewport_rect().size
	var mid := size.y * 0.5
	var grow_btn_rect := _get_grow_button_rect(size, mid)

	if _is_paused:
		var pause_rects := _get_pause_button_rects(size, mid)
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				_toggle_pause()
				return
			elif event.keycode == KEY_UP or event.keycode == KEY_W:
				_pause_hovered_btn_idx = (_pause_hovered_btn_idx - 1 + 2) % 2
				queue_redraw()
				return
			elif event.keycode == KEY_DOWN or event.keycode == KEY_S:
				_pause_hovered_btn_idx = (_pause_hovered_btn_idx + 1) % 2
				queue_redraw()
				return
			elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE:
				_activate_pause_button(_pause_hovered_btn_idx)
				return

		elif event is InputEventMouseMotion:
			for i in pause_rects.size():
				if pause_rects[i].has_point(event.position):
					if _pause_hovered_btn_idx != i:
						_pause_hovered_btn_idx = i
						queue_redraw()
					break

		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			for i in pause_rects.size():
				if pause_rects[i].has_point(event.position):
					_pause_hovered_btn_idx = i
					_activate_pause_button(i)
					return
		return

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
		if event.keycode == KEY_R:
			_restart_game()
		elif event.keycode == KEY_TAB:
			# Temporary debug shortcut: immediately win and trigger victory outro cutscene
			if not _is_game_over:
				_game_timer = 0.0
				_is_game_over = true
				_is_game_won = true
				_trigger_victory()
		elif event.keycode == KEY_ESCAPE:
			if not _is_game_over:
				_toggle_pause()


func _activate_pause_button(idx: int) -> void:
	if idx == 0:
		# Continue
		_toggle_pause()
	elif idx == 1:
		# Main Menu
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


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


func _is_cell_acid_water(cell: Vector2i) -> bool:
	if not _water_bank_lookup.has(cell):
		return false
	var bank_idx: int = _water_bank_lookup[cell]
	var bank: Dictionary = _water_banks[bank_idx]
	if not bank.get("is_acid", false):
		return false
	var rect: Rect2i = bank["rect"]
	var current_top: int = rect.position.y + bank["drained_layers"]
	return cell.y >= current_top


func _is_adjacent_to_acid_water(cell: Vector2i) -> bool:
	for nr in range(-1, 2):
		for nc in range(-1, 2):
			if _is_cell_acid_water(cell + Vector2i(nc, nr)):
				return true
	return false


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
	var hit_rock := false

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
			if _rock_cells.has(interp_cell):
				hit_rock = true
			if _try_extend_root_at_cell(interp_cell):
				changed = true
	else:
		if _rock_cells.has(target_cell):
			hit_rock = true
		if _try_extend_root_at_cell(target_cell):
			changed = true

	if hit_rock and _rock_player:
		if not _rock_player.playing:
			_rock_player.play()

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
			# Acid pools cannot be connected afterwards (enforce at least 1 cell gap around acid water)
			if _is_adjacent_to_acid_water(target):
				return false
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


func _get_trunk_base_span(center_col: int) -> Vector2i:
	# Columns covered by the trunk sprite's base row (y=36), aligned so sprite x=17 sits on column center_col - 2.
	# Small trunk: x=16..22 (7 wide). Big trunk: x=14..23 (10 wide).
	if _current_trunk_rect == SPRITE_RECT_BIGROOT:
		return Vector2i(center_col - 5, center_col + 4)
	return Vector2i(center_col - 3, center_col + 3)


func _refresh_roots_for_trunk() -> void:
	# Called when the trunk sprite changes: re-shape the top of the initial roots while keeping player-grown roots
	var size := get_viewport_rect().size
	var cols := int(ceil(size.x / TILE_SIZE))
	if cols <= 10:
		return
	_build_initial_roots(cols)
	if _is_connected_to_water:
		_update_water_flow_path()


func _generate_initial_roots(cols: int) -> void:
	_root_tiles.clear()
	_build_initial_roots(cols)


func _build_initial_roots(cols: int) -> void:
	_initial_root_tiles.clear()
	var center_col := int(cols * 0.5)

	# Main stem root: top rows match the trunk base width (7 for the small trunk, 10 for the big one), then taper down
	var is_big := _current_trunk_rect == SPRITE_RECT_BIGROOT
	var top_w := 10 if is_big else 7
	var mid_w := 7 if is_big else 5
	for r in 15:
		var w := top_w if r < 2 else (mid_w if r < 4 else (4 if r < 7 else (3 if r < 12 else 2)))
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
	var attempts := 0

	while _water_banks.size() < num_sources and attempts < 500:
		attempts += 1
		var w := rng.randi_range(8, 14)
		var min_h := int(ceil(64.0 / float(w)))
		var h := rng.randi_range(min_h, min_h + 3)

		var origin_x := rng.randi_range(2, maxi(cols - w - 2, 2))
		var origin_y := rng.randi_range(16, maxi(rows - h - 2, 16))

		var rect := Rect2i(origin_x, origin_y, w, h)
		# Expand check rect by 1 cell so no two water sources overlap or touch each other
		var padded_rect := rect.grow(1)
		var overlaps := false
		for existing_bank in _water_banks:
			var existing_rect: Rect2i = existing_bank["rect"]
			if padded_rect.intersects(existing_rect):
				overlaps = true
				break
		if overlaps:
			continue

		var layer_time := float(w) * 0.4
		var bank_idx := _water_banks.size()

		_water_banks.append({
			"rect": rect,
			"drained_layers": 0,
			"drain_timer": 0.0,
			"layer_time": layer_time,
			"is_acid": false
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
	if _intro_cutscene != null or _victory_cutscene != null:
		return

	var size := get_viewport_rect().size
	var mid := size.y * 0.5
	_draw_sky(size, mid)
	_draw_hills(size, mid)
	if _acid_rain_intensity > 0.01:
		# Overcast grayish tint over the top screen during acid rain (behind the tree)
		draw_rect(Rect2(0.0, 0.0, size.x, mid), Color(0.32, 0.35, 0.37, 0.65 * _acid_rain_intensity))
	# Air pollution atmospheric tint over the top screen: scales smoothly between 0% and 20% opacity as pollution reaches 100%
	var poll_ratio := clampf(_air_pollution / MAX_AIR_POLLUTION, 0.0, 1.0)
	if poll_ratio > 0.001:
		draw_rect(Rect2(0.0, 0.0, size.x, mid), Color(0.85, 0.18, 0.18, 0.20 * poll_ratio))
	_draw_wind_gusts(mid)
	_draw_acid_clouds(size, mid)
	_draw_acid_rain(size, mid)
	_draw_tree(Vector2(size.x * 0.5, mid), mid)
	_draw_leaf_particles(mid)
	_draw_soil_grid(size, mid)
	_draw_health_bar(size)
	_draw_countdown_timer(size)
	_draw_grow_button(size, mid)
	if _is_game_over:
		_draw_game_over_overlay(size)
	elif _is_paused:
		_draw_pause_menu(size, mid)


func _draw_pause_menu(size: Vector2, mid: float) -> void:
	if not _vt323_font:
		return

	# Lower half dim overlay
	draw_rect(Rect2(0.0, mid, size.x, size.y - mid), Color(0.0, 0.0, 0.0, 0.78))

	var is_tr := false
	if GameSettings:
		is_tr = (GameSettings.language == GameSettings.Language.TR)

	var rects := _get_pause_button_rects(size, mid)
	var labels := [
		"Devam Et" if is_tr else "Continue",
		"Ana Menü" if is_tr else "Main Menu"
	]

	for i in rects.size():
		var r: Rect2 = rects[i]
		var is_focused := (i == _pause_hovered_btn_idx)

		# Drop shadow
		draw_rect(Rect2(r.position + Vector2(2.0, 3.0), r.size), Color(0.0, 0.0, 0.0, 0.65))

		# Background
		var bg_col := Color(0.22, 0.28, 0.22, 0.95) if is_focused else Color(0.12, 0.12, 0.12, 0.88)
		draw_rect(r, bg_col)

		# Border: focused button gets a crisp white thick border
		if is_focused:
			draw_rect(r, Color.WHITE, false, 2.5)
		else:
			draw_rect(r, Color(1.0, 1.0, 1.0, 0.25), false, 1.0)

		# Label
		var text_col := Color("bfe3f5") if is_focused else Color.WHITE
		var text_y := r.position.y + r.size.y * 0.5 + 8.0
		draw_string(_vt323_font, Vector2(r.position.x, text_y), labels[i], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 26, text_col)


func _draw_acid_clouds(size: Vector2, mid: float) -> void:
	if _acid_rain_intensity <= 0.02:
		return
	var a := clampf(_acid_rain_intensity, 0.0, 1.0)
	for i in CLOUD_FX.size():
		var shape: Array = CLOUD_SHAPE_A if i % 2 == 0 else CLOUD_SHAPE_B
		var left := _get_cloud_left(i, size.x)
		var top: float = CLOUD_TOP_FRAC[i] * mid
		for row in shape.size():
			var line: String = shape[row]
			var col_color: Color = CLOUD_ROW_COLORS[mini(row, CLOUD_ROW_COLORS.size() - 1)]
			col_color.a = a
			var run_start := -1
			for col in line.length() + 1:
				var filled := col < line.length() and line[col] == "#"
				if filled and run_start < 0:
					run_start = col
				elif not filled and run_start >= 0:
					draw_rect(Rect2(left + float(run_start) * TILE_SIZE, top + float(row) * TILE_SIZE, float(col - run_start) * TILE_SIZE, TILE_SIZE), col_color)
					run_start = -1


func _draw_acid_rain(size: Vector2, mid: float) -> void:
	if _acid_rain_intensity <= 0.02:
		return
	for drop in _acid_rain_drops:
		var y: float = drop["y"]
		if y >= mid or y + drop["len"] <= 0.0:
			continue
		var idx: int = drop["cloud"]
		var x: float = _get_cloud_left(idx, size.x) + drop["ox"]
		var len_y: float = drop["len"]
		var p1 := Vector2(x, maxf(0.0, y))
		var p2 := Vector2(x - 1.5, minf(mid, y + len_y))
		var alpha: float = drop["alpha"] * _acid_rain_intensity
		draw_line(p1, p2, Color("16a05d") if alpha < 0.5 else Color("2ecc71"), 1.5)


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

	var bar_pos := Vector2(HUD_BAR_X, 26.0)
	var bar_w := 200.0
	var bar_h := 18.0
	var border_w := 2.0

	var font_size := 22

	var is_tr := false
	if GameSettings:
		is_tr = (GameSettings.language == GameSettings.Language.TR)

	# Title text above the bar (offset right of the top-left corner icon)
	var tree_title := "AĞAÇ SAĞLIĞI" if is_tr else "TREE HEALTH"
	draw_string(_vt323_font, bar_pos + Vector2(12.0, -6.0), tree_title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

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
		if _wood_log_texture:
			var log_size := _wood_log_texture.get_size()
			var src_rect := Rect2(0.0, 0.0, log_size.x * hp_ratio, log_size.y)
			draw_texture_rect_region(_wood_log_texture, Rect2(bar_pos, Vector2(current_w, bar_h)), src_rect)
			# Slight red/yellow/green health tint over the filled wood bar
			draw_rect(Rect2(bar_pos, Vector2(current_w, bar_h)), Color(fill_color.r, fill_color.g, fill_color.b, 0.35))
		else:
			# Main filled bar with organic wood/growth tone
			draw_rect(Rect2(bar_pos, Vector2(current_w, bar_h)), fill_color)

			# Organic wood-grain texture lines along the health bar
			var grain_color := Color(fill_color.darkened(0.25), 0.55)
			draw_line(Vector2(bar_pos.x, bar_pos.y + 5.0), Vector2(bar_pos.x + current_w, bar_pos.y + 5.0), grain_color, 1.0)
			draw_line(Vector2(bar_pos.x, bar_pos.y + 12.0), Vector2(bar_pos.x + current_w, bar_pos.y + 12.0), grain_color, 1.0)

			# Subtle organic wood knot pattern along the bar
			var step_x := 18.0
			var k_x := bar_pos.x + 12.0
			while k_x < bar_pos.x + current_w - 4.0:
				draw_rect(Rect2(k_x, bar_pos.y + 8.0, 3.0, 2.0), grain_color)
				k_x += step_x

			# Gloss highlight line on top half of the bar
			draw_rect(Rect2(bar_pos, Vector2(current_w, bar_h * 0.35)), Color(1.0, 1.0, 1.0, 0.22))

	# Wood log borders around the health bar (same outer footprint as the other bars)
	if _wood_log_texture:
		var log_size := _wood_log_texture.get_size()
		# Top and bottom wood log borders
		draw_texture_rect(_wood_log_texture, Rect2(bar_pos.x - border_w, bar_pos.y - border_w, bar_w + border_w * 2.0, border_w), false)
		draw_texture_rect(_wood_log_texture, Rect2(bar_pos.x - border_w, bar_pos.y + bar_h, bar_w + border_w * 2.0, border_w), false)
		# Left and right wood log borders
		draw_texture_rect_region(_wood_log_texture, Rect2(bar_pos.x - border_w, bar_pos.y, border_w, bar_h), Rect2(0.0, 0.0, minf(32.0, log_size.x), log_size.y))
		draw_texture_rect_region(_wood_log_texture, Rect2(bar_pos.x + bar_w, bar_pos.y, border_w, bar_h), Rect2(maxf(0.0, log_size.x - 32.0), 0.0, minf(32.0, log_size.x), log_size.y))
	else:
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(1.0, 1.0, 1.0, 0.2), false, 1.0)

	# --- WATER BAR (right below the health bar) ---
	var water_bar_pos := Vector2(HUD_BAR_X, 68.0)

	# Title text above the water bar (offset right of the top-left corner icon)
	var water_title := "SU" if is_tr else "WATER"
	draw_string(_vt323_font, water_bar_pos + Vector2(12.0, -6.0), water_title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

	# Water amount in Liters on the right (1px water source = 1L)
	var water_str := "%dL" % int(roundf(_water_stored))
	draw_string(_vt323_font, water_bar_pos + Vector2(bar_w - 60.0, -6.0), water_str, HORIZONTAL_ALIGNMENT_RIGHT, 60.0, font_size, Color("bfe3f5"))

	# Outer border/drop shadow
	draw_rect(Rect2(water_bar_pos - Vector2(border_w, border_w), Vector2(bar_w + border_w * 2.0, bar_h + border_w * 2.0)), Color(0, 0, 0, 0.7))
	# Inner dark background
	draw_rect(Rect2(water_bar_pos, Vector2(bar_w, bar_h)), Color(0.12, 0.12, 0.12, 0.85))

	var water_ratio := clampf(_water_stored / MAX_WATER_STORED, 0.0, 1.0)
	var water_fill_w := bar_w * water_ratio
	var ghost_ratio := clampf(_water_ghost_stored / MAX_WATER_STORED, 0.0, 1.0)
	var ghost_fill_w := bar_w * ghost_ratio
	if ghost_fill_w > water_fill_w + 0.5:
		draw_rect(Rect2(water_bar_pos.x + water_fill_w, water_bar_pos.y, ghost_fill_w - water_fill_w, bar_h), Color(0.75, 0.90, 0.98, 0.55))
		draw_rect(Rect2(water_bar_pos.x + water_fill_w, water_bar_pos.y, ghost_fill_w - water_fill_w, bar_h * 0.35), Color(1.0, 1.0, 1.0, 0.3))
	if water_fill_w > 0.0:
		var water_fill_color := WATER_COLOR.lerp(Color("5dade2"), water_ratio)
		draw_rect(Rect2(water_bar_pos, Vector2(water_fill_w, bar_h)), water_fill_color)

		# Liquid undulating pixel wave on the surface layer
		var wave_step := 3.0
		var wx := 0.0
		while wx < water_fill_w:
			var wave_offset_y := sin((water_bar_pos.x + wx) * 0.15 + _hud_anim_time * 4.5) * 1.5
			var seg_w := minf(wave_step, water_fill_w - wx)
			draw_rect(Rect2(water_bar_pos.x + wx, water_bar_pos.y, seg_w, 2.0 + wave_offset_y), Color(1.0, 1.0, 1.0, 0.35))
			wx += wave_step

		# Gloss reflection band in top third
		draw_rect(Rect2(water_bar_pos + Vector2(0.0, 2.0), Vector2(water_fill_w, bar_h * 0.3)), Color(1.0, 1.0, 1.0, 0.18))

		# Rising bubbles when water is increasing
		for b in _water_bar_bubbles:
			var bx: float = water_bar_pos.x + b["rel_x"] * water_fill_w + sin(_water_pulse_time * 6.0 + b["wobble_phase"]) * 1.5
			var by: float = water_bar_pos.y + b["y"]
			var bsz: float = b["size"]
			if bx >= water_bar_pos.x and bx + bsz <= water_bar_pos.x + water_fill_w and by >= water_bar_pos.y and by + bsz <= water_bar_pos.y + bar_h:
				draw_rect(Rect2(bx, by, bsz, bsz), Color("dff5ff"))

	# Inner outline
	draw_rect(Rect2(water_bar_pos, Vector2(bar_w, bar_h)), Color(1.0, 1.0, 1.0, 0.2), false, 1.0)

	# --- AIR POLLUTION BAR (right below the water bar) ---
	var poll_bar_pos := Vector2(HUD_BAR_X, 110.0)

	# Title text above the air pollution bar (offset right of the top-left corner icon)
	var is_poll_flashing := _air_pollution > 80.0
	var flash_on := is_poll_flashing and (int(_pollution_flash_time * 7.0) % 2 == 1)
	var poll_title := "HAVA KİRLİLİĞİ" if is_tr else "AIR POLLUTION"
	draw_string(_vt323_font, poll_bar_pos + Vector2(12.0, -6.0), poll_title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

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
		# Fill the pollution bar directly with a continuous two-tone pixel-art smoke plume that rises upward
		# (light smoke #d7d7d7 with swirling #b5b5b5 inner patches rising from bottom to top)
		var px_size := 2.0
		var rows := int(bar_h / px_size) # 9 pixel rows
		var max_cols := int(ceil(poll_fill_w / px_size))
		var base_light := Color("d7d7d7").lerp(Color("e6b8b8"), _pollution_rising_tint)
		var base_shade := Color("b5b5b5").lerp(Color("c99393"), _pollution_rising_tint)
		var smoke_light := Color("ff8a8a") if flash_on else base_light
		var smoke_shade := Color("d93838") if flash_on else base_shade
		var rise_shift := _hud_anim_time * 6.5
		var right_shift := _hud_anim_time * 8.0

		for ry in rows:
			var sy_f := float(ry) + rise_shift
			# Shape the leading front edge at poll_fill_w with an upward-traveling billow wave
			var base_taper := -absi(ry - 4) / 2
			var upward_billow := int(roundf(sin(sy_f * 0.85) * 1.5 + cos(sy_f * 0.45 + 1.1) * 1.0))
			var row_front_offset := clampi(base_taper + upward_billow - 1, -5, 0)
			var row_end_col := maxi(1, max_cols + row_front_offset)

			for rx in row_end_col:
				var sx_f := float(rx) - right_shift + sin(sy_f * 0.55) * 1.2
				# Subtle billowing puffs rising and drifting right along the top/bottom edges
				if ry == 0:
					var top_puff := sin((float(rx) - right_shift) * 0.65) + cos((float(rx) - right_shift) * 0.33 + 1.2)
					if top_puff < -0.55:
						continue
				elif ry == rows - 1:
					var bot_puff := cos((float(rx) - right_shift) * 0.60 + 0.8)
					if bot_puff < -0.75:
						continue

				# Two-tone pixel-art smoke shading rising upward and moving right through the bar
				var is_rim := (ry == 0) or (rx >= row_end_col - 2 and ry <= 5)
				var swirl := sin(sy_f * 0.85 + sin(sx_f * 0.45) * 1.6) + cos(sx_f * 0.52 + sy_f * 0.55)
				var is_shaded := (not is_rim) and (swirl > 0.12 or ry == rows - 1)
				var col := smoke_shade if is_shaded else smoke_light

				var draw_x := poll_bar_pos.x + float(rx) * px_size
				var draw_w := minf(px_size, poll_bar_pos.x + bar_w - draw_x)
				if draw_w > 0.0:
					draw_rect(Rect2(draw_x, poll_bar_pos.y + float(ry) * px_size, draw_w, px_size), col)

		# Small detached smoke wisps rising upward and drifting right near the billowing front edge
		if max_cols >= 6 and poll_fill_w < bar_w - 6.0:
			for wi in 2:
				var cycle := fmod(_hud_anim_time * 4.5 + float(wi) * 3.5, 7.0)
				var wisp_row := rows - 2 - int(cycle)
				if wisp_row >= 0 and wisp_row <= rows - 2:
					var wisp_col := max_cols - 4 + int(cycle * 0.6) + (wi % 2)
					var wisp_x := poll_bar_pos.x + float(wisp_col) * px_size
					var wisp_y := poll_bar_pos.y + float(wisp_row) * px_size
					if wisp_x + px_size * 2.0 <= poll_bar_pos.x + bar_w:
						draw_rect(Rect2(wisp_x, wisp_y, px_size * 2.0, px_size), smoke_light)
						if wisp_row + 1 < rows:
							draw_rect(Rect2(wisp_x + px_size, wisp_y + px_size, px_size, px_size), smoke_shade)

	# Inner outline (alert border when flashing)
	var poll_outline_col := Color("ff5252") if flash_on else Color(1.0, 1.0, 1.0, 0.2)
	draw_rect(Rect2(poll_bar_pos, Vector2(bar_w, bar_h)), poll_outline_col, false, 1.5 if flash_on else 1.0)


	# Icons perched on the top-left corner of each bar (matching the recovery bar layout)
	_draw_hud_icon(HUD_ICON_HEART, HUD_ICON_HEART_COLORS, bar_pos)
	_draw_hud_icon(HUD_ICON_DROP, HUD_ICON_DROP_COLORS, water_bar_pos)
	_draw_hud_icon(HUD_ICON_SMOKE, HUD_ICON_SMOKE_COLORS, poll_bar_pos)


func _draw_hud_icon(pattern: Array, colors: Dictionary, bar_top_left: Vector2) -> void:
	# Draws a pixel-art icon perched on the top-left corner of the bar, matching the recovery bar sprout
	var px := HUD_ICON_PIXEL
	var h := float(pattern.size()) * px
	var left := bar_top_left.x - 6.0
	var top := bar_top_left.y - h + 2.0
	for row in pattern.size():
		var line: String = pattern[row]
		for col in line.length():
			var ch := line[col]
			if ch == ".":
				continue
			draw_rect(Rect2(left + float(col) * px, top + float(row) * px, px, px), colors[ch])


func _draw_grow_button(size: Vector2, mid: float) -> void:
	if not _vt323_font:
		return

	var btn_rect := _get_grow_button_rect(size, mid)
	var can_grow := _water_stored > 50.0

	var is_tr := false
	if GameSettings:
		is_tr = (GameSettings.language == GameSettings.Language.TR)

	# Calculate spring bounce scale when pressed:
	# dampens smoothly from a squash to stretch and settles back to 1.0
	var spring_scale := 1.0
	if _grow_btn_spring_time > 0.0:
		var progress := 1.0 - (_grow_btn_spring_time / 0.45) # 0.0 -> 1.0
		var damp := exp(-progress * 4.5)
		spring_scale = 1.0 - sin(progress * TAU * 2.0) * 0.28 * damp

	var current_scale := _grow_btn_hover_scale * spring_scale
	var btn_center := btn_rect.position + btn_rect.size * 0.5

	if _leaf_btn_texture:
		var src_rect := Rect2(125.0, 78.0, 252.0, 362.0) # tight leaf bounding box
		var leaf_aspect := src_rect.size.x / src_rect.size.y # ~0.696
		# Fit the leaf inside btn_rect maintaining aspect ratio and applied scale
		var base_leaf_h := btn_rect.size.y
		var leaf_h := base_leaf_h * current_scale
		var leaf_w := leaf_h * leaf_aspect
		var leaf_pos := Vector2(btn_center.x - leaf_w * 0.5, btn_center.y - leaf_h * 0.5)
		var leaf_rect := Rect2(leaf_pos, Vector2(leaf_w, leaf_h))

		# Drop shadow
		draw_texture_rect_region(_leaf_btn_texture, Rect2(leaf_pos + Vector2(2.0, 3.0), Vector2(leaf_w, leaf_h)), src_rect, Color(0.0, 0.0, 0.0, 0.65))

		# Modulate tint: vibrant green when ready, slightly brightened when hovered, darkened gray when not ready
		var leaf_mod: Color
		if not can_grow:
			leaf_mod = Color(0.45, 0.45, 0.45, 0.65)
		elif _is_grow_btn_hovered:
			leaf_mod = Color(1.2, 1.2, 1.2, 1.0)
		else:
			leaf_mod = Color(1.0, 1.0, 1.0, 1.0)
		draw_texture_rect_region(_leaf_btn_texture, leaf_rect, src_rect, leaf_mod)

		# Text overlay on the leaf button (centered around btn_center)
		var text_col := Color.WHITE if can_grow else Color(0.75, 0.75, 0.75, 0.85)
		var shadow_col := Color(0.0, 0.0, 0.0, 0.85)
		var grow_l1 := "AĞACI" if is_tr else "GROW"
		var grow_l2 := "BÜYÜT" if is_tr else "TREE"
		# Text with shadow for legibility over the leaf
		draw_string(_vt323_font, btn_center + Vector2(-btn_rect.size.x * 0.5 + 1.0, -12.0), grow_l1, HORIZONTAL_ALIGNMENT_CENTER, btn_rect.size.x, 22, shadow_col)
		draw_string(_vt323_font, btn_center + Vector2(-btn_rect.size.x * 0.5, -13.0), grow_l1, HORIZONTAL_ALIGNMENT_CENTER, btn_rect.size.x, 22, text_col)

		draw_string(_vt323_font, btn_center + Vector2(-btn_rect.size.x * 0.5 + 1.0, 10.0), grow_l2, HORIZONTAL_ALIGNMENT_CENTER, btn_rect.size.x, 22, shadow_col)
		draw_string(_vt323_font, btn_center + Vector2(-btn_rect.size.x * 0.5, 9.0), grow_l2, HORIZONTAL_ALIGNMENT_CENTER, btn_rect.size.x, 22, text_col)

		var cost_col := Color("bfe3f5") if can_grow else text_col
		draw_string(_vt323_font, btn_center + Vector2(-btn_rect.size.x * 0.5 + 1.0, 31.0), "(50L)", HORIZONTAL_ALIGNMENT_CENTER, btn_rect.size.x, 18, shadow_col)
		draw_string(_vt323_font, btn_center + Vector2(-btn_rect.size.x * 0.5, 30.0), "(50L)", HORIZONTAL_ALIGNMENT_CENTER, btn_rect.size.x, 18, cost_col)

		# Draw falling tiny leaf particles from pressing
		_draw_grow_leaf_particles(mid)
		return

	var border_w := 2.0

	# Drop shadow / outer border
	draw_rect(
		Rect2(btn_rect.position - Vector2(border_w, border_w), btn_rect.size + Vector2(border_w * 2.0, border_w * 2.0)),
		Color(0.0, 0.0, 0.0, 0.75)
	)

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

	var text_col := Color.WHITE if can_grow else Color(0.7, 0.7, 0.7, 0.85)
	var grow_l1 := "AĞACI" if is_tr else "GROW"
	var grow_l2 := "BÜYÜT" if is_tr else "TREE"
	draw_string(_vt323_font, btn_rect.position + Vector2(0.0, 28.0), grow_l1, HORIZONTAL_ALIGNMENT_CENTER, btn_rect.size.x, 22, text_col)
	draw_string(_vt323_font, btn_rect.position + Vector2(0.0, 50.0), grow_l2, HORIZONTAL_ALIGNMENT_CENTER, btn_rect.size.x, 22, text_col)
	draw_string(_vt323_font, btn_rect.position + Vector2(0.0, 72.0), "(50L)", HORIZONTAL_ALIGNMENT_CENTER, btn_rect.size.x, 18, Color("bfe3f5") if can_grow else text_col)

	_draw_grow_leaf_particles(mid)


func _draw_grow_leaf_particles(mid: float) -> void:
	for p in _grow_btn_leaf_particles:
		var pos: Vector2 = p["pos"]
		if pos.y >= mid:
			continue
		var progress: float = p["age"] / p["max_age"]
		var fade := clampf((1.0 - progress) / 0.3, 0.0, 1.0)
		var col: Color = p["color"]
		col.a = fade
		var sz: float = p["size"]
		# Draw cute 2x2 / 3x3 pixel leaf flake with darker outline pixel
		draw_rect(Rect2(pos.x, pos.y, sz, sz), col)
		draw_rect(Rect2(pos.x + 1.0, pos.y - 1.0, sz * 0.5, sz * 0.5), Color("33691e", fade))


func _draw_countdown_timer(size: Vector2) -> void:
	if not _vt323_font:
		return

	var bar_w := 240.0
	var bar_h := 18.0
	var border_w := 2.0
	var bar_pos := Vector2(size.x - bar_w - 20.0, 26.0)
	var font_size := 22

	var is_tr := false
	if GameSettings:
		is_tr = (GameSettings.language == GameSettings.Language.TR)

	# Progress from 0% to 100% over 60 seconds (GAME_DURATION)
	var recover_ratio := clampf((GAME_DURATION - _game_timer) / GAME_DURATION, 0.0, 1.0)
	var pct_str := "%d%%" % int(roundf(recover_ratio * 100.0))

	# Outer border/drop shadow
	draw_rect(Rect2(bar_pos - Vector2(border_w, border_w), Vector2(bar_w + border_w * 2.0, bar_h + border_w * 2.0)), Color("2a3b1c"))
	# Inner dark background
	draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.12, 0.12, 0.12, 0.85))

	var fill_w := bar_w * recover_ratio

	# Back half of the spiral ivy vine (curves behind the bar where sin(theta) < 0)
	_draw_recovery_spiral_ivy(bar_pos, bar_w, bar_h, recover_ratio, false)

	if fill_w > 0.0:
		if _recovery_fill_texture:
			var rec_size := _recovery_fill_texture.get_size()
			# Fit the full image height into the bar's height maintaining true aspect ratio, tiling horizontally as needed
			var tile_scale := bar_h / rec_size.y
			var tile_w := rec_size.x * tile_scale
			var drawn_w := 0.0
			while drawn_w < fill_w:
				var piece_w := minf(tile_w, fill_w - drawn_w)
				var src_piece_w := (piece_w / tile_w) * rec_size.x
				var dst_rect := Rect2(bar_pos.x + drawn_w, bar_pos.y, piece_w, bar_h)
				var src_rect := Rect2(0.0, 0.0, src_piece_w, rec_size.y)
				draw_texture_rect_region(_recovery_fill_texture, dst_rect, src_rect)
				drawn_w += piece_w
		else:
			var fill_col := Color("3e6537").lerp(Color("55824b"), recover_ratio)
			draw_rect(Rect2(bar_pos, Vector2(fill_w, bar_h)), fill_col)
			# Top highlight
			draw_rect(Rect2(bar_pos, Vector2(fill_w, bar_h * 0.3)), Color(1.0, 1.0, 1.0, 0.16))

	# Inner outline
	draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color("2a3b1c"), false, 1.5)

	# Front half of the spiral ivy vine (wraps across the front of the bar where sin(theta) >= 0)
	_draw_recovery_spiral_ivy(bar_pos, bar_w, bar_h, recover_ratio, true)

	# Pixel-art double-leaf sprout perched on the top-left corner of the recovery bar
	var sprout_px := 1.5
	var sprout_origin := Vector2(bar_pos.x - 4.0, bar_pos.y - float(RECOVERY_SPROUT_LEAVES.size()) * sprout_px + 2.0)
	for row in RECOVERY_SPROUT_LEAVES.size():
		var line: String = RECOVERY_SPROUT_LEAVES[row]
		for col in line.length():
			var ch := line[col]
			if ch == ".":
				continue
			draw_rect(Rect2(sprout_origin.x + float(col) * sprout_px, sprout_origin.y + float(row) * sprout_px, sprout_px, sprout_px), RECOVERY_SPROUT_COLORS[ch])

	# Title and percentage text above the bar (offset right of the top-left leaves)
	var title := "DOĞANIN İYİLEŞMESİ" if is_tr else "NATURE RECOVERY"
	draw_string(_vt323_font, bar_pos + Vector2(22.0, -6.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
	draw_string(_vt323_font, bar_pos + Vector2(bar_w - 46.0, -6.0), pct_str, HORIZONTAL_ALIGNMENT_RIGHT, 46.0, font_size, Color("c8e6c9"))


func _draw_recovery_spiral_ivy(bar_pos: Vector2, bar_w: float, bar_h: float, recover_ratio: float, front_pass: bool) -> void:
	if recover_ratio <= 0.005:
		return

	var px := 2.0 # Constant size of 1 small pixel square
	var total_cols := int(bar_w / px)
	var max_col := int(roundf(float(total_cols) * recover_ratio))
	if max_col <= 0:
		return

	var turns := 4.5 # Number of spiral loops along the full bar
	var amp_rows := 5.0
	var center_row := int(roundf((bar_h * 0.5) / px))
	var outline_col := Color("2a3b1c")
	var stem_col := Color("476e3f") if front_pass else Color("33522c")
	var leaf_fill := Color("59874f") if front_pass else Color("3d6135")

	# Pixel grid: Vector2i(col, row) -> Color (every pixel is drawn as exactly 1 small px x px square)
	var grid: Dictionary = {}

	var prev_row := 0
	var has_prev := false
	for col in max_col:
		var theta := (float(col) / float(total_cols)) * turns * TAU
		var is_front := sin(theta) >= 0.0
		var row := center_row - int(roundf(cos(theta) * amp_rows))
		if is_front == front_pass:
			if has_prev and absi(row - prev_row) > 1:
				var step_r := 1 if row > prev_row else -1
				var r := prev_row + step_r
				while r != row:
					grid[Vector2i(col, r)] = stem_col
					grid[Vector2i(col, r - 1)] = outline_col
					grid[Vector2i(col, r + 1)] = outline_col
					r += step_r
			grid[Vector2i(col, row)] = stem_col
			if not grid.has(Vector2i(col, row - 1)):
				grid[Vector2i(col, row - 1)] = outline_col
			if not grid.has(Vector2i(col, row + 1)):
				grid[Vector2i(col, row + 1)] = outline_col
			has_prev = true
			prev_row = row
		else:
			has_prev = false

	# Small pixel-art ivy leaves along the spiral vine (also strictly 1x1 grid squares)
	var leaf_step := 7
	var lc := 5
	var leaf_idx := 0
	while lc < max_col - 1:
		var theta := (float(lc) / float(total_cols)) * turns * TAU
		var is_front := sin(theta) >= 0.0
		if is_front == front_pass:
			var base_r := center_row - int(roundf(cos(theta) * amp_rows))
			var dir_r := -1 if (leaf_idx % 2 == 0) else 1
			var lr := base_r + dir_r * 2
			var leaf_cells := [
				Vector2i(lc, lr),
				Vector2i(lc + 1, lr),
				Vector2i(lc + 1, lr + dir_r),
			]
			for cell in leaf_cells:
				grid[cell] = leaf_fill
				for off in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
					var nb: Vector2i = cell + off
					if not grid.has(nb):
						grid[nb] = outline_col
		lc += leaf_step
		leaf_idx += 1

	for cell in grid.keys():
		var c: Vector2i = cell
		draw_rect(Rect2(bar_pos.x + float(c.x) * px, bar_pos.y + float(c.y) * px, px, px), grid[c])


func _draw_game_over_overlay(size: Vector2) -> void:
	if not _vt323_font:
		return

	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.72))

	var is_tr := false
	if GameSettings:
		is_tr = (GameSettings.language == GameSettings.Language.TR)

	var center_y := size.y * 0.45
	var title_text := ""
	if _is_game_won:
		title_text = "KAZANDINIZ" if is_tr else "YOU WIN"
	else:
		title_text = "OYUN BİTTİ" if is_tr else "GAME OVER"
	var title_col := Color("4caf50") if _is_game_won else Color("ff5252")

	draw_string(_vt323_font, Vector2(0.0, center_y), title_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 72, title_col)
	draw_string(_vt323_font, Vector2(0.0, center_y + 45.0), _game_over_reason, HORIZONTAL_ALIGNMENT_CENTER, size.x, 32, Color.WHITE)
	var restart_msg := "YENİDEN BAŞLATMAK İÇİN TIKLAYIN VEYA R'YE BASIN" if is_tr else "CLICK OR PRESS R TO RESTART"
	draw_string(_vt323_font, Vector2(0.0, center_y + 90.0), restart_msg, HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, Color("bfe3f5"))


func _draw_sky(size: Vector2, mid: float) -> void:
	# Tint sky/air to a vibrant orange/yellow color at 50% opacity during heatwaves, or overcast gray during acid rain
	var top_col := SKY_TOP.lerp(SKY_HEAT_TOP, _heatwave_intensity * 0.5).lerp(SKY_ACID_TOP, _acid_rain_intensity * 0.85)
	var hor_col := SKY_HORIZON.lerp(SKY_HEAT_HORIZON, _heatwave_intensity * 0.5).lerp(SKY_ACID_HORIZON, _acid_rain_intensity * 0.85)
	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, mid), Vector2(0, mid)]),
		PackedColorArray([top_col, top_col, hor_col, hor_col])
	)
	var sun_pos := Vector2(size.x * 0.82, mid * 0.25)
	var base_r := mid * 0.1
	# Scale sun up to 1.2x and tint slightly orange during heatwave, or dim into gray clouds during acid rain
	var r := base_r * lerpf(1.0, 1.2, _heatwave_intensity)
	var sun_col := SUN.lerp(SUN_HEAT_COLOR, _heatwave_intensity).lerp(Color("9aa2a6"), _acid_rain_intensity * 0.75)
	var sun_alpha := lerpf(1.0, 0.35, _acid_rain_intensity)
	draw_circle(sun_pos, r * 1.5, Color(sun_col, 0.25 * sun_alpha))
	draw_circle(sun_pos, r, Color(sun_col, sun_alpha))


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
	var sway_px := 0.0
	if _is_tree_oscillating():
		sway_px = (sin(_wind_time * WIND_SWAY_FREQ) * WIND_MAX_SWAY_PX + _wind_direction * 0.6) * _wind_strength
	var base_oscillation_x := sway_px * tree_pixel_scale
	var leaf_offset_x := base_oscillation_x * 0.75 * 0.66

	# Constant warm orange tint during heatwave (0.225 opacity), or 50% of the gray tint on the tree during acid rain
	var heat_alpha := clampf(_heatwave_intensity, 0.0, 1.0) * 0.225
	var acid_alpha := clampf(_acid_rain_intensity, 0.0, 1.0) * (0.65 * 0.5)
	var flash_alpha := maxf(heat_alpha, acid_alpha)
	var flash_col := Color(1.0, 0.55, 0.15) if heat_alpha >= acid_alpha else Color(0.32, 0.35, 0.37)

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
			if flash_alpha > 0.001 and _tree_white_texture:
				draw_texture_rect_region(_tree_white_texture, dst_row_rect, prev_src_row, Color(flash_col.r, flash_col.g, flash_col.b, (1.0 - trunk_t) * flash_alpha))

		var cur_src_row := Rect2(_current_trunk_rect.position.x, _current_trunk_rect.position.y + row_y, SPRITE_SIZE, 1.0)
		draw_texture_rect_region(_tree_texture, dst_row_rect, cur_src_row, Color(1.0, 1.0, 1.0, trunk_t))
		if flash_alpha > 0.001 and _tree_white_texture:
			draw_texture_rect_region(_tree_white_texture, dst_row_rect, cur_src_row, Color(flash_col.r, flash_col.g, flash_col.b, trunk_t * flash_alpha))

	# Draw leaves on top with smooth cross-dissolve and interpolated vertical offset
	var leaf_t := smoothstep(0.0, 1.0, _leaf_dissolve_t)
	if leaf_t < 1.0 and _prev_leaf_rect.size.x > 0.0:
		var prev_offset_y := _prev_leaf_offset_px * tree_pixel_scale
		var prev_leaf_dest := Rect2(dest_pos + Vector2(leaf_offset_x, -prev_offset_y), scaled_size)
		draw_texture_rect_region(_tree_texture, prev_leaf_dest, _prev_leaf_rect, Color(1.0, 1.0, 1.0, 1.0 - leaf_t))
		if flash_alpha > 0.001 and _tree_white_texture:
			draw_texture_rect_region(_tree_white_texture, prev_leaf_dest, _prev_leaf_rect, Color(flash_col.r, flash_col.g, flash_col.b, (1.0 - leaf_t) * flash_alpha))

	if _current_leaf_rect.size.x > 0.0:
		var cur_offset_y := _current_leaf_offset_px * tree_pixel_scale
		var cur_leaf_dest := Rect2(dest_pos + Vector2(leaf_offset_x, -cur_offset_y), scaled_size)
		draw_texture_rect_region(_tree_texture, cur_leaf_dest, _current_leaf_rect, Color(1.0, 1.0, 1.0, leaf_t))
		if flash_alpha > 0.001 and _tree_white_texture:
			draw_texture_rect_region(_tree_white_texture, cur_leaf_dest, _current_leaf_rect, Color(flash_col.r, flash_col.g, flash_col.b, leaf_t * flash_alpha))


func _draw_tree_procedural(base: Vector2, mid: float) -> void:
	var h := mid * 0.6
	var w := h * 0.1
	var heat_alpha := clampf(_heatwave_intensity, 0.0, 1.0) * 0.21
	var acid_alpha := clampf(_acid_rain_intensity, 0.0, 1.0) * (0.65 * 0.5)
	var flash_t := maxf(heat_alpha, acid_alpha)
	var heat_col := Color(1.0, 0.55, 0.15) if heat_alpha >= acid_alpha else Color(0.32, 0.35, 0.37)
	# Trunk (slightly tapered)
	draw_colored_polygon(PackedVector2Array([
		base + Vector2(-w * 0.7, 0), base + Vector2(w * 0.7, 0),
		base + Vector2(w * 0.4, -h * 0.6), base + Vector2(-w * 0.4, -h * 0.6),
	]), TRUNK.lerp(heat_col, flash_t))
	# Canopy: layered circles for depth
	var c := base + Vector2(0, -h * 0.72)
	var r := h * 0.22
	for o in [Vector2(-1.1, 0.4), Vector2(1.1, 0.4), Vector2(0, 0.6)]:
		draw_circle(c + o * r, r, LEAVES_DARK.lerp(heat_col, flash_t))
	for o in [Vector2(-0.7, -0.3), Vector2(0.7, -0.3), Vector2(0, -0.9), Vector2(0, 0.1)]:
		draw_circle(c + o * r, r, LEAVES.lerp(heat_col, flash_t))
	draw_circle(c + Vector2(-0.3, -0.8) * r, r * 0.5, LEAVES_LIGHT.lerp(heat_col, flash_t))


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


			# 3. Water overlay with top-to-bottom pixel fade/shrink
			if _water_bank_lookup.has(cell):
				var bank_idx: int = _water_bank_lookup[cell]
				var bank: Dictionary = _water_banks[bank_idx]
				var rect: Rect2i = bank["rect"]
				var current_top_layer: int = rect.position.y + bank["drained_layers"]
				var is_acid: bool = bank.get("is_acid", false)
				var fill_col := ACID_WATER_COLOR if is_acid else WATER_COLOR
				var edge_col := ACID_WATER_EDGE if is_acid else WATER_EDGE

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
						draw_rect(water_subrect, fill_col)
				else:
					# Untouched water layers below
					draw_rect(tile_rect, fill_col)

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
		var span := _get_trunk_base_span(center_col)
		return c.x >= span.x and c.x <= span.y
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

	var trunk_span := _get_trunk_base_span(center_col)
	for cx in range(trunk_span.x, trunk_span.y + 1):
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
