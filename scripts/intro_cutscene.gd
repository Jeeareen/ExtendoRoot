extends Node2D
## Dedicated animated pixel-art cinematic intro cutscene for ExtendoRoot.
## Features:
## - Peaceful forest with family picnic (parents + child) and barbecue grill.
## - Family departs leaving the burning BBQ unattended.
## - A spark leaps onto dry grass, igniting a devastating wildfire.
## - Surrounding trees burn down to charred stumps.
## - Main tree survives singed, losing all its leaves, revealing bare branches and trunk.
## - Ash drifts down in the aftermath; soil preview appears.
## - Interactive SPACE to skip anytime, or wait for "[ PRESS SPACE TO BEGIN ]".

signal finished

enum Phase {
	PEACEFUL_FAMILY,   # 0.0s - 3.5s: Serene forest, family enjoys picnic
	FAMILY_LEAVING,    # 3.5s - 6.2s: Family departs; BBQ left unattended & smoking
	SPARK_IGNITION,    # 6.2s - 7.2s: Careless spark arcs onto grass, ignites
	FIRE_SPREAD,       # 7.2s - 12.5s: Fire consumes forest; side trees burn to stumps; main tree leaves burn off
	AFTERMATH,         # 12.5s - 16.5s: Fire clears, ash falls; bare-branched singed main tree stands
	READY              # 16.5s+: Interactive prompt to begin
}

const TILE_SIZE := 8.0
const SPRITE_SIZE := 40
const SPRITE_RECT_SMALLROOT := Rect2(0, 0, 40, 40)
const SPRITE_RECT_MIDLEAVES := Rect2(80, 0, 40, 40)
const SPRITE_RECT_SMALLLEAVES := Rect2(40, 40, 40, 40)

const SKY_TOP := Color("4a90d9")
const SKY_HORIZON := Color("bfe3f5")
const SUN := Color("fff2a8")
const HILL_FAR := Color("7fae6a")
const HILL_NEAR := Color("5e9a4c")
const GRASS := Color("4f8a3c")

var _tree_texture: Texture2D = null
var _vt323_font: Font = null
var _rng := RandomNumberGenerator.new()

var _timer: float = 0.0
var _phase: Phase = Phase.PEACEFUL_FAMILY
var _wind_time: float = 0.0

var _fire_particles: Array = []
var _smoke_particles: Array = []
var _burning_leaf_particles: Array = []


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.randomize()
	if ResourceLoader.exists("res://assets/tree.png"):
		_tree_texture = load("res://assets/tree.png")
	if ResourceLoader.exists("res://assets/VT323-Regular.ttf"):
		_vt323_font = load("res://assets/VT323-Regular.ttf")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			_complete()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			var mode := DisplayServer.window_get_mode()
			if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _phase == Phase.READY:
			_complete()
			get_viewport().set_input_as_handled()


func _complete() -> void:
	finished.emit()


func _process(delta: float) -> void:
	_timer += delta
	_wind_time += delta

	# State phase progression
	if _timer < 3.5:
		_phase = Phase.PEACEFUL_FAMILY
	elif _timer < 6.2:
		_phase = Phase.FAMILY_LEAVING
	elif _timer < 7.2:
		_phase = Phase.SPARK_IGNITION
	elif _timer < 12.5:
		_phase = Phase.FIRE_SPREAD
	elif _timer < 16.5:
		_phase = Phase.AFTERMATH
	else:
		_phase = Phase.READY

	var size := get_viewport_rect().size
	var mid := size.y * 0.5
	_update_particles(delta, size, mid)
	queue_redraw()


