extends Control
## Main Menu for ExtendoRoot

var _vt323_font: Font = null

# Focus targets: "BUTTONS" or "LANG_TR" or "LANG_UK"
enum FocusArea { BUTTONS, LANG_TR, LANG_UK }
var _focus_area: FocusArea = FocusArea.BUTTONS
var _hovered_btn_idx: int = 0
var _mouse_hovered_lang: String = ""

var _tr_flag_tex: Texture2D = null
var _uk_flag_tex: Texture2D = null
var _title_logo_tex: Texture2D = null

enum Language { EN, TR }
var _current_language: Language = Language.EN

enum MenuState { MAIN, DIFFICULTY }
var _menu_state: MenuState = MenuState.MAIN

enum DifficultyLevel { EASY, MEDIUM, HARD }
var _selected_difficulty: DifficultyLevel = DifficultyLevel.EASY

const TITLE_COLOR := Color("58a84a")
const TITLE_SHADOW := Color("1b0800")
const BTN_NORMAL_BG := Color(0.12, 0.12, 0.12, 0.88)
const BTN_HOVER_BG := Color(0.22, 0.28, 0.22, 0.95)
const BTN_PASSIVE_BG := Color(0.10, 0.10, 0.10, 0.60)

const BTN_ACTIVE_TEXT := Color.WHITE
const BTN_ACTIVE_HOVER_TEXT := Color("bfe3f5")
const BTN_PASSIVE_TEXT := Color(0.55, 0.55, 0.55, 0.70)

const MAIN_BUTTONS := [
	{"id": "play", "text_en": "Play Game", "text_tr": "Oyuna Başla", "active": true},
	{"id": "difficulty", "text_en": "Difficulty", "text_tr": "Zorluk", "active": true},
	{"id": "how_to_play", "text_en": "How to Play", "text_tr": "Nasıl Oynanır", "active": false},
	{"id": "about", "text_en": "About", "text_tr": "Hakkında", "active": false}
]

