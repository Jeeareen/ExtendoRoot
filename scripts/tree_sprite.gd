extends RefCounted
## Shared loader for the tree spritesheet. Applies the dark side shading to the leaf sprites
## so the game, intro and outro scenes all show the same tree.

const SPRITE_SIZE := 40

static var _shaded_image: Image = null
static var _shaded_texture: Texture2D = null


static func get_shaded_image() -> Image:
	if _shaded_image == null:
		var tex := load("res://assets/tree.png") as Texture2D
		if tex == null:
			return null
		var img := tex.get_image()
		if img == null:
			return null
		img.convert(Image.FORMAT_RGBA8)
		darken_leaf_sides(img)
		_shaded_image = img
	return _shaded_image


static func get_shaded_texture() -> Texture2D:
	if _shaded_texture == null:
		var img := get_shaded_image()
		if img == null:
			return load("res://assets/tree.png") as Texture2D
		_shaded_texture = ImageTexture.create_from_image(img)
	return _shaded_texture


static func darken_leaf_sides(img: Image) -> void:
	# Shades the far-left / far-right edges of each leaf sprite (and a little of the bottom) towards near-black,
	# with a stepped gradient so it blends into the normal leaf color and echoes the dark trunk.
	var leaf_rects: Array[Rect2i] = [
		Rect2i(80, 0, SPRITE_SIZE, SPRITE_SIZE),  # mid leaves
		Rect2i(0, 40, SPRITE_SIZE, SPRITE_SIZE),  # large leaves
		Rect2i(40, 40, SPRITE_SIZE, SPRITE_SIZE), # small leaves
		Rect2i(80, 40, SPRITE_SIZE, SPRITE_SIZE), # dry leaves
	]
	# Blend amount towards the dark color by depth from the edge (0 = outermost pixel)
	var ramp: Array[float] = [0.64, 0.58, 0.45, 0.30, 0.16, 0.07]
	var bottom_extra := 3 # bottom shading only reaches (ramp.size() - bottom_extra) pixels deep
	for rect in leaf_rects:
		var is_dry := rect.position == Vector2i(80, 40)
		var dark_col := Color("2a1205") if is_dry else Color("0b1a08")
		var row_min: Dictionary = {}
		var row_max: Dictionary = {}
		var col_max: Dictionary = {}
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			for x in range(rect.position.x, rect.position.x + rect.size.x):
				if img.get_pixel(x, y).a <= 0.0:
					continue
				if not row_min.has(y) or x < row_min[y]:
					row_min[y] = x
				if not row_max.has(y) or x > row_max[y]:
					row_max[y] = x
				if not col_max.has(x) or y > col_max[x]:
					col_max[x] = y
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			for x in range(rect.position.x, rect.position.x + rect.size.x):
				var c: Color = img.get_pixel(x, y)
				if c.a <= 0.0:
					continue
				var side_depth: int = mini(x - int(row_min[y]), int(row_max[y]) - x)
				var bottom_depth: int = int(col_max[x]) - y
				var idx: int = mini(side_depth, bottom_depth + bottom_extra)
				if idx >= ramp.size():
					continue
				img.set_pixel(x, y, Color(c.lerp(dark_col, ramp[idx]), c.a))