func _update_particles(delta: float, size: Vector2, mid: float) -> void:
	var bbq_x := size.x * 0.58 + 10.0
	var spark_land_x := size.x * 0.58 + 26.0

	# 1. Gentle white smoke from BBQ grill (0.0s - 6.2s)
	if _timer < 6.2:
		if _rng.randf() < delta * 4.5:
			_smoke_particles.append({
				"pos": Vector2(bbq_x + _rng.randf_range(-3.0, 3.0), mid - 20.0),
				"vel": Vector2(_rng.randf_range(-4.0, 8.0), _rng.randf_range(-22.0, -36.0)),
				"radius": _rng.randf_range(3.0, 5.0),
				"max_radius": _rng.randf_range(10.0, 16.0),
				"color": Color(0.92, 0.94, 0.96, 0.45),
				"age": 0.0,
				"max_age": _rng.randf_range(2.0, 3.0)
			})

	# 2. Fire, sparks & billowing smoke during wildfire (7.0s - 13.0s)
	if _timer >= 7.0 and _timer < 13.0:
		var left_t := clampf((_timer - 7.0) / 4.2, 0.0, 1.0)
		var fire_left := lerpf(spark_land_x, size.x * 0.06, left_t)
		var right_t := clampf((_timer - 7.0) / 3.0, 0.0, 1.0)
		var fire_right := lerpf(spark_land_x, size.x * 0.94, right_t)

		var fire_intensity := 1.0
		if _timer > 11.5:
			fire_intensity = clampf((13.0 - _timer) / 1.5, 0.0, 1.0)

		# Ground fire particles
		var count := int(fire_intensity * 8.0)
		for k in count:
			var fx := _rng.randf_range(fire_left, fire_right)
			var col_choice := _rng.randf()
			var p_col: Color
			if col_choice < 0.35:
				p_col = Color("fff59d")
			elif col_choice < 0.7:
				p_col = Color("ff9800")
			else:
				p_col = Color("f44336")

			_fire_particles.append({
				"pos": Vector2(fx, mid - _rng.randf_range(0.0, 8.0)),
				"vel": Vector2(_rng.randf_range(-14.0, 14.0), _rng.randf_range(-45.0, -110.0)),
				"size": _rng.randf_range(3.0, 7.0),
				"color": p_col,
				"age": 0.0,
				"max_age": _rng.randf_range(0.25, 0.55)
			})

		# Dark billowing smoke clouds
		for k in 3:
			var sx := _rng.randf_range(fire_left, fire_right)
			_smoke_particles.append({
				"pos": Vector2(sx, mid - _rng.randf_range(4.0, 16.0)),
				"vel": Vector2(_rng.randf_range(10.0, 32.0), _rng.randf_range(-35.0, -75.0)),
				"radius": _rng.randf_range(6.0, 12.0),
				"max_radius": _rng.randf_range(28.0, 52.0),
				"color": Color(_rng.randf_range(0.12, 0.22), _rng.randf_range(0.10, 0.16), _rng.randf_range(0.08, 0.14), 0.55 * fire_intensity),
				"age": 0.0,
				"max_age": _rng.randf_range(2.5, 4.0)
			})

		# Burning leaves flying from the main tree canopy (8.5s - 11.2s)
		if _timer >= 8.5 and _timer < 11.2:
			var center_x := size.x * 0.5
			for k in 2:
				_burning_leaf_particles.append({
					"pos": Vector2(center_x + _rng.randf_range(-40.0, 40.0), mid - _rng.randf_range(60.0, 140.0)),
					"vel": Vector2(_rng.randf_range(45.0, 110.0), _rng.randf_range(-25.0, 30.0)),
					"color": Color("ff9800") if _rng.randf() < 0.6 else Color("f44336"),
					"size": _rng.randf_range(2.0, 5.0),
					"age": 0.0,
					"max_age": _rng.randf_range(0.8, 1.8)
				})

		# Tiny smoking wisps from burnt tree stumps
		var stumps := [size.x * 0.14, size.x * 0.28, size.x * 0.72, size.x * 0.86]
		for sx in stumps:
			if _rng.randf() < delta * 1.8:
				_smoke_particles.append({
					"pos": Vector2(sx + _rng.randf_range(-4.0, 4.0), mid - 14.0),
					"vel": Vector2(_rng.randf_range(-4.0, 8.0), _rng.randf_range(-16.0, -30.0)),
					"radius": _rng.randf_range(3.0, 5.0),
					"max_radius": _rng.randf_range(10.0, 16.0),
					"color": Color(0.65, 0.65, 0.65, 0.35),
					"age": 0.0,
					"max_age": _rng.randf_range(1.8, 2.8)
				})

	# Update physics
	for i in range(_smoke_particles.size() - 1, -1, -1):
		var p: Dictionary = _smoke_particles[i]
		p["age"] += delta
		if p["age"] >= p["max_age"]:
			_smoke_particles.remove_at(i)
		else:
			p["pos"] += p["vel"] * delta

	for i in range(_fire_particles.size() - 1, -1, -1):
		var p: Dictionary = _fire_particles[i]
		p["age"] += delta
		if p["age"] >= p["max_age"]:
			_fire_particles.remove_at(i)
		else:
			p["pos"] += p["vel"] * delta

	for i in range(_burning_leaf_particles.size() - 1, -1, -1):
		var p: Dictionary = _burning_leaf_particles[i]
		p["age"] += delta
		if p["age"] >= p["max_age"]:
			_burning_leaf_particles.remove_at(i)
		else:
			p["pos"] += p["vel"] * delta


