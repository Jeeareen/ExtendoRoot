extends Node2D
## Dedicated animated pixel-art cinematic victory cutscene for ExtendoRoot.
## Features:
## - The surviving tree flourishes into full bloom and releases glowing seeds into the breeze.
## - Glowing seeds land on bare empty ground (NOT on the burnt stumps).
## - Fresh green sprouts emerge and grow into young flourishing trees.
## - The scorched landscape and sky heal back to vibrant sunny nature.
## - The family returns with deep remorse; the child runs to the tree and hugs the trunk.
## - Powerful educational message on forest fire prevention and campfire safety.
## - Touching closing narrative: "The forest breathes again... thanks to you."
## - Press SPACE to skip anytime or to proceed at the end.

signal finished
signal replay_requested

enum Phase {
	BLOOM_AND_SEEDS,     # 0.0s - 4.5s: Main tree blooms; glowing seeds lift into the breeze
	SPROUTING,           # 4.5s - 8.5s: Seeds land on empty soil; young trees grow; nature heals
	FAMILY_RETURN,       # 8.5s - 13.5s: Family returns; child hugs the tree; remorse & educational message
	EPILOGUE,            # 13.5s - 17.5s: "The forest breathes again... thanks to you."
	READY                # 17.5s+: Interactive prompt to continue/replay
}

const TILE_SIZE := 8.0
const SPRITE_SIZE := 40
const SPRITE_RECT_SMALLROOT := Rect2(0, 0, 40, 40)
const SPRITE_RECT_BIGROOT := Rect2(40, 0, 40, 40)
const SPRITE_RECT_MIDLEAVES := Rect2(80, 0, 40, 40)
const SPRITE_RECT_LARGELEAVES := Rect2(0, 40, 40, 40)
const SPRITE_RECT_SMALLLEAVES := Rect2(40, 40, 40, 40)

const SKY_TOP_HEALED := Color("4a90d9")
const SKY_HORIZON_HEALED := Color("bfe3f5")
const SUN_COLOR := Color("fff2a8")
const HILL_FAR_HEALED := Color("7fae6a")
const HILL_NEAR_HEALED := Color("5e9a4c")
const GRASS_HEALED := Color("4f8a3c")

var _tree_texture: Texture2D = null
var _vt323_font: Font = null
var _rng := RandomNumberGenerator.new()

var _timer: float = 0.0
var _phase: Phase = Phase.BLOOM_AND_SEEDS
var _wind_time: float = 0.0

# Visual particles
var _ambient_spores: Array = []
var _target_seeds: Array = []
var _sparkles: Array = []
var _hearts: Array = []
var _flowers: Array = []
var _sprout_points: Array = []

var _initialized_points: bool = false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.randomize()
	if ResourceLoader.exists("res://assets/tree.png"):
		_tree_texture = preload("res://scripts/tree_sprite.gd").get_shaded_texture()
	if ResourceLoader.exists("res://assets/VT323-Regular.ttf"):
		_vt323_font = load("res://assets/VT323-Regular.ttf")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			if get_viewport():
				get_viewport().set_input_as_handled()
			_complete()
		elif event.keycode == KEY_ESCAPE:
			var mode := DisplayServer.window_get_mode()
			if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			if get_viewport():
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _phase == Phase.READY:
			if get_viewport():
				get_viewport().set_input_as_handled()
			_complete()


var _is_completing: bool = false


func _complete() -> void:
	if _is_completing:
		return
	_is_completing = true
	finished.emit()


func _process(delta: float) -> void:
	_timer += delta
	_wind_time += delta

	var size := get_viewport_rect().size
	var mid := size.y * 0.5

	if not _initialized_points and size.x > 0.0:
		_setup_points(size)

	# Phase sequence
	if _timer < 4.5:
		_phase = Phase.BLOOM_AND_SEEDS
	elif _timer < 5.0:
		_phase = Phase.SPROUTING
	elif _timer < 14.0:
		_phase = Phase.FAMILY_RETURN
	elif _timer < 18.5:
		_phase = Phase.EPILOGUE
	else:
		_phase = Phase.READY

	_update_sim(delta, size, mid)
	queue_redraw()