const DIFFICULTY_BUTTONS := [
	{"id": "diff_easy", "text_en": "Easy", "text_tr": "Kolay", "active": true},
	{"id": "diff_medium", "text_en": "Medium", "text_tr": "Orta", "active": true},
	{"id": "diff_hard", "text_en": "Hard", "text_tr": "Zor", "active": true},
	{"id": "back", "text_en": "< Back", "text_tr": "< Geri", "active": true}
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_vt323_font = load("res://assets/VT323-Regular.ttf")

	if ResourceLoader.exists("res://assets/TR.png"):
		_tr_flag_tex = load("res://assets/TR.png")
	if ResourceLoader.exists("res://assets/UK.png"):
		_uk_flag_tex = load("res://assets/UK.png")
	if ResourceLoader.exists("res://assets/Extendoroot.png"):
		_title_logo_tex = load("res://assets/Extendoroot.png")
	elif ResourceLoader.exists("res://assets/extendoroot.png"):
		_title_logo_tex = load("res://assets/extendoroot.png")

	if GameSettings:
		match GameSettings.difficulty:
			GameSettings.Difficulty.EASY:
				_selected_difficulty = DifficultyLevel.EASY
			GameSettings.Difficulty.MEDIUM:
				_selected_difficulty = DifficultyLevel.MEDIUM
			GameSettings.Difficulty.HARD:
				_selected_difficulty = DifficultyLevel.HARD
		match GameSettings.language:
			GameSettings.Language.EN:
				_current_language = Language.EN
			GameSettings.Language.TR:
				_current_language = Language.TR

	get_viewport().size_changed.connect(queue_redraw)


func _get_current_buttons() -> Array:
	return MAIN_BUTTONS if _menu_state == MenuState.MAIN else DIFFICULTY_BUTTONS


func _get_button_rects(size: Vector2) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var buttons := _get_current_buttons()
	var count := buttons.size()
	if count == 0:
		return rects

	var btn_w := 260.0
	var btn_h := 46.0

	var mid := size.y * 0.5
	var lower_h := size.y - mid

	# Equal vertical margins across the lower half screen: (count + 1) spaces
	var total_btn_h := float(count) * btn_h
	var margin_y := maxf(8.0, (lower_h - total_btn_h) / float(count + 1))

	var start_x := (size.x - btn_w) * 0.5

	for i in count:
		var y := mid + margin_y + float(i) * (btn_h + margin_y)
		rects.append(Rect2(Vector2(start_x, y), Vector2(btn_w, btn_h)))

	return rects


func _get_flag_rects(size: Vector2) -> Dictionary:
	var flag_w := 36.0
	var flag_h := 24.0
	var spacing := 10.0
	var margin_right := 24.0
	var margin_top := 20.0

	var uk_x := size.x - margin_right - flag_w
	var tr_x := uk_x - spacing - flag_w
	var flag_y := margin_top

	return {
		"TR": Rect2(Vector2(tr_x, flag_y), Vector2(flag_w, flag_h)),
		"UK": Rect2(Vector2(uk_x, flag_y), Vector2(flag_w, flag_h))
	}


func _draw() -> void:
	var size := get_viewport_rect().size
	var mid := size.y * 0.5

	# Sky gradient background
	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, mid), Vector2(0, mid)]),
		PackedColorArray([Color("4a90d9"), Color("4a90d9"), Color("bfe3f5"), Color("bfe3f5")])
	)

	# Sun
	var sun_pos := Vector2(size.x * 0.82, mid * 0.25)
	var sun_r := mid * 0.1
	var sun_col := Color("fff2a8")
	draw_circle(sun_pos, sun_r * 1.5, Color(sun_col, 0.25))
	draw_circle(sun_pos, sun_r, sun_col)

	# Hills & Grass above horizon
	_draw_wave(size.x, mid, mid * 0.72, mid * 0.08, 1.3, 0.0, Color("7fae6a"))
	_draw_wave(size.x, mid, mid * 0.82, mid * 0.06, 2.1, 1.7, Color("5e9a4c"))
	draw_rect(Rect2(0, mid * 0.94, size.x, mid * 0.06), Color("4f8a3c"))

	# Deep soil gradient background
	draw_polygon(
		PackedVector2Array([Vector2(0, mid), Vector2(size.x, mid), size, Vector2(0, size.y)]),
		PackedColorArray([Color("4a2d18"), Color("4a2d18"), Color("170a04"), Color("170a04")])
	)

	# Subtle horizon divider line
	draw_line(Vector2(0, mid), Vector2(size.x, mid), Color(0.0, 0.0, 0.0, 0.35), 2.0)

	_draw_language_switcher(size)

	if not _vt323_font:
		return

	# Title "ExtendoRoot" on top (using Extendoroot.png logo if available)
	var title_y := mid * 0.52
	if _title_logo_tex:
		# Crop tightly to the logo's content region in Extendoroot.png (618x137)
		var src_rect := Rect2(101.0, 80.0, 618.0, 137.0)
		var logo_aspect := src_rect.size.x / src_rect.size.y # ~4.51
		var target_h := minf(mid * 0.45, 96.0)
		var target_w := target_h * logo_aspect
		if target_w > size.x * 0.85:
			target_w = size.x * 0.85
			target_h = target_w / logo_aspect
		var logo_center_y := mid * 0.44
		var dst_rect := Rect2((size.x - target_w) * 0.5, logo_center_y - target_h * 0.5, target_w, target_h)
		# Subtle drop shadow behind the logo
		draw_texture_rect_region(_title_logo_tex, Rect2(dst_rect.position + Vector2(0.0, 3.0), dst_rect.size), src_rect, Color(0.0, 0.0, 0.0, 0.6))
		draw_texture_rect_region(_title_logo_tex, dst_rect, src_rect)
		title_y = dst_rect.position.y + dst_rect.size.y + 4.0
	else:
		var title_text := "ExtendoRoot"
		var title_size := 72
		# Drop shadow
		draw_string(_vt323_font, Vector2(0.0, title_y + 3.0), title_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, title_size, TITLE_SHADOW)
		draw_string(_vt323_font, Vector2(0.0, title_y), title_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, title_size, TITLE_COLOR)

	# Subtitle / tagline or Submenu breadcrumb
	var tag_size := 24
	var tag_text := ""
	if _menu_state == MenuState.MAIN:
		tag_text = "GROW ROOTS & SAVE THE AIR" if _current_language == Language.EN else "KÖKLERİ BÜYÜT & HAVAYI KURTAR"
	else:
		tag_text = "-- SELECT DIFFICULTY --" if _current_language == Language.EN else "-- ZORLUK SEÇİN --"
	var tag_y := title_y + (18.0 if _title_logo_tex else 36.0)
	draw_string(_vt323_font, Vector2(0.0, tag_y), tag_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, tag_size, Color("bfe3f5"))

	# Button stack
	var buttons := _get_current_buttons()
	var rects := _get_button_rects(size)
	var border_w := 2.0

	for i in buttons.size():
		var rect := rects[i]
		var btn_info: Dictionary = buttons[i]
		var is_active: bool = btn_info["active"]
		var is_focused := (_focus_area == FocusArea.BUTTONS and i == _hovered_btn_idx and is_active)

		# Outer border / drop shadow
		draw_rect(
			Rect2(rect.position - Vector2(border_w, border_w), rect.size + Vector2(border_w * 2.0, border_w * 2.0)),
			Color(0.0, 0.0, 0.0, 0.75)
		)

		# Background
		var bg_color := BTN_HOVER_BG if is_focused else (BTN_NORMAL_BG if is_active else BTN_PASSIVE_BG)
		draw_rect(rect, bg_color)

		# Outline (thick white outline for focused button or selected difficulty)
		var is_selected_diff := false
		if _menu_state == MenuState.DIFFICULTY:
			if btn_info["id"] == "diff_easy" and _selected_difficulty == DifficultyLevel.EASY:
				is_selected_diff = true
			elif btn_info["id"] == "diff_medium" and _selected_difficulty == DifficultyLevel.MEDIUM:
				is_selected_diff = true
			elif btn_info["id"] == "diff_hard" and _selected_difficulty == DifficultyLevel.HARD:
				is_selected_diff = true

		var outline_color: Color
		var outline_thickness: float = 1.0

		if is_focused or is_selected_diff:
			outline_color = Color.WHITE
			outline_thickness = 2.5
		elif is_active:
			outline_color = Color(1.0, 1.0, 1.0, 0.35)
			outline_thickness = 1.0
		else:
			outline_color = Color(1.0, 1.0, 1.0, 0.12)
			outline_thickness = 1.0

		draw_rect(rect, outline_color, false, outline_thickness)

		# Text
		var text_color: Color
		if is_focused or is_selected_diff:
			text_color = Color.WHITE
		elif is_active:
			text_color = Color(0.85, 0.85, 0.85, 0.95)
		else:
			text_color = BTN_PASSIVE_TEXT

		var label: String = btn_info["text_tr"] if _current_language == Language.TR else btn_info["text_en"]
		if is_selected_diff:
			label = "> " + label + " <"
		var text_y := rect.position.y + rect.size.y * 0.70
		draw_string(_vt323_font, Vector2(rect.position.x, text_y), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 30, text_color)