func _draw() -> void:
	var size := get_viewport_rect().size
	var mid := size.y * 0.5

	# 1. Sky & Sun
	_draw_sky(size, mid)

	# 2. Rolling hills
	_draw_hills(size, mid)

	# 3. Ground meadow & underground preview
	_draw_ground_and_soil(size, mid)

	# 4. Smoke particles (behind trees)
	_draw_smoke_particles()

	# 5. Picnic Area, Barbecue Grill & Departing Family
	_draw_picnic_and_family(size, mid)

	# 6. Trees (Surrounding + Main Protagonist Tree)
	_draw_trees(size, mid)

	# 7. Flames on the grassline
	_draw_grass_fire(size, mid)

	# 8. Fire, burning leaves & Ash flakes
	_draw_foreground_particles()

	# 9. Narrative text & HUD prompts
	_draw_narrative_text(size)


func _draw_sky(size: Vector2, mid: float) -> void:
	var cur_sky_top := SKY_TOP
	var cur_sky_horiz := SKY_HORIZON
	var cur_sun_col := SUN
	var sun_alpha := 1.0

	if _timer < 6.2:
		cur_sky_top = SKY_TOP
		cur_sky_horiz = SKY_HORIZON
		sun_alpha = 1.0
	elif _timer < 12.5:
		var fire_t := clampf((_timer - 6.2) / 5.0, 0.0, 1.0)
		cur_sky_top = SKY_TOP.lerp(Color("160805"), fire_t)
		cur_sky_horiz = SKY_HORIZON.lerp(Color("9e320f"), fire_t)
		cur_sun_col = SUN.lerp(Color("d84315"), fire_t)
		sun_alpha = lerpf(1.0, 0.2, fire_t)
	else:
		var after_t := clampf((_timer - 12.5) / 3.0, 0.0, 1.0)
		cur_sky_top = Color("160805").lerp(Color("1b2028"), after_t)
		cur_sky_horiz = Color("9e320f").lerp(Color("4f4347"), after_t)
		sun_alpha = 0.0

	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, mid), Vector2(0, mid)]),
		PackedColorArray([cur_sky_top, cur_sky_top, cur_sky_horiz, cur_sky_horiz])
	)

	if sun_alpha > 0.02:
		var sun_pos := Vector2(size.x * 0.82, mid * 0.25)
		var r := mid * 0.1
		var c := cur_sun_col
		c.a *= sun_alpha
		draw_circle(sun_pos, r, c)
		var c_ring := cur_sun_col
		c_ring.a *= 0.2 * sun_alpha
		draw_circle(sun_pos, r * 1.35, c_ring)


func _draw_hills(size: Vector2, mid: float) -> void:
	var far_col := HILL_FAR
	var near_col := HILL_NEAR
	if _timer >= 6.2 and _timer < 12.5:
		var ht := clampf((_timer - 6.2) / 5.0, 0.0, 1.0)
		far_col = HILL_FAR.lerp(Color("3d2016"), ht)
		near_col = HILL_NEAR.lerp(Color("2a170f"), ht)
	elif _timer >= 12.5:
		var ht := clampf((_timer - 12.5) / 3.0, 0.0, 1.0)
		far_col = Color("3d2016").lerp(Color("23272e"), ht)
		near_col = Color("2a170f").lerp(Color("1b1e24"), ht)

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
	var grass_col := GRASS
	if _timer >= 7.0 and _timer < 12.5:
		var gt := clampf((_timer - 7.0) / 4.0, 0.0, 1.0)
		grass_col = GRASS.lerp(Color("22150e"), gt)
	elif _timer >= 12.5:
		grass_col = Color("1e140d")

	draw_rect(Rect2(0, mid * 0.94, size.x, mid * 0.06), grass_col)

	# Underground (below mid): solid dark soil layers (no water)
	var rows := int(ceil((size.y - mid) / TILE_SIZE))
	for r in rows:
		var y := mid + float(r) * TILE_SIZE
		var t := float(r) / float(maxi(rows, 1))
		var soil_row_col := Color("3a2417").lerp(Color("130904"), t)
		draw_rect(Rect2(0, y, size.x, TILE_SIZE), soil_row_col)