func _setup_points(size: Vector2) -> void:
	_initialized_points = true

	# Fresh green trees at spread-out forest locations (in place of the old burnt trees):
	_sprout_points = [
		{"x": size.x * 0.14, "grow": 0.0, "scale": 0.85, "leaf_rect": SPRITE_RECT_MIDLEAVES, "landed": false},
		{"x": size.x * 0.28, "grow": 0.0, "scale": 1.05, "leaf_rect": SPRITE_RECT_MIDLEAVES, "landed": false},
		{"x": size.x * 0.72, "grow": 0.0, "scale": 1.05, "leaf_rect": SPRITE_RECT_MIDLEAVES, "landed": false},
		{"x": size.x * 0.86, "grow": 0.0, "scale": 0.85, "leaf_rect": SPRITE_RECT_MIDLEAVES, "landed": false}
	]

	# Pre-generate meadow wildflowers that bloom when grass heals
	_flowers.clear()
	for i in 28:
		var fx := _rng.randf_range(16.0, size.x - 16.0)
		var f_col: Color
		var c_choice := _rng.randf()
		if c_choice < 0.35:
			f_col = Color("ffd54f") # Yellow buttercup
		elif c_choice < 0.7:
			f_col = Color("ef5350") # Red poppy
		else:
			f_col = Color("ffffff") # White daisy
		_flowers.append({
			"x": fx,
			"y_off": _rng.randf_range(1.0, 7.0),
			"color": f_col,
			"size": _rng.randf_range(2.0, 3.5)
		})

	# Life seeds launched from center tree canopy toward the 4 bare ground spots
	_target_seeds.clear()
	var center_x := size.x * 0.5
	for i in _sprout_points.size():
		var pt: Dictionary = _sprout_points[i]
		_target_seeds.append({
			"start": Vector2(center_x + _rng.randf_range(-18.0, 18.0), size.y * 0.5 - 90.0),
			"target": Vector2(pt["x"], size.y * 0.5),
			"arc_height": _rng.randf_range(45.0, 75.0),
			"start_time": 1.2 + float(i) * 0.45,
			"flight_duration": 2.2,
			"index": i,
			"landed": false
		})


func _update_sim(delta: float, size: Vector2, mid: float) -> void:
	var center_x := size.x * 0.5

	# 1. Update target life seeds (1.2s - 5.5s)
	for s in _target_seeds:
		if _timer >= s["start_time"] and not s["landed"]:
			var t: float = (_timer - s["start_time"]) / s["flight_duration"]
			if t >= 1.0:
				s["landed"] = true
				var idx: int = s["index"]
				_sprout_points[idx]["landed"] = true
				# Landing sparkle burst!
				for k in 12:
					_sparkles.append({
						"pos": Vector2(s["target"].x, mid - 2.0),
						"vel": Vector2(_rng.randf_range(-26.0, 26.0), _rng.randf_range(-14.0, -42.0)),
						"color": Color("a5d6a7") if _rng.randf() < 0.5 else Color("fff59d"),
						"size": _rng.randf_range(2.0, 4.0),
						"age": 0.0,
						"max_age": _rng.randf_range(0.4, 0.8)
					})
			else:
				# Emit trail sparkles along trajectory
				if _rng.randf() < delta * 18.0:
					var cur_pos := _get_seed_pos(s, t)
					_sparkles.append({
						"pos": cur_pos,
						"vel": Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-4.0, 10.0)),
						"color": Color("fff9c4"),
						"size": _rng.randf_range(1.5, 3.0),
						"age": 0.0,
						"max_age": _rng.randf_range(0.3, 0.6)
					})

	# 2. Grow young trees once their seed has landed
	for pt in _sprout_points:
		if pt["landed"]:
			pt["grow"] = clampf(pt["grow"] + delta * 0.42, 0.0, 1.0)

	# 3. Ambient small yellow circular seeds/spores scattering from tree canopy (STOPS after trees are planted/grown!)
	if _timer >= 0.8 and _timer < 4.5:
		if _rng.randf() < delta * 14.0:
			var start_x := center_x + _rng.randf_range(-45.0, 45.0)
			var start_y := mid - _rng.randf_range(60.0, 110.0)
			_ambient_spores.append({
				"pos": Vector2(start_x, start_y),
				"vel": Vector2(_rng.randf_range(-20.0, 32.0), _rng.randf_range(20.0, 50.0)),
				"color": Color("fff59d") if _rng.randf() < 0.7 else Color("ffd54f"),
				"radius": _rng.randf_range(1.5, 2.8),
				"age": 0.0,
				"max_age": _rng.randf_range(1.5, 2.4)
			})

	# 4. Little floating hearts ONLY WHEN child actually reaches and hugs the tree trunk
	var enter_time := maxf(0.0, _timer - 8.5)
	var kid_run_t := clampf(enter_time / 2.2, 0.0, 1.0)
	var kid_is_hugging := _timer >= 8.5 and kid_run_t >= 1.0
	if kid_is_hugging:
		if _rng.randf() < delta * 2.2:
			_hearts.append({
				"pos": Vector2(center_x + 6.0 + _rng.randf_range(-4.0, 4.0), mid - 28.0),
				"vel": Vector2(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-14.0, -28.0)),
				"color": Color("ff5252"),
				"age": 0.0,
				"max_age": _rng.randf_range(1.4, 2.2)
			})

	# Update physics for particles
	for i in range(_sparkles.size() - 1, -1, -1):
		var p: Dictionary = _sparkles[i]
		p["age"] += delta
		if p["age"] >= p["max_age"]:
			_sparkles.remove_at(i)
		else:
			p["pos"] += p["vel"] * delta

	for i in range(_ambient_spores.size() - 1, -1, -1):
		var p: Dictionary = _ambient_spores[i]
		p["age"] += delta
		if p["age"] >= p["max_age"]:
			_ambient_spores.remove_at(i)
		else:
			p["pos"] += p["vel"] * delta

	for i in range(_hearts.size() - 1, -1, -1):
		var p: Dictionary = _hearts[i]
		p["age"] += delta
		if p["age"] >= p["max_age"]:
			_hearts.remove_at(i)
		else:
			p["pos"] += p["vel"] * delta


