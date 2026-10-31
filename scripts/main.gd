extends Node2D
## Draws the split-screen scene procedurally:
## upper half = landscape with a tree, lower half = brown soil.

const SKY_TOP := Color("4a90d9")
const SKY_HORIZON := Color("bfe3f5")
const SUN := Color("fff2a8")
const HILL_FAR := Color("7fae6a")
const HILL_NEAR := Color("5e9a4c")
const GRASS := Color("4f8a3c")
const SOIL_TOP := Color("7a4e2d")
const SOIL_BOTTOM := Color("4a2d17")
const TRUNK := Color("6b4423")
const LEAVES_DARK := Color("2f6b2a")
const LEAVES := Color("3f8a36")
const LEAVES_LIGHT := Color("58a84a")


func _ready() -> void:
	get_viewport().size_changed.connect(queue_redraw)


func _draw() -> void:
	var size := get_viewport_rect().size
	var mid := size.y * 0.5
	_draw_sky(size, mid)
	_draw_hills(size, mid)
	_draw_tree(Vector2(size.x * 0.5, mid), mid)
	_draw_soil(size, mid)


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


func _draw_soil(size: Vector2, mid: float) -> void:
	draw_polygon(
		PackedVector2Array([Vector2(0, mid), Vector2(size.x, mid), size, Vector2(0, size.y)]),
		PackedColorArray([SOIL_TOP, SOIL_TOP, SOIL_BOTTOM, SOIL_BOTTOM])
	)
	# Deterministic pebbles for texture
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 80:
		var p := Vector2(rng.randf() * size.x, mid + rng.randf() * (size.y - mid))
		draw_circle(p, rng.randf_range(1.5, 4.0), Color(0, 0, 0, rng.randf_range(0.08, 0.2)))