func _draw_picnic_and_family(size: Vector2, mid: float) -> void:
	var picnic_base_x := size.x * 0.58
	var bbq_x := picnic_base_x + 10.0
	var bbq_base_y := mid

	# 1. Barbecue Kettle Grill (STAYS IN PLACE even after family leaves!)
	# Ground shadow
	draw_line(Vector2(bbq_x - 8.0, bbq_base_y), Vector2(bbq_x + 8.0, bbq_base_y), Color(0.0, 0.0, 0.0, 0.35), 2.0)
	# Grill tripod legs
	var leg_col := Color("141414")
	draw_line(Vector2(bbq_x - 7.0, bbq_base_y), Vector2(bbq_x - 3.0, bbq_base_y - 12.0), leg_col, 2.0)
	draw_line(Vector2(bbq_x + 7.0, bbq_base_y), Vector2(bbq_x + 3.0, bbq_base_y - 12.0), leg_col, 2.0)
	draw_line(Vector2(bbq_x, bbq_base_y), Vector2(bbq_x, bbq_base_y - 12.0), leg_col, 2.0)

	# Kettle bowl
	var bowl_rect := Rect2(bbq_x - 8.0, bbq_base_y - 20.0, 16.0, 10.0)
	draw_rect(bowl_rect, Color("222222"))
	draw_rect(Rect2(bbq_x - 9.0, bbq_base_y - 21.0, 18.0, 3.0), Color("333333"))

	# Glowing hot coals inside
	var coal_glow := (sin(_timer * 6.0) + 1.0) * 0.5
	var coal_col := Color("ff5722").lerp(Color("ffeb3b"), coal_glow * 0.6)
	draw_rect(Rect2(bbq_x - 6.0, bbq_base_y - 19.0, 12.0, 4.0), coal_col)

	# Careless Spark flying out from unattended grill (6.2s to 7.0s)
	if _timer >= 6.2 and _timer < 7.0:
		var spark_t := (_timer - 6.2) / 0.8
		var target_x := bbq_x + 16.0
		var sx := lerpf(bbq_x, target_x, spark_t)
		var sy := lerpf(bbq_base_y - 19.0, bbq_base_y, spark_t) - sin(spark_t * PI) * 26.0
		draw_rect(Rect2(Vector2(sx - 2.0, sy - 2.0), Vector2(4.0, 4.0)), Color("fff59d"))
		draw_rect(Rect2(Vector2(sx - 1.0, sy - 1.0), Vector2(2.0, 2.0)), Color.WHITE)

	# 2. Picnic Blanket & Basket
	var blk_x := picnic_base_x + 28.0
	var blk_w := 48.0
	var blk_h := 10.0
	var picnic_burn := 0.0
	if _timer >= 7.0:
		picnic_burn = clampf((_timer - 7.0) / 1.8, 0.0, 1.0)

	if picnic_burn < 1.0:
		var blk_mod := Color.WHITE.lerp(Color("1a100a"), picnic_burn)
		var tile_w := 8.0
		var tile_h := 5.0
		for row in 2:
			for col in 6:
				var is_red := (col + row) % 2 == 0
				var t_col := Color("d32f2f") if is_red else Color("f5f5f5")
				t_col = t_col * blk_mod
				draw_rect(Rect2(blk_x + float(col) * tile_w, bbq_base_y - 4.0 + float(row) * tile_h, tile_w, tile_h), t_col)

		# Basket stays on blanket only if mom hasn't picked it up (before 3.5s)
		if _timer < 3.5:
			var basket_rect := Rect2(blk_x + 8.0, bbq_base_y - 16.0, 14.0, 12.0)
			draw_rect(basket_rect, Color("8d5524"))
			draw_line(Vector2(basket_rect.position.x, basket_rect.position.y), Vector2(basket_rect.position.x + basket_rect.size.x, basket_rect.position.y), Color("a06530"), 1.0)
			draw_rect(Rect2(blk_x + 12.0, bbq_base_y - 16.0, 6.0, 5.0), Color.WHITE)
			draw_rect(Rect2(blk_x + 32.0, bbq_base_y - 7.0, 4.0, 4.0), Color("e53935"))
	else:
		# Burnt ash smudge
		draw_rect(Rect2(blk_x, bbq_base_y - 2.0, blk_w, 4.0), Color("170f0a"))

	# 3. Family Pixel Figures: Dad, Mom, Child walking away together!
	var is_walking := _timer >= 3.5
	var walk_phase := _timer * 11.0

	var dad_x: float
	var mom_x: float
	var kid_x: float

	if not is_walking:
		dad_x = bbq_x - 12.0
		mom_x = blk_x + 14.0
		kid_x = blk_x + 28.0
	else:
		# Group up and walk together as a unified family at identical speed
		var walk_time := _timer - 3.5
		var group_center := (blk_x + 22.0) + walk_time * 78.0
		var form_t := clampf(walk_time / 0.5, 0.0, 1.0)
		var start_dad := bbq_x - 12.0
		var start_mom := blk_x + 14.0
		var start_kid := blk_x + 28.0

		dad_x = lerpf(start_dad, group_center - 13.0, form_t) + (1.0 - form_t) * walk_time * 78.0
		kid_x = lerpf(start_kid, group_center, form_t) + (1.0 - form_t) * walk_time * 78.0
		mom_x = lerpf(start_mom, group_center + 13.0, form_t) + (1.0 - form_t) * walk_time * 78.0

		if form_t >= 1.0:
			dad_x = group_center - 13.0
			kid_x = group_center
			mom_x = group_center + 13.0

	# Draw family while on screen
	if dad_x < size.x + 30.0 or mom_x < size.x + 30.0 or kid_x < size.x + 30.0:
		# When walking together, draw hand holding between parents and child
		if is_walking and dad_x < size.x + 20.0 and kid_x < size.x + 20.0 and mom_x < size.x + 20.0:
			draw_line(Vector2(dad_x + 3.0, mid - 10.0), Vector2(kid_x - 2.0, mid - 8.0), Color("ffcc80"), 2.0)
			draw_line(Vector2(mom_x - 3.0, mid - 10.0), Vector2(kid_x + 2.0, mid - 8.0), Color("ffcc80"), 2.0)

		if dad_x < size.x + 30.0:
			_draw_person(Vector2(dad_x, mid), "dad", walk_phase, is_walking)
		if kid_x < size.x + 30.0:
			_draw_person(Vector2(kid_x, mid), "kid", walk_phase, is_walking)
		if mom_x < size.x + 30.0:
			_draw_person(Vector2(mom_x, mid), "mom", walk_phase, is_walking)