func _get_seed_pos(seed_data: Dictionary, t: float) -> Vector2:
	var start: Vector2 = seed_data["start"]
	var target: Vector2 = seed_data["target"]
	var arc: float = seed_data["arc_height"]
	var x := lerpf(start.x, target.x, t)
	var y := lerpf(start.y, target.y, t) - sin(t * PI) * arc
	return Vector2(x, y)


func _draw() -> void:
	var size := get_viewport_rect().size
	var mid := size.y * 0.5

	if not _initialized_points and size.x > 0.0:
		_setup_points(size)

	# 1. Sky & Sun restoring to golden sunny daylight
	_draw_sky(size, mid)

	# 2. Rolling hills healing from burnt ash to vivid greens
	_draw_hills(size, mid)

	# 3. Ground & soil healing from scorched earth to fertile meadow
	_draw_ground_and_soil(size, mid)

	# 4. Wildflowers blooming across the healed meadow
	_draw_wildflowers(mid)

	# 5. Fresh young trees growing where seeds landed (burnt stumps completely removed)
	_draw_new_sprouts(mid)

	# 7. Main tree blooming into magnificent lush foliage
	_draw_main_tree(Vector2(size.x * 0.50, mid))

	# 8. Flying life seeds and ambient spores
	_draw_seeds_and_spores()

	# 9. Returning family: remorseful parents and child hugging the tree
	_draw_family_and_embrace(size, mid)

	# 10. Sparkles & Hearts
	_draw_sparkles_and_hearts()

	# 11. Narrative texts & Educational message
	_draw_narrative_text(size)


func _draw_sky(size: Vector2, mid: float) -> void:
	# Transition from post-fire murky sky to sunny healed sky (0.0s to 6.5s)
	var heal_t := clampf(_timer / 6.0, 0.0, 1.0)
	var sky_top := Color("1b2028").lerp(SKY_TOP_HEALED, heal_t)
	var sky_horiz := Color("4f4347").lerp(SKY_HORIZON_HEALED, heal_t)

	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, mid), Vector2(0, mid)]),
		PackedColorArray([sky_top, sky_top, sky_horiz, sky_horiz])
	)

	# Radiant warm sun rising back into brilliance
	if heal_t > 0.05:
		var sun_pos := Vector2(size.x * 0.82, mid * 0.25)
		var r := mid * 0.11
		var c := SUN_COLOR
		c.a *= heal_t
		draw_circle(sun_pos, r, c)
		var c_ring := SUN_COLOR
		c_ring.a *= 0.28 * heal_t
		draw_circle(sun_pos, r * 1.45, c_ring)


func _draw_hills(size: Vector2, mid: float) -> void:
	var heal_t := clampf(_timer / 6.0, 0.0, 1.0)
	var far_col := Color("23272e").lerp(HILL_FAR_HEALED, heal_t)
	var near_col := Color("1b1e24").lerp(HILL_NEAR_HEALED, heal_t)

	_draw_wave(size.x, mid, mid * 0.72, mid * 0.08, 1.3, 0.0, far_col)
	_draw_wave(size.x, mid, mid * 0.82, mid * 0.06, 2.1, 1.7, near_col)


func _draw_wave(width: float, _bottom: float, base_y: float, amp: float, freq: float, phase: float, color: Color) -> void:
	var pts := PackedVector2Array()
	var steps := 48
	for i in steps + 1:
		var x := width * i / steps
		pts.append(Vector2(x, base_y - sin(x / width * TAU * freq + phase) * amp))
	pts.append(Vector2(width, _bottom))
	pts.append(Vector2(0, _bottom))
	draw_colored_polygon(pts, color)


func _draw_ground_and_soil(size: Vector2, mid: float) -> void:
	# Grass line transitions from charred soil (#1e140d) to vibrant green (#4f8a3c)
	var heal_t := clampf((_timer - 1.5) / 5.5, 0.0, 1.0)
	var grass_col := Color("1e140d").lerp(GRASS_HEALED, heal_t)

	draw_rect(Rect2(0, mid * 0.94, size.x, mid * 0.06), grass_col)

	# Underground soil: dark fertile earth
	var rows := int(ceil((size.y - mid) / TILE_SIZE))
	for r in rows:
		var y := mid + float(r) * TILE_SIZE
		var t := float(r) / float(maxi(rows, 1))
		var soil_row_col := Color("3a2417").lerp(Color("130904"), t)
		draw_rect(Rect2(0, y, size.x, TILE_SIZE), soil_row_col)