func _draw_language_switcher(size: Vector2) -> void:
	var flags := _get_flag_rects(size)
	var tr_rect: Rect2 = flags["TR"]
	var uk_rect: Rect2 = flags["UK"]

	# Container bounding box for the switcher
	var container_pos := tr_rect.position - Vector2(10.0, 6.0)
	var container_size := Vector2(uk_rect.end.x - tr_rect.position.x + 20.0, tr_rect.size.y + 12.0)

	# Container drop shadow & dark backdrop
	draw_rect(Rect2(container_pos - Vector2(2.0, 2.0), container_size + Vector2(4.0, 4.0)), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(container_pos, container_size), Color(0.12, 0.12, 0.12, 0.85))
	draw_rect(Rect2(container_pos, container_size), Color(1.0, 1.0, 1.0, 0.20), false, 1.0)

	var is_uk_focused := (_focus_area == FocusArea.LANG_UK or _mouse_hovered_lang == "UK")
	var is_tr_focused := (_focus_area == FocusArea.LANG_TR or _mouse_hovered_lang == "TR")

	# Draw UK Flag (English)
	_draw_single_flag(uk_rect, _uk_flag_tex, Rect2(72, 72, 433, 290), _current_language == Language.EN, is_uk_focused)

	# Draw TR Flag (Turkish)
	_draw_single_flag(tr_rect, _tr_flag_tex, Rect2(17, 182, 990, 660), _current_language == Language.TR, is_tr_focused)