func _draw_person(pos: Vector2, person_type: String, walk_phase: float, is_walking: bool) -> void:
	var leg_swing := sin(walk_phase) * 4.5 if is_walking else 0.0

	if person_type == "dad":
		# Legs
		draw_line(Vector2(pos.x - 2.0, pos.y - 8.0), Vector2(pos.x - 2.0 - leg_swing, pos.y), Color("212121"), 2.0)
		draw_line(Vector2(pos.x + 2.0, pos.y - 8.0), Vector2(pos.x + 2.0 + leg_swing, pos.y), Color("212121"), 2.0)
		# Torso (Blue shirt)
		draw_rect(Rect2(pos.x - 4.0, pos.y - 18.0, 8.0, 10.0), Color("1976d2"))
		# Head (Skin tone)
		draw_rect(Rect2(pos.x - 3.0, pos.y - 25.0, 6.0, 7.0), Color("ffcc80"))
		# Hair (Dark brown)
		draw_rect(Rect2(pos.x - 4.0, pos.y - 27.0, 8.0, 3.0), Color("4e342e"))
		# If standing by grill, hold spatula towards grill
		if not is_walking:
			draw_line(Vector2(pos.x + 3.0, pos.y - 14.0), Vector2(pos.x + 10.0, pos.y - 17.0), Color("ffcc80"), 2.0)
			draw_rect(Rect2(pos.x + 10.0, pos.y - 19.0, 4.0, 3.0), Color("9e9e9e"))

	elif person_type == "mom":
		if not is_walking:
			# Sitting on blanket
			draw_rect(Rect2(pos.x - 4.0, pos.y - 12.0, 8.0, 8.0), Color("fbc02d")) # Yellow dress
			draw_rect(Rect2(pos.x - 3.0, pos.y - 19.0, 6.0, 7.0), Color("ffcc80")) # Head
			draw_rect(Rect2(pos.x - 4.0, pos.y - 21.0, 8.0, 3.0), Color("5d4037")) # Hair
			draw_rect(Rect2(pos.x - 5.0, pos.y - 18.0, 3.0, 6.0), Color("5d4037")) # Long hair
		else:
			# Walking
			draw_line(Vector2(pos.x - 2.0, pos.y - 7.0), Vector2(pos.x - 2.0 - leg_swing, pos.y), Color("d32f2f"), 2.0)
			draw_line(Vector2(pos.x + 2.0, pos.y - 7.0), Vector2(pos.x + 2.0 + leg_swing, pos.y), Color("d32f2f"), 2.0)
			draw_rect(Rect2(pos.x - 4.0, pos.y - 17.0, 8.0, 10.0), Color("fbc02d")) # Yellow dress
			draw_rect(Rect2(pos.x - 3.0, pos.y - 24.0, 6.0, 7.0), Color("ffcc80"))
			draw_rect(Rect2(pos.x - 4.0, pos.y - 26.0, 8.0, 3.0), Color("5d4037"))
			# Carrying the picnic basket
			draw_rect(Rect2(pos.x + 4.0, pos.y - 12.0, 8.0, 7.0), Color("8d5524"))

	elif person_type == "kid":
		# Small child (12px tall)
		draw_line(Vector2(pos.x - 2.0, pos.y - 5.0), Vector2(pos.x - 2.0 - leg_swing, pos.y), Color("1e88e5"), 2.0)
		draw_line(Vector2(pos.x + 2.0, pos.y - 5.0), Vector2(pos.x + 2.0 + leg_swing, pos.y), Color("1e88e5"), 2.0)
		# Red shirt
		draw_rect(Rect2(pos.x - 3.0, pos.y - 12.0, 6.0, 7.0), Color("e53935"))
		# Head & cap
		draw_rect(Rect2(pos.x - 2.0, pos.y - 18.0, 5.0, 6.0), Color("ffcc80"))
		draw_rect(Rect2(pos.x - 3.0, pos.y - 19.0, 7.0, 2.0), Color("795548"))