func _draw_wildflowers(mid: float) -> void:
	# Wildflowers emerge after grass heals (t > 4.5s)
	if _timer < 4.5:
		return
	var flower_alpha := clampf((_timer - 4.5) / 3.0, 0.0, 1.0)
	for f in _flowers:
		var c: Color = f["color"]
		c.a *= flower_alpha
		var pos := Vector2(f["x"], mid - f["y_off"])
		var s: float = f["size"]
		draw_rect(Rect2(pos.x - s * 0.5, pos.y - s * 0.5, s, s), c)


func _draw_new_sprouts(mid: float) -> void:
	if not _tree_texture:
		return

	# Fresh green trees growing at spread-out locations
	for pt in _sprout_points:
		var grow_t: float = pt["grow"]
		if grow_t <= 0.01:
			continue

		var sx: float = pt["x"]
		var target_scale: float = pt["scale"]
		var cur_scale: float = target_scale * clampf(grow_t, 0.15, 1.0)
		var tree_pixel_scale := TILE_SIZE * cur_scale
		var scaled_size := Vector2(SPRITE_SIZE, SPRITE_SIZE) * tree_pixel_scale
		var dest_pos := Vector2(sx - 19.0 * tree_pixel_scale, mid - 37.0 * tree_pixel_scale)

		var sway_px := sin(_wind_time * 5.0 + sx * 0.02) * 1.2
		var base_oscillation_x := sway_px * tree_pixel_scale
		var leaf_offset_x := base_oscillation_x * 0.75 * 0.66

		# Fresh healthy wood tone
		var trunk_col := Color("965b38")

		# Draw young tree trunk
		for row_y in SPRITE_SIZE:
			var height_t := clampf((36.0 - float(row_y)) / 32.0, 0.0, 1.0)
			var trunk_row_offset_x := base_oscillation_x * 0.5 * (height_t * height_t)
			var dst_row_rect := Rect2(
				dest_pos.x + trunk_row_offset_x,
				dest_pos.y + float(row_y) * tree_pixel_scale,
				scaled_size.x,
				tree_pixel_scale
			)
			var src_row := Rect2(SPRITE_RECT_SMALLROOT.position.x, SPRITE_RECT_SMALLROOT.position.y + row_y, SPRITE_SIZE, 1.0)
			draw_texture_rect_region(_tree_texture, dst_row_rect, src_row, trunk_col)

		# Draw vibrant young leaves once sprout has grown a bit
		if grow_t > 0.25:
			var leaf_alpha := clampf((grow_t - 0.25) / 0.45, 0.0, 1.0)
			var leaf_col := Color(1.0, 1.0, 1.0, leaf_alpha)
			var leaf_dest := Rect2(dest_pos + Vector2(leaf_offset_x, 0.0), scaled_size)
			var l_rect: Rect2 = pt.get("leaf_rect", SPRITE_RECT_MIDLEAVES)
			draw_texture_rect_region(_tree_texture, leaf_dest, l_rect, leaf_col)


func _draw_main_tree(pos: Vector2) -> void:
	if not _tree_texture:
		return

	var tree_pixel_scale := TILE_SIZE
	var scaled_size := Vector2(SPRITE_SIZE, SPRITE_SIZE) * tree_pixel_scale
	var dest_pos := Vector2(pos.x - 19.0 * tree_pixel_scale, pos.y - 37.0 * tree_pixel_scale)

	var sway_px := sin(_wind_time * 5.0) * 1.5
	var base_oscillation_x := sway_px * tree_pixel_scale
	var leaf_offset_x := base_oscillation_x * 0.75 * 0.66

	# Singed wood heals back into healthy, radiant bark (0.0s - 4.0s)
	var heal_bark_t := clampf(_timer / 4.0, 0.0, 1.0)
	var trunk_col := Color("6e3015").lerp(Color.WHITE, heal_bark_t)

	# Magnificent strong trunk (using BIGROOT sprite region for full grandeur)
	for row_y in SPRITE_SIZE:
		var height_t := clampf((36.0 - float(row_y)) / 32.0, 0.0, 1.0)
		var trunk_row_offset_x := base_oscillation_x * 0.5 * (height_t * height_t)
		var dst_row_rect := Rect2(
			dest_pos.x + trunk_row_offset_x,
			dest_pos.y + float(row_y) * tree_pixel_scale,
			scaled_size.x,
			tree_pixel_scale
		)
		var src_row := Rect2(SPRITE_RECT_BIGROOT.position.x, SPRITE_RECT_BIGROOT.position.y + row_y, SPRITE_SIZE, 1.0)
		draw_texture_rect_region(_tree_texture, dst_row_rect, src_row, trunk_col)

	# Full bloom: foliage blooms from bare branches into LARGELEAVES canopy (0.5s - 3.5s)
	var bloom_t := clampf((_timer - 0.5) / 3.0, 0.0, 1.0)
	if bloom_t > 0.02:
		var leaf_color := Color.WHITE
		leaf_color.a = bloom_t
		var leaf_dest := Rect2(dest_pos + Vector2(leaf_offset_x, 0.0), scaled_size)
		draw_texture_rect_region(_tree_texture, leaf_dest, SPRITE_RECT_LARGELEAVES, leaf_color)