func _draw_single_flag(rect: Rect2, tex: Texture2D, src_rect: Rect2, is_selected: bool, is_hovered: bool) -> void:
	var border_w := 2.0

	# Flag shadow
	draw_rect(Rect2(rect.position - Vector2(1.0, 1.0), rect.size + Vector2(2.0, 2.0)), Color(0, 0, 0, 0.8))

	# Flag Texture clipped to its exact visual flag aspect ratio
	if tex:
		var modulate_col := Color.WHITE if (is_selected or is_hovered) else Color(0.75, 0.75, 0.75, 0.75)
		draw_texture_rect_region(tex, rect, src_rect, modulate_col)
	else:
		draw_rect(rect, Color.DARK_GRAY)

	# Selection highlight / frame (thick white frame for selected/focused flag)
	if is_selected or is_hovered:
		var frame_w := 2.5
		draw_rect(Rect2(rect.position - Vector2(frame_w, frame_w), rect.size + Vector2(frame_w * 2.0, frame_w * 2.0)), Color.WHITE, false, frame_w)
	else:
		draw_rect(rect, Color(0.0, 0.0, 0.0, 0.4), false, 1.0)


func _draw_wave(width: float, bottom: float, base_y: float, amp: float, freq: float, phase: float, color: Color) -> void:
	var pts := PackedVector2Array()
	var steps := 48
	for i in steps + 1:
		var x := width * i / steps
		pts.append(Vector2(x, base_y - sin(x / width * TAU * freq + phase) * amp))
	pts.append(Vector2(width, bottom))
	pts.append(Vector2(0, bottom))
	draw_colored_polygon(pts, color)


func _gui_input(event: InputEvent) -> void:
	_handle_input_event(event)


func _unhandled_input(event: InputEvent) -> void:
	_handle_input_event(event)


func _handle_input_event(event: InputEvent) -> void:
	var size := get_viewport_rect().size
	var rects := _get_button_rects(size)
	var flag_rects := _get_flag_rects(size)
	var buttons := _get_current_buttons()

	if event is InputEventMouseMotion:
		var prev_hovered := _hovered_btn_idx
		var prev_focus := _focus_area
		var prev_mouse_lang := _mouse_hovered_lang

		var hovered_any := false
		for i in rects.size():
			if rects[i].has_point(event.position):
				_hovered_btn_idx = i
				_focus_area = FocusArea.BUTTONS
				hovered_any = true
				break

		_mouse_hovered_lang = ""
		if flag_rects["TR"].has_point(event.position):
			_mouse_hovered_lang = "TR"
			_focus_area = FocusArea.LANG_TR
			hovered_any = true
		elif flag_rects["UK"].has_point(event.position):
			_mouse_hovered_lang = "UK"
			_focus_area = FocusArea.LANG_UK
			hovered_any = true

		if prev_hovered != _hovered_btn_idx or prev_focus != _focus_area or prev_mouse_lang != _mouse_hovered_lang:
			queue_redraw()

	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Check flag clicks
			if flag_rects["TR"].has_point(event.position):
				_current_language = Language.TR
				if GameSettings:
					GameSettings.language = GameSettings.Language.TR
				_focus_area = FocusArea.LANG_TR
				queue_redraw()
				return
			elif flag_rects["UK"].has_point(event.position):
				_current_language = Language.EN
				if GameSettings:
					GameSettings.language = GameSettings.Language.EN
				_focus_area = FocusArea.LANG_UK
				queue_redraw()
				return

			for i in rects.size():
				if rects[i].has_point(event.position):
					_focus_area = FocusArea.BUTTONS
					_hovered_btn_idx = i
					_on_button_clicked(i)
					break

	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if _menu_state == MenuState.DIFFICULTY:
				# Return to main menu
				_menu_state = MenuState.MAIN
				_focus_area = FocusArea.BUTTONS
				_hovered_btn_idx = 1 # Back onto Difficulty button
				queue_redraw()
			elif _focus_area != FocusArea.BUTTONS:
				# Return focus to main buttons
				_focus_area = FocusArea.BUTTONS
				queue_redraw()
			else:
				var mode := DisplayServer.window_get_mode()
				if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				else:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

		elif event.keycode == KEY_UP or event.keycode == KEY_W:
			_navigate_vertical(-1)

		elif event.keycode == KEY_DOWN or event.keycode == KEY_S:
			_navigate_vertical(1)

		elif event.keycode == KEY_LEFT or event.keycode == KEY_A:
			_navigate_horizontal(-1)

		elif event.keycode == KEY_RIGHT or event.keycode == KEY_D:
			_navigate_horizontal(1)

		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE:
			_trigger_selection()