func _draw_trees(size: Vector2, mid: float) -> void:
	# Burn progress for surrounding trees
	var burn_t3 := clampf((_timer - 7.6) / 2.0, 0.0, 1.0) if _timer >= 7.6 else 0.0
	var burn_t4 := clampf((_timer - 8.4) / 2.0, 0.0, 1.0) if _timer >= 8.4 else 0.0
	var burn_t1 := clampf((_timer - 9.0) / 2.0, 0.0, 1.0) if _timer >= 9.0 else 0.0
	var burn_t0 := clampf((_timer - 9.8) / 2.0, 0.0, 1.0) if _timer >= 9.8 else 0.0

	# Surrounding trees: burn down to small charred stumps
	_draw_tree_instance(Vector2(size.x * 0.14, mid), SPRITE_RECT_MIDLEAVES, 0.85, burn_t0, false)
	_draw_tree_instance(Vector2(size.x * 0.28, mid), SPRITE_RECT_MIDLEAVES, 1.10, burn_t1, false)
	_draw_tree_instance(Vector2(size.x * 0.72, mid), SPRITE_RECT_MIDLEAVES, 1.05, burn_t3, false)
	_draw_tree_instance(Vector2(size.x * 0.86, mid), SPRITE_RECT_MIDLEAVES, 0.90, burn_t4, false)

	# MAIN PROTAGONIST TREE (Center: size.x * 0.50):
	# Survives the fire! Leaves burn off and blow away, exposing bare branches and singed trunk!
	var main_leaf_burn := 0.0
	var main_singe := 0.0
	if _timer >= 8.5:
		main_leaf_burn = clampf((_timer - 8.5) / 2.5, 0.0, 1.0)
		main_singe = clampf((_timer - 8.5) / 3.0, 0.0, 1.0)

	_draw_main_tree(Vector2(size.x * 0.50, mid), main_leaf_burn, main_singe)