func _draw_seeds_and_spores() -> void:
	# 1. Parabolic flight of targeted life seeds to empty soil
	for s in _target_seeds:
		if _timer >= s["start_time"] and not s["landed"]:
			var t: float = (_timer - s["start_time"]) / s["flight_duration"]
			var cur_pos := _get_seed_pos(s, clampf(t, 0.0, 1.0))
			# Small glowing yellow circular seed
			draw_circle(cur_pos, 3.5, Color("fff9c4"))
			draw_circle(cur_pos, 1.8, Color.WHITE)

	# 2. Ambient small yellow circular dots scattering and drifting down
	for p in _ambient_spores:
		var progress: float = p["age"] / p["max_age"]
		var r: float = p.get("radius", 2.2) * (1.0 - progress * 0.3)
		var col: Color = p["color"]
		col.a *= (1.0 - progress)
		draw_circle(p["pos"], r, col)


func _draw_sparkles_and_hearts() -> void:
	# Sparkles
	for p in _sparkles:
		var progress: float = p["age"] / p["max_age"]
		var s: float = lerpf(p["size"], 1.0, progress)
		var col: Color = p["color"]
		col.a *= (1.0 - progress)
		draw_rect(Rect2(p["pos"].x - s * 0.5, p["pos"].y - s * 0.5, s, s), col)

	# Floating red pixel hearts above child hugging the tree
	for h in _hearts:
		var progress: float = h["age"] / h["max_age"]
		var col: Color = h["color"]
		col.a *= (1.0 - progress)
		var pos: Vector2 = h["pos"]
		# Crisp 5x4 pixel heart
		draw_rect(Rect2(pos.x - 2.0, pos.y - 1.0, 1.0, 1.0), col)
		draw_rect(Rect2(pos.x, pos.y - 1.0, 1.0, 1.0), col)
		draw_rect(Rect2(pos.x - 3.0, pos.y, 5.0, 1.0), col)
		draw_rect(Rect2(pos.x - 2.0, pos.y + 1.0, 3.0, 1.0), col)
		draw_rect(Rect2(pos.x - 1.0, pos.y + 2.0, 1.0, 1.0), col)


func _draw_family_and_embrace(size: Vector2, mid: float) -> void:
	# Family appears at t >= 5.0s from the right side of the screen
	if _timer < 5.0:
		return

	var enter_time := _timer - 5.0
	var walk_phase := enter_time * 9.0

	var center_x := size.x * 0.5
	var dad_target_x := size.x * 0.65
	var mom_target_x := size.x * 0.70
	var kid_target_x := center_x + 6.0

	# Child runs quickly to the tree in 2.2s (reaches trunk at t = 7.2s)
	var kid_run_t := clampf(enter_time / 2.2, 0.0, 1.0)
	var kid_x := lerpf(size.x + 20.0, kid_target_x, kid_run_t)
	var kid_is_hugging := kid_run_t >= 1.0

	# Parents walk in 3.0s (reach position at t = 8.0s)
	var parent_walk_t := clampf(enter_time / 3.0, 0.0, 1.0)
	var dad_x := lerpf(size.x + 40.0, dad_target_x, parent_walk_t)
	var mom_x := lerpf(size.x + 65.0, mom_target_x, parent_walk_t)

	var dad_is_walking := parent_walk_t < 1.0
	var mom_is_walking := parent_walk_t < 1.0

	# Draw Dad
	_draw_remorseful_dad(Vector2(dad_x, mid), walk_phase, dad_is_walking)

	# Draw Mom
	_draw_remorseful_mom(Vector2(mom_x, mid), walk_phase, mom_is_walking)

	# Draw Child (runs to tree, then hugs trunk)
	if not kid_is_hugging:
		_draw_running_kid(Vector2(kid_x, mid), walk_phase)
	else:
		_draw_hugging_kid(Vector2(kid_target_x, mid))