func _navigate_vertical(direction: int) -> void:
	if _focus_area == FocusArea.LANG_TR or _focus_area == FocusArea.LANG_UK:
		if direction > 0:
			# Jump from language switcher down to buttons
			_focus_area = FocusArea.BUTTONS
			_hovered_btn_idx = 0
			queue_redraw()
		return

	# Inside buttons
	var buttons := _get_current_buttons()
	if buttons.is_empty():
		return

	var count := buttons.size()
	if direction < 0 and _hovered_btn_idx == 0:
		# Going up from first button enters language selector
		if _current_language == Language.TR:
			_focus_area = FocusArea.LANG_TR
		else:
			_focus_area = FocusArea.LANG_UK
		queue_redraw()
		return

	var next_idx := _hovered_btn_idx
	for step in count:
		next_idx = (next_idx + direction + count) % count
		if buttons[next_idx]["active"]:
			_hovered_btn_idx = next_idx
			_focus_area = FocusArea.BUTTONS
			queue_redraw()
			return


func _navigate_horizontal(direction: int) -> void:
	if _focus_area == FocusArea.LANG_TR and direction > 0:
		_focus_area = FocusArea.LANG_UK
		queue_redraw()
	elif _focus_area == FocusArea.LANG_UK and direction < 0:
		_focus_area = FocusArea.LANG_TR
		queue_redraw()


func _trigger_selection() -> void:
	if _focus_area == FocusArea.LANG_TR:
		_current_language = Language.TR
		if GameSettings:
			GameSettings.language = GameSettings.Language.TR
		queue_redraw()
		return
	elif _focus_area == FocusArea.LANG_UK:
		_current_language = Language.EN
		if GameSettings:
			GameSettings.language = GameSettings.Language.EN
		queue_redraw()
		return

	var buttons := _get_current_buttons()
	if _hovered_btn_idx >= 0 and _hovered_btn_idx < buttons.size():
		_on_button_clicked(_hovered_btn_idx)


func _on_button_clicked(idx: int) -> void:
	var buttons := _get_current_buttons()
	if idx < 0 or idx >= buttons.size():
		return

	var btn_info: Dictionary = buttons[idx]
	if not btn_info["active"]:
		return

	var id: String = btn_info["id"]

	if _menu_state == MenuState.MAIN:
		if id == "play":
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		elif id == "difficulty":
			_menu_state = MenuState.DIFFICULTY
			_focus_area = FocusArea.BUTTONS
			match _selected_difficulty:
				DifficultyLevel.EASY:
					_hovered_btn_idx = 0
				DifficultyLevel.MEDIUM:
					_hovered_btn_idx = 1
				DifficultyLevel.HARD:
					_hovered_btn_idx = 2
			queue_redraw()

	elif _menu_state == MenuState.DIFFICULTY:
		if id == "diff_easy":
			_selected_difficulty = DifficultyLevel.EASY
			if GameSettings:
				GameSettings.difficulty = GameSettings.Difficulty.EASY
			queue_redraw()
		elif id == "diff_medium":
			_selected_difficulty = DifficultyLevel.MEDIUM
			if GameSettings:
				GameSettings.difficulty = GameSettings.Difficulty.MEDIUM
			queue_redraw()
		elif id == "diff_hard":
			_selected_difficulty = DifficultyLevel.HARD
			if GameSettings:
				GameSettings.difficulty = GameSettings.Difficulty.HARD
			queue_redraw()
		elif id == "back":
			_menu_state = MenuState.MAIN
			_focus_area = FocusArea.BUTTONS
			_hovered_btn_idx = 1 # Back onto Difficulty button
			queue_redraw()