func _draw_main_tree(pos: Vector2, leaf_burn_t: float, singe_t: float) -> void:
	if not _tree_texture:
		return

	var tree_pixel_scale := TILE_SIZE
	var scaled_size := Vector2(SPRITE_SIZE, SPRITE_SIZE) * tree_pixel_scale
	var dest_pos := Vector2(pos.x - 19.0 * tree_pixel_scale, pos.y - 37.0 * tree_pixel_scale)

	var sway_px := sin(_wind_time * 5.0) * 1.5
	var base_oscillation_x := sway_px * tree_pixel_scale
	var leaf_offset_x := base_oscillation_x * 0.75

	# Trunk tone: darkens with singe_t to a charred wood tone (#6e3015 / #451b08)
	var trunk_col := Color.WHITE.lerp(Color("6e3015"), singe_t * 0.85)

	# Draw trunk and bare branches (SPRITE_RECT_SMALLROOT rows 0..36 contains trunk & bare branches!)
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

	# Leaves on main tree:
	# Burn and fade away as leaf_burn_t reaches 1.0! Once burnt, leaves are completely gone!
	if leaf_burn_t < 1.0:
		var leaf_alpha := clampf((1.0 - leaf_burn_t) * 1.25, 0.0, 1.0)
		var leaf_color := Color.WHITE.lerp(Color("ff4500"), leaf_burn_t)
		leaf_color.a *= leaf_alpha
		if leaf_color.a > 0.02:
			var leaf_dest := Rect2(dest_pos + Vector2(leaf_offset_x, 0.0), scaled_size)
			draw_texture_rect_region(_tree_texture, leaf_dest, SPRITE_RECT_SMALLLEAVES, leaf_color)


func _draw_tree_instance(pos: Vector2, leaf_rect: Rect2, sway_mult: float, burn_progress: float, _is_main: bool) -> void:
	if not _tree_texture:
		return

	var tree_pixel_scale := TILE_SIZE
	var scaled_size := Vector2(SPRITE_SIZE, SPRITE_SIZE) * tree_pixel_scale
	var dest_pos := Vector2(pos.x - 19.0 * tree_pixel_scale, pos.y - 37.0 * tree_pixel_scale)

	var sway_px := sin(_wind_time * 5.0 + pos.x * 0.015) * 1.5 * sway_mult
	var base_oscillation_x := sway_px * tree_pixel_scale
	var leaf_offset_x := base_oscillation_x * 0.75

	if burn_progress >= 1.0:
		# Burnt to a small charred stump (rows 31..36)
		var stump_col := Color("140905")
		for row_y in range(31, SPRITE_SIZE):
			var dst_row_rect := Rect2(dest_pos.x, dest_pos.y + float(row_y) * tree_pixel_scale, scaled_size.x, tree_pixel_scale)
			var src_row := Rect2(SPRITE_RECT_SMALLROOT.position.x, SPRITE_RECT_SMALLROOT.position.y + row_y, SPRITE_SIZE, 1.0)
			draw_texture_rect_region(_tree_texture, dst_row_rect, src_row, stump_col)
		return

	var trunk_col := Color.WHITE
	if burn_progress > 0.0:
		trunk_col = Color.WHITE.lerp(Color("160a06"), burn_progress)

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

	# Leaves
	if burn_progress < 1.0:
		var leaf_alpha := clampf((1.0 - burn_progress) * 1.25, 0.0, 1.0)
		var leaf_tint := Color.WHITE.lerp(Color("ff4500"), burn_progress)
		leaf_tint.a *= leaf_alpha
		if leaf_tint.a > 0.02:
			var leaf_dest := Rect2(dest_pos + Vector2(leaf_offset_x, 0.0), scaled_size)
			draw_texture_rect_region(_tree_texture, leaf_dest, leaf_rect, leaf_tint)