func _draw_remorseful_dad(pos: Vector2, walk_phase: float, is_walking: bool) -> void:
	var leg_swing := sin(walk_phase) * 5.0 if is_walking else 0.0

	# Legs
	draw_line(Vector2(pos.x - 3.0, pos.y - 12.0), Vector2(pos.x - 3.0 - leg_swing, pos.y), Color("212121"), 3.0)
	draw_line(Vector2(pos.x + 3.0, pos.y - 12.0), Vector2(pos.x + 3.0 + leg_swing, pos.y), Color("212121"), 3.0)
	# Torso (Blue shirt: 12x14 px)
	draw_rect(Rect2(pos.x - 6.0, pos.y - 26.0, 12.0, 14.0), Color("1976d2"))
	# Head (Skin: 10x10 px)
	draw_rect(Rect2(pos.x - 5.0, pos.y - 36.0, 10.0, 10.0), Color("ffcc80"))
	# Hair (Dark brown)
	draw_rect(Rect2(pos.x - 6.0, pos.y - 39.0, 12.0, 4.0), Color("4e342e"))

	# Arms: hands clasped in front with head slightly bowed in remorse and reverence
	if is_walking:
		draw_line(Vector2(pos.x - 6.0, pos.y - 24.0), Vector2(pos.x - 6.0 - leg_swing, pos.y - 14.0), Color("ffcc80"), 2.5)
		draw_line(Vector2(pos.x + 6.0, pos.y - 24.0), Vector2(pos.x + 6.0 + leg_swing, pos.y - 14.0), Color("ffcc80"), 2.5)
	else:
		# Hands clasped together over chest
		draw_line(Vector2(pos.x - 5.0, pos.y - 22.0), Vector2(pos.x - 1.0, pos.y - 17.0), Color("ffcc80"), 2.5)
		draw_line(Vector2(pos.x + 5.0, pos.y - 22.0), Vector2(pos.x + 1.0, pos.y - 17.0), Color("ffcc80"), 2.5)


func _draw_remorseful_mom(pos: Vector2, walk_phase: float, is_walking: bool) -> void:
	var leg_swing := sin(walk_phase) * 5.0 if is_walking else 0.0

	# Legs (red shoes)
	draw_line(Vector2(pos.x - 3.0, pos.y - 10.0), Vector2(pos.x - 3.0 - leg_swing, pos.y), Color("d32f2f"), 2.5)
	draw_line(Vector2(pos.x + 3.0, pos.y - 10.0), Vector2(pos.x + 3.0 + leg_swing, pos.y), Color("d32f2f"), 2.5)
	# Yellow dress
	draw_rect(Rect2(pos.x - 6.0, pos.y - 23.0, 12.0, 14.0), Color("fbc02d"))
	# Head
	draw_rect(Rect2(pos.x - 5.0, pos.y - 33.0, 10.0, 10.0), Color("ffcc80"))
	# Hair
	draw_rect(Rect2(pos.x - 6.0, pos.y - 36.0, 12.0, 4.0), Color("5d4037"))
	draw_rect(Rect2(pos.x - 7.0, pos.y - 32.0, 3.0, 8.0), Color("5d4037"))

	# Arms: hand over heart in relief and remorse
	if is_walking:
		draw_line(Vector2(pos.x - 6.0, pos.y - 22.0), Vector2(pos.x - 6.0 - leg_swing, pos.y - 12.0), Color("ffcc80"), 2.5)
		draw_line(Vector2(pos.x + 6.0, pos.y - 22.0), Vector2(pos.x + 6.0 + leg_swing, pos.y - 12.0), Color("ffcc80"), 2.5)
	else:
		draw_line(Vector2(pos.x - 5.0, pos.y - 21.0), Vector2(pos.x - 1.0, pos.y - 18.0), Color("ffcc80"), 2.5)
		draw_line(Vector2(pos.x + 5.0, pos.y - 21.0), Vector2(pos.x + 1.0, pos.y - 14.0), Color("ffcc80"), 2.5)


func _draw_running_kid(pos: Vector2, walk_phase: float) -> void:
	var leg_swing := sin(walk_phase * 1.4) * 6.0

	# Running legs
	draw_line(Vector2(pos.x - 2.5, pos.y - 7.0), Vector2(pos.x - 2.5 - leg_swing, pos.y), Color("1e88e5"), 2.5)
	draw_line(Vector2(pos.x + 2.5, pos.y - 7.0), Vector2(pos.x + 2.5 + leg_swing, pos.y), Color("1e88e5"), 2.5)
	# Red shirt
	draw_rect(Rect2(pos.x - 4.0, pos.y - 16.0, 8.0, 9.0), Color("e53935"))
	# Head & cap
	draw_rect(Rect2(pos.x - 3.5, pos.y - 24.0, 7.0, 8.0), Color("ffcc80"))
	draw_rect(Rect2(pos.x - 4.0, pos.y - 26.0, 9.0, 3.0), Color("795548"))
	# Arms outstretched forward towards tree
	draw_line(Vector2(pos.x - 3.0, pos.y - 14.0), Vector2(pos.x - 10.0, pos.y - 15.0), Color("ffcc80"), 2.5)
	draw_line(Vector2(pos.x + 3.0, pos.y - 14.0), Vector2(pos.x - 6.0, pos.y - 12.0), Color("ffcc80"), 2.0)


func _draw_hugging_kid(pos: Vector2) -> void:
	# Child standing right against the bark, arms wrapped affectionately around the tree trunk!
	# Legs standing planted firmly
	draw_line(Vector2(pos.x - 1.0, pos.y - 7.0), Vector2(pos.x - 1.0, pos.y), Color("1e88e5"), 2.5)
	draw_line(Vector2(pos.x + 3.0, pos.y - 7.0), Vector2(pos.x + 3.0, pos.y), Color("1e88e5"), 2.5)

	# Red shirt leaned close against trunk
	draw_rect(Rect2(pos.x - 3.0, pos.y - 16.0, 8.0, 9.0), Color("e53935"))

	# Head leaned against trunk
	draw_rect(Rect2(pos.x - 2.5, pos.y - 24.0, 7.0, 8.0), Color("ffcc80"))
	draw_rect(Rect2(pos.x - 3.0, pos.y - 26.0, 8.0, 3.0), Color("795548"))

	# Symmetrical short arms wrapping around trunk on BOTH sides:
	# Left arm wrapping outwards to the left (4px arm):
	draw_line(Vector2(pos.x - 3.0, pos.y - 13.0), Vector2(pos.x - 7.0, pos.y - 13.0), Color("ffcc80"), 2.5)
	draw_line(Vector2(pos.x - 7.0, pos.y - 13.0), Vector2(pos.x - 8.0, pos.y - 10.0), Color("ffcc80"), 2.5)
	# Right arm wrapping outwards to the right, exactly like the left arm:
	draw_line(Vector2(pos.x + 5.0, pos.y - 13.0), Vector2(pos.x + 9.0, pos.y - 13.0), Color("ffcc80"), 2.5)
	draw_line(Vector2(pos.x + 9.0, pos.y - 13.0), Vector2(pos.x + 10.0, pos.y - 10.0), Color("ffcc80"), 2.5)