func _draw_grass_fire(size: Vector2, mid: float) -> void:
	if _timer < 7.0 or _timer >= 13.0:
		return

	var spark_land_x := size.x * 0.58 + 26.0
	var left_t := clampf((_timer - 7.0) / 4.2, 0.0, 1.0)
	var fire_left := lerpf(spark_land_x, size.x * 0.06, left_t)
	var right_t := clampf((_timer - 7.0) / 3.0, 0.0, 1.0)
	var fire_right := lerpf(spark_land_x, size.x * 0.94, right_t)

	var fire_alpha := 1.0
	if _timer > 11.5:
		fire_alpha = clampf((13.0 - _timer) / 1.5, 0.0, 1.0)

	var step_x := 8.0
	var num_steps := int((fire_right - fire_left) / step_x)
	for s in num_steps:
		var fx := fire_left + float(s) * step_x
		var jitter := sin(fx * 0.35 + _timer * 16.0) * 0.5 + 0.5
		var flame_h := jitter * 14.0 + 4.0
		var col_outer := Color("f44336")
		col_outer.a *= fire_alpha
		var col_inner := Color("ffeb3b")
		col_inner.a *= fire_alpha
		draw_rect(Rect2(fx, mid - flame_h, step_x, flame_h), col_outer)
		draw_rect(Rect2(fx + 2.0, mid - flame_h * 0.65, step_x - 4.0, flame_h * 0.65), col_inner)


func _draw_smoke_particles() -> void:
	for p in _smoke_particles:
		var progress: float = p["age"] / p["max_age"]
		var r: float = lerpf(p["radius"], p["max_radius"], progress)
		var col: Color = p["color"]
		col.a *= (1.0 - progress)
		draw_circle(p["pos"], r, col)


func _draw_foreground_particles() -> void:
	# Fire particles
	for p in _fire_particles:
		var progress: float = p["age"] / p["max_age"]
		var s: float = lerpf(p["size"], 1.5, progress)
		var col: Color = p["color"]
		col.a *= (1.0 - progress)
		draw_rect(Rect2(p["pos"].x - s * 0.5, p["pos"].y - s * 0.5, s, s), col)

	# Burning leaf fragments flying from main tree canopy
	for p in _burning_leaf_particles:
		var progress: float = p["age"] / p["max_age"]
		var s: float = p["size"]
		var col: Color = p["color"]
		col.a *= (1.0 - progress)
		draw_rect(Rect2(p["pos"].x, p["pos"].y, s, s), col)


func _draw_narrative_text(size: Vector2) -> void:
	if not _vt323_font:
		return

	var text := ""
	var alpha := 0.0
	var is_final := false
	var subtext := ""

	if _timer < 6.0:
		text = "A peaceful forest, full of beautiful life..."
		if _timer < 0.8:
			alpha = _timer / 0.8
		elif _timer > 5.2:
			alpha = clampf((6.0 - _timer) / 0.8, 0.0, 1.0)
		else:
			alpha = 1.0
	elif _timer < 12.5:
		text = "A single careless spark... turned forest to ashes."
		if _timer < 6.8:
			alpha = (_timer - 6.0) / 0.8
		elif _timer > 11.8:
			alpha = clampf((12.5 - _timer) / 0.7, 0.0, 1.0)
		else:
			alpha = 1.0
	else:
		text = "The fate of the forest is now in your hands."
		alpha = clampf((_timer - 12.5) / 0.8, 0.0, 1.0)
		is_final = true
		if _timer >= 16.5:
			subtext = "[ PRESS SPACE TO BEGIN ]"

	if alpha > 0.01 and text != "":
		# Letterbox top banner
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
		var pulse := (sin(_timer * 4.8) + 1.0) * 0.5
		var sub_color := Color("ffd54f").lerp(Color.WHITE, pulse)
		var box_w := 360.0
		var box_h := 46.0
		var box_pos := Vector2((size.x - box_w) * 0.5, size.y * 0.74)
		draw_rect(Rect2(box_pos, Vector2(box_w, box_h)), Color(0.0, 0.0, 0.0, 0.75))
		draw_rect(Rect2(box_pos, Vector2(box_w, box_h)), sub_color, false, 2.0)
		draw_string(_vt323_font, Vector2(box_pos.x, box_pos.y + 32.0), subtext, HORIZONTAL_ALIGNMENT_CENTER, box_w, 32, sub_color)

	# Skip prompt in bottom right
	if _phase != Phase.READY:
		draw_string(_vt323_font, Vector2(size.x - 170.0, size.y - 24.0), "[ SPACE ] SKIP", HORIZONTAL_ALIGNMENT_RIGHT, 150.0, 22, Color(1.0, 1.0, 1.0, 0.65))