func _draw_narrative_text(size: Vector2) -> void:
	if not _vt323_font:
		return

	var mid := size.y * 0.5
	var soil_center_y := mid + (size.y - mid) * 0.5 # Center of underground soil area

	var is_tr := false
	if GameSettings:
		is_tr = (GameSettings.language == GameSettings.Language.TR)

	var main_text := ""
	var sub_text_line1 := ""
	var sub_text_line2 := ""
	var banner_alpha := 0.0
	var is_final := false
	var cta_prompt := ""

	if _timer < 4.5:
		main_text = "Kökler toprağa tutundukça, yaşam küllerin arasından yeniden doğdu." if is_tr else "As roots held onto the earth, life was reborn from the ashes."
		if _timer < 0.8:
			banner_alpha = _timer / 0.8
		elif _timer > 3.8:
			banner_alpha = clampf((4.5 - _timer) / 0.7, 0.0, 1.0)
		else:
			banner_alpha = 1.0

	elif _timer < 5.0:
		# Brief 0.5s pause between stage 1 and stage 2
		banner_alpha = 0.0

	elif _timer < 14.0:
		# Family return & remorseful educational message (Split across 3 lines: main text + 2 subtitle lines)
		main_text = "Doğa bize ikinci bir şans verdi; şimdi borcumuzu onu koruyarak ödeme vakti." if is_tr else "Nature gave us a second chance; time to repay our debt by protecting it."
		if is_tr:
			sub_text_line1 = "Ormanlar yalnızca ağaç değil; suyumuzu tutan"
			sub_text_line2 = "ve karbonu hapseden yaşam kalkanıdır."
		else:
			sub_text_line1 = "Forests are not just trees; they are life shields"
			sub_text_line2 = "holding water and trapping carbon."
		if _timer < 5.8:
			banner_alpha = (_timer - 5.0) / 0.8
		elif _timer > 13.3:
			banner_alpha = clampf((14.0 - _timer) / 0.7, 0.0, 1.0)
		else:
			banner_alpha = 1.0

	elif _timer < 14.5:
		# Brief 0.5s pause between stage 2 and stage 3
		banner_alpha = 0.0

	elif _timer < 18.5:
		# Closing narrative
		main_text = "Orman yeniden nefes alıyor... Doğayla barış içinde bir gelecek için." if is_tr else "The forest breathes again... For a future in peace with nature."
		if _timer < 15.3:
			banner_alpha = (_timer - 14.5) / 0.8
		elif _timer > 17.8:
			banner_alpha = clampf((18.5 - _timer) / 0.7, 0.0, 1.0)
		else:
			banner_alpha = 1.0
		is_final = true

	else:
		# When Continue prompt arrives, text is gone ("contiune gelince yazı gitsin o gelsın")
		banner_alpha = 0.0
		cta_prompt = "DEVAM ETMEK İÇİN SPACE TUŞUNA BAS" if is_tr else "PRESS SPACE TO CONTINUE"

	# Draw Narrative Banner in the middle of the soil
	if banner_alpha > 0.01 and main_text != "":
		# Left and right 10% margins: width is 80% of screen, centered at size.x * 0.10
		var margin_x := size.x * 0.10
		var text_area_w := size.x * 0.80

		var main_font_size := 30 if main_text.length() > 60 else (34 if main_text.length() > 40 else 38)
		if text_area_w < 720.0 and main_font_size > 26:
			main_font_size = 26

		var main_lines := _wrap_text_lines(main_text, _vt323_font, main_font_size, text_area_w)
		var has_sub := sub_text_line1 != ""

		var sub_font_size := 24
		if text_area_w < 720.0:
			sub_font_size = 20

		var sub_lines: Array[String] = []
		if has_sub:
			sub_lines.append_array(_wrap_text_lines(sub_text_line1, _vt323_font, sub_font_size, text_area_w))
			sub_lines.append_array(_wrap_text_lines(sub_text_line2, _vt323_font, sub_font_size, text_area_w))

		var main_line_gap := float(main_font_size) + 4.0
		var sub_line_gap := float(sub_font_size) + 4.0

		var total_content_h := float(main_lines.size()) * main_line_gap
		if has_sub:
			total_content_h += 8.0 + float(sub_lines.size()) * sub_line_gap

		var bar_height := total_content_h + 30.0
		var bar_rect := Rect2(0.0, soil_center_y - bar_height * 0.5, size.x, bar_height)
		draw_rect(bar_rect, Color(0.04, 0.04, 0.06, 0.78 * banner_alpha))
		draw_line(Vector2(0.0, bar_rect.position.y), Vector2(size.x, bar_rect.position.y), Color(0.65, 0.95, 0.55, 0.50 * banner_alpha), 1.0)
		draw_line(Vector2(0.0, bar_rect.position.y + bar_height), Vector2(size.x, bar_rect.position.y + bar_height), Color(0.65, 0.95, 0.55, 0.50 * banner_alpha), 1.0)

		var text_color := Color.WHITE
		text_color.a *= banner_alpha

		var current_y := soil_center_y - total_content_h * 0.5 + float(main_font_size) * 0.85

		# Draw Main Text Lines
		for line in main_lines:
			draw_string(_vt323_font, Vector2(margin_x + 2.0, current_y + 2.0), line, HORIZONTAL_ALIGNMENT_CENTER, text_area_w, main_font_size, Color(0.0, 0.0, 0.0, 0.85 * banner_alpha))
			draw_string(_vt323_font, Vector2(margin_x, current_y), line, HORIZONTAL_ALIGNMENT_CENTER, text_area_w, main_font_size, text_color)
			current_y += main_line_gap

		# Draw Subtitle Lines (if any)
		if has_sub:
			current_y += 4.0
			for s_line in sub_lines:
				draw_string(_vt323_font, Vector2(margin_x + 2.0, current_y + 2.0), s_line, HORIZONTAL_ALIGNMENT_CENTER, text_area_w, sub_font_size, Color(0.0, 0.0, 0.0, 0.85 * banner_alpha))
				draw_string(_vt323_font, Vector2(margin_x, current_y), s_line, HORIZONTAL_ALIGNMENT_CENTER, text_area_w, sub_font_size, text_color)
				current_y += sub_line_gap

	# Call to Action prompt at center of soil (replacing narrative text)
	if cta_prompt != "":
		var pulse := (sin(_timer * 4.8) + 1.0) * 0.5
		var prompt_col := Color("ffd54f").lerp(Color.WHITE, pulse)
		var box_w := 460.0 if is_tr else 380.0
		var box_h := 48.0
		var box_pos := Vector2((size.x - box_w) * 0.5, soil_center_y - box_h * 0.5)
		draw_rect(Rect2(box_pos, Vector2(box_w, box_h)), Color(0.0, 0.0, 0.0, 0.82))
		draw_rect(Rect2(box_pos, Vector2(box_w, box_h)), prompt_col, false, 2.0)
		draw_string(_vt323_font, Vector2(box_pos.x, box_pos.y + 33.0), cta_prompt, HORIZONTAL_ALIGNMENT_CENTER, box_w, 32, prompt_col)

	# Skip prompt in bottom right corner
	if _phase != Phase.READY:
		var skip_txt := "[SPACE] GEÇ" if is_tr else "[SPACE] SKIP"
		draw_string(_vt323_font, Vector2(size.x - 190.0, size.y - 24.0), skip_txt, HORIZONTAL_ALIGNMENT_RIGHT, 170.0, 22, Color.WHITE)


func _wrap_text_lines(raw_text: String, font: Font, font_size: int, max_width: float) -> Array[String]:
	var result: Array[String] = []
	if not font or raw_text == "":
		return result
	var words := raw_text.split(" ")
	var current_line := ""
	for word in words:
		if word == "":
			continue
		var test_line := word if current_line == "" else current_line + " " + word
		var measured_w: float = font.get_string_size(test_line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if measured_w <= max_width or current_line == "":
			current_line = test_line
		else:
			result.append(current_line)
			current_line = word
	if current_line != "":
		result.append(current_line)
	return result
