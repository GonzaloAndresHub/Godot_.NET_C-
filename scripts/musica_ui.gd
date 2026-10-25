extends Control

# ============================================================
#  CLASES AUXILIARES (visualizador y botón play)
# ============================================================

class Visualizer extends Control:
	var spectrum: AudioEffectSpectrumAnalyzerInstance
	var active: bool = false
	var bars: int = 72
	var bar_color := Color.WHITE
	var levels := PackedFloat32Array()

	func _ready() -> void:
		levels.resize(bars)

	func _process(delta: float) -> void:
		for i in bars:
			var target := 0.03
			if active and spectrum != null:
				var t0 := float(i) / bars
				var t1 := float(i + 1) / bars
				var f0 := 40.0 * pow(300.0, t0)
				var f1 := 40.0 * pow(300.0, t1)
				var mag := spectrum.get_magnitude_for_frequency_range(f0, f1).length()
				var db := linear_to_db(mag + 0.000001)
				target = clampf((db + 62.0 + t0 * 14.0) / 62.0, 0.03, 1.0)
			var speed := 22.0 if target > levels[i] else 7.0
			levels[i] = lerpf(levels[i], target, 1.0 - exp(-speed * delta))
		queue_redraw()

	func _draw() -> void:
		var step := size.x / bars
		var cy := size.y * 0.5
		for i in bars:
			var env := sin(PI * (i + 0.5) / bars)
			var lv := levels[i]
			var h := maxf(1.5, lv * cy * (0.3 + 0.7 * env))
			var x := (i + 0.5) * step
			# resplandor ancho y tenue + barra nítida encima
			draw_line(Vector2(x, cy - h), Vector2(x, cy + h), Color(bar_color, 0.18 + 0.2 * lv), step * 1.3)
			draw_line(Vector2(x, cy - h), Vector2(x, cy + h), Color(bar_color, 0.55 + 0.45 * lv), step * 0.45)


class PlayIcon extends Control:
	var active: bool = false
	var fill_on := Color("#f4f6f8")
	var fill_off := Color("#c9d0d6")
	var ring := Color("#8d97a1")
	var symbol := Color("#56626e")

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 1.0
		draw_circle(c, r, fill_on if active else fill_off)
		draw_arc(c, r, 0.0, TAU, 32, ring, 2.0, true)
		draw_arc(c, r - 3.0, 0.0, TAU, 32, Color(1, 1, 1, 0.5), 1.5, true)
		var tri := PackedVector2Array([
			c + Vector2(-r * 0.25, -r * 0.45),
			c + Vector2(-r * 0.25, r * 0.45),
			c + Vector2(r * 0.5, 0.0)
		])
		draw_colored_polygon(tri, symbol)


# ============================================================
#  AJUSTES (se cambian en el Inspector)
# ============================================================

@export_group("Música")
@export_dir var music_folder: String = "res://assets/music"
@export var autoplay_on_start: bool = true
@export var start_volume_db: float = -8.0

@export_group("Panel")
@export_enum("Plata F1", "Carbono Neón", "Rojo Racing", "Azul Hielo") var theme_preset: int = 1
@export var panel_width: float = 600.0
@export var ui_scale: float = 0.75
@export var margin: float = 20.0
@export var dock_right: bool = false
@export var auto_hide_seconds: float = 8.0
@export var visible_rows: int = 5
@export var cover: Texture2D
@export var ui_font: Font

const BUS_NAME := "Musica"
const SAVE_PATH := "user://musica.cfg"
const PAD := 14.0
const HEADER_H := 120.0
const ROW_H := 40.0
const ROW_GAP := 6.0

# Colores (los rellena _apply_theme)
var c_panel: Color
var c_panel_border: Color
var c_header: Color
var c_header_border: Color
var c_row: Color
var c_row_border: Color
var c_row_play: Color
var c_row_sel: Color
var c_row_play_sel: Color
var c_select: Color
var c_text: Color
var c_hint: Color
var c_accent: Color
var c_ph: Color
var c_ph_border: Color
var c_scroll_bg: Color
var c_scroll_thumb: Color

# ============================================================
#  ESTADO
# ============================================================

var tracks: Array[Dictionary] = []
var selected: int = 0
var playing_index: int = -1
var scroll_offset: int = 0
var panel_open: bool = false
var is_paused: bool = false
var paused_pos: float = 0.0
var panel_size := Vector2.ZERO

var player: AudioStreamPlayer
var spectrum: AudioEffectSpectrumAnalyzerInstance

var panel: Panel
var title_label: Label
var time_label: Label
var hint_label: Label
var visualizer: Visualizer
var header_icon: PlayIcon
var scroll_track: Panel
var scroll_thumb: Panel
var rows: Array[Dictionary] = []
var styles := {}
var hide_timer: Timer
var tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_apply_theme()
	_scan_tracks()
	_setup_audio()
	_build_ui()
	_load_settings()
	_select(selected)

	hide_timer = Timer.new()
	hide_timer.one_shot = true
	hide_timer.timeout.connect(hide_panel)
	add_child(hide_timer)

	get_viewport().size_changed.connect(_snap_panel)

	await get_tree().process_frame
	if autoplay_on_start and not tracks.is_empty():
		play_track(selected)
	show_panel()


# ============================================================
#  TEMAS
# ============================================================

func _theme_data(id: int) -> Dictionary:
	match id:
		0: # Plata F1
			return {
				"panel": "#d9dee3", "panel_border": "#aab2ba", "header": "#e4e8ec",
				"header_border": "#b9c0c7", "row": "#d2d8de", "row_border": "#a7afb8",
				"row_play": "#b6bfc8", "row_sel": "#eef1f4", "row_play_sel": "#c9d1d9",
				"select": "#e10600", "text": "#2b3440", "hint": "#6b7681",
				"accent": "#e10600", "ph": "#aeb6be", "ph_border": "#8d97a1",
				"scroll_bg": "#c3cad1", "scroll_thumb": "#8d97a1"
			}
		1: # Carbono Neón
			return {
				"panel": "#12161c", "panel_border": "#2b3440", "header": "#0b0e13",
				"header_border": "#1f2833", "row": "#1a2029", "row_border": "#2c3643",
				"row_play": "#1d2b36", "row_sel": "#222c38", "row_play_sel": "#14303a",
				"select": "#00e5ff", "text": "#e8eef5", "hint": "#7f8c99",
				"accent": "#00e5ff", "ph": "#232c36", "ph_border": "#3a4654",
				"scroll_bg": "#1a2029", "scroll_thumb": "#00e5ff"
			}
		2: # Rojo Racing
			return {
				"panel": "#1a0d0f", "panel_border": "#4a1a1f", "header": "#120709",
				"header_border": "#5c2027", "row": "#261215", "row_border": "#4a1f25",
				"row_play": "#35171b", "row_sel": "#3a1a20", "row_play_sel": "#4a1f26",
				"select": "#ff2d3d", "text": "#f5e9ea", "hint": "#a08488",
				"accent": "#ff2d3d", "ph": "#3a1a20", "ph_border": "#6b2a32",
				"scroll_bg": "#261215", "scroll_thumb": "#ff2d3d"
			}
		_: # Azul Hielo
			return {
				"panel": "#dfe9f3", "panel_border": "#9fb4c8", "header": "#eaf2fa",
				"header_border": "#aec3d6", "row": "#d3e0ec", "row_border": "#9fb4c8",
				"row_play": "#bcd0e2", "row_sel": "#f2f8fd", "row_play_sel": "#c7dcef",
				"select": "#0a84ff", "text": "#1c2b3a", "hint": "#5d7186",
				"accent": "#0a84ff", "ph": "#b4c7d8", "ph_border": "#8aa2b8",
				"scroll_bg": "#c3d2e0", "scroll_thumb": "#0a84ff"
			}


func _apply_theme() -> void:
	var t := _theme_data(theme_preset)
	c_panel = Color(t["panel"])
	c_panel_border = Color(t["panel_border"])
	c_header = Color(t["header"])
	c_header_border = Color(t["header_border"])
	c_row = Color(t["row"])
	c_row_border = Color(t["row_border"])
	c_row_play = Color(t["row_play"])
	c_row_sel = Color(t["row_sel"])
	c_row_play_sel = Color(t["row_play_sel"])
	c_select = Color(t["select"])
	c_text = Color(t["text"])
	c_hint = Color(t["hint"])
	c_accent = Color(t["accent"])
	c_ph = Color(t["ph"])
	c_ph_border = Color(t["ph_border"])
	c_scroll_bg = Color(t["scroll_bg"])
	c_scroll_thumb = Color(t["scroll_thumb"])


# ============================================================
#  CANCIONES Y AUDIO
# ============================================================

func _scan_tracks() -> void:
	var dir := DirAccess.open(music_folder)
	if dir == null:
		push_warning("MusicaUI: no se pudo abrir la carpeta " + music_folder)
		return

	var files: Array[String] = []
	for f in dir.get_files():
		var fname := f
		if fname.ends_with(".import"):
			fname = fname.trim_suffix(".import")
		if fname.get_extension().to_lower() in ["mp3", "ogg", "wav"]:
			if not files.has(fname):
				files.append(fname)
	files.sort()

	for fname in files:
		var stream = load(music_folder.path_join(fname))
		if stream is AudioStream:
			var base := fname.get_basename()
			var title := base
			var artist := ""
			if " - " in base:
				var parts := base.split(" - ", true, 1)
				title = parts[0].strip_edges()
				artist = parts[1].strip_edges()
			tracks.append({
				"file": fname,
				"title": title,
				"artist": artist,
				"display": title if artist == "" else "%s - %s" % [title, artist],
				"stream": stream,
				"length": stream.get_length()
			})

	if tracks.is_empty():
		push_warning("MusicaUI: no hay canciones en " + music_folder)


func _setup_audio() -> void:
	var bus_idx := AudioServer.get_bus_index(BUS_NAME)
	if bus_idx == -1:
		AudioServer.add_bus()
		bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_idx, BUS_NAME)
		AudioServer.set_bus_send(bus_idx, "Master")
		var fx := AudioEffectSpectrumAnalyzer.new()
		fx.buffer_length = 0.2
		fx.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048
		AudioServer.add_bus_effect(bus_idx, fx)
	spectrum = AudioServer.get_bus_effect_instance(bus_idx, 0) as AudioEffectSpectrumAnalyzerInstance

	player = AudioStreamPlayer.new()
	player.bus = BUS_NAME
	player.volume_db = start_volume_db
	player.finished.connect(_on_track_finished)
	add_child(player)


func play_track(idx: int) -> void:
	if tracks.is_empty():
		return
	playing_index = wrapi(idx, 0, tracks.size())
	is_paused = false
	player.stream = tracks[playing_index].stream
	player.play()
	_save_settings()
	_refresh_all()


func toggle_pause() -> void:
	if tracks.is_empty():
		return
	if playing_index < 0:
		play_track(selected)
		return
	if is_paused:
		is_paused = false
		player.play(paused_pos)
	else:
		paused_pos = player.get_playback_position()
		is_paused = true
		player.stop()
	_refresh_all()


func _on_track_finished() -> void:
	play_track(playing_index + 1)
	_select(playing_index)
	show_panel()


# ============================================================
#  CONSTRUCCIÓN DE LA INTERFAZ
# ============================================================

func _flat(bg: Color, border: Color, radius: int = 12, border_w: int = 2, shadow: int = 0, glow: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	if glow.a > 0.0:
		sb.shadow_size = 12
		sb.shadow_color = glow
		sb.shadow_offset = Vector2.ZERO
	elif shadow > 0:
		sb.shadow_size = shadow
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_offset = Vector2(0, 3)
	return sb


# Franja de luz en la mitad superior (efecto cristal)
func _gloss(parent: Control, w: float, h: float, radius: int, alpha: float = 0.10) -> void:
	var g := Panel.new()
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, alpha)
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	g.add_theme_stylebox_override("panel", sb)
	parent.add_child(g)
	g.position = Vector2(2, 2)
	g.size = Vector2(w - 4, h * 0.45)


func _place(c: Control, pos: Vector2, sz: Vector2) -> void:
	c.position = pos
	c.size = sz


func _make_label(parent: Control, text: String, font_size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if ui_font:
		l.add_theme_font_override("font", ui_font)
	parent.add_child(l)
	return l


func _style_icon(ic: PlayIcon) -> void:
	ic.fill_on = c_accent
	ic.fill_off = c_row_border
	ic.ring = c_accent.darkened(0.25)
	ic.symbol = c_panel.darkened(0.3) if c_panel.get_luminance() < 0.5 else Color("#56626e")


func _build_ui() -> void:
	var list_h := visible_rows * ROW_H + (visible_rows - 1) * ROW_GAP
	panel_size = Vector2(panel_width, PAD + HEADER_H + 10.0 + list_h + 8.0 + 18.0 + 10.0)
	var inner_w := panel_width - PAD * 2.0
	var row_w := inner_w - 14.0

	styles = {
		"normal": _flat(c_row, c_row_border, 10, 2),
		"selected": _flat(c_row_sel, c_accent, 10, 3, 0, Color(c_accent, 0.55)),
		"playing": _flat(c_row_play, c_row_border, 10, 2),
		"both": _flat(c_row_play_sel, c_accent, 10, 3, 0, Color(c_accent, 0.55)),
	}

	# --- Panel principal ---
	panel = Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _flat(c_panel, c_panel_border, 20, 2, 0, Color(c_accent, 0.25)))
	panel.size = panel_size
	panel.scale = Vector2.ONE * ui_scale
	add_child(panel)
	_snap_panel()

	# --- Cabecera ---
	var header := Panel.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_stylebox_override("panel", _flat(c_header, c_header_border, 14, 2))
	panel.add_child(header)
	_place(header, Vector2(PAD, PAD), Vector2(inner_w, HEADER_H))
	_gloss(header, inner_w, HEADER_H, 14, 0.08)

	if cover:
		var tr := TextureRect.new()
		tr.texture = cover
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_child(tr)
		_place(tr, Vector2(12, 12), Vector2(96, 96))
	else:
		var ph := Panel.new()
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ph.add_theme_stylebox_override("panel", _flat(c_ph, c_ph_border, 8, 2))
		header.add_child(ph)
		_place(ph, Vector2(12, 12), Vector2(96, 96))

	title_label = _make_label(header, "", 18, c_text)
	_place(title_label, Vector2(124, 10), Vector2(inner_w - 124 - 126, 28))

	time_label = _make_label(header, "0:00 / 0:00", 18, c_text, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(time_label, Vector2(inner_w - 12 - 114, 10), Vector2(114, 28))

	visualizer = Visualizer.new()
	visualizer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visualizer.spectrum = spectrum
	visualizer.bar_color = c_accent
	header.add_child(visualizer)
	_place(visualizer, Vector2(124, 44), Vector2(inner_w - 124 - 60, 66))

	header_icon = PlayIcon.new()
	header_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_icon(header_icon)
	header.add_child(header_icon)
	_place(header_icon, Vector2(inner_w - 12 - 34, HEADER_H - 12 - 34), Vector2(34, 34))

	# --- Lista de canciones ---
	var list := Control.new()
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(list)
	_place(list, Vector2(PAD, PAD + HEADER_H + 10.0), Vector2(inner_w, list_h))

	for i in visible_rows:
		var rp := Panel.new()
		rp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rp.add_theme_stylebox_override("panel", styles["normal"])
		list.add_child(rp)
		_place(rp, Vector2(0, i * (ROW_H + ROW_GAP)), Vector2(row_w, ROW_H))
		_gloss(rp, row_w, ROW_H, 10, 0.07)

		var name_l := _make_label(rp, "", 18, c_text)
		_place(name_l, Vector2(16, 0), Vector2(row_w - 190, ROW_H))

		var time_l := _make_label(rp, "", 18, c_text, HORIZONTAL_ALIGNMENT_RIGHT)
		_place(time_l, Vector2(row_w - 160, 0), Vector2(110, ROW_H))

		var ic := PlayIcon.new()
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_style_icon(ic)
		rp.add_child(ic)
		_place(ic, Vector2(row_w - 42, (ROW_H - 30.0) / 2.0), Vector2(30, 30))

		rows.append({"panel": rp, "title": name_l, "time": time_l, "icon": ic})

	# --- Barra de scroll ---
	scroll_track = Panel.new()
	scroll_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll_track.add_theme_stylebox_override("panel", _flat(c_scroll_bg, c_scroll_bg, 3, 0))
	list.add_child(scroll_track)
	_place(scroll_track, Vector2(inner_w - 6, 0), Vector2(5, list_h))

	scroll_thumb = Panel.new()
	scroll_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll_thumb.add_theme_stylebox_override("panel", _flat(c_scroll_thumb, c_scroll_thumb, 3, 0))
	scroll_track.add_child(scroll_thumb)

	# --- Línea de ayuda ---
	hint_label = _make_label(panel, "", 12, c_hint, HORIZONTAL_ALIGNMENT_CENTER)
	_place(hint_label, Vector2(PAD, PAD + HEADER_H + 10.0 + list_h + 8.0), Vector2(inner_w, 18))


# ============================================================
#  ACTUALIZAR LO QUE SE VE
# ============================================================

func _fmt(sec: float) -> String:
	var s := int(round(sec))
	var m := int(s / 60.0)
	return "%d:%02d" % [m, s % 60]


func _fmt_row(sec: float) -> String:
	var s := int(round(sec))
	var m := int(s / 60.0)
	return "%02d:%02d" % [m, s % 60]


func _refresh_all() -> void:
	if panel == null:
		return
	_refresh_title()
	_refresh_rows()
	_refresh_scrollbar()
	_refresh_hint()


func _refresh_title() -> void:
	if tracks.is_empty():
		title_label.text = "SIN CANCIONES"
		return
	if playing_index < 0:
		title_label.text = "PRESIONA ENTER PARA REPRODUCIR"
		return
	var t := tracks[playing_index]
	if t.artist == "":
		title_label.text = str(t.title).to_upper()
	else:
		title_label.text = "%s  -  ARTIST: %s" % [str(t.title).to_upper(), str(t.artist).to_upper()]
	header_icon.active = not is_paused
	header_icon.queue_redraw()


func _refresh_rows() -> void:
	for i in visible_rows:
		var r: Dictionary = rows[i]
		var idx := scroll_offset + i
		if idx >= tracks.size():
			r.panel.visible = false
			continue
		r.panel.visible = true

		var t := tracks[idx]
		var is_sel := idx == selected
		var is_play := idx == playing_index

		var key := "normal"
		if is_sel and is_play:
			key = "both"
		elif is_sel:
			key = "selected"
		elif is_play:
			key = "playing"
		r.panel.add_theme_stylebox_override("panel", styles[key])

		r.title.text = "%d.  %s" % [idx + 1, t.display]

		if is_play:
			r.time.text = "Pausa" if is_paused else "Playing"
			r.time.add_theme_color_override("font_color", c_accent)
		else:
			r.time.text = _fmt_row(t.length)
			r.time.add_theme_color_override("font_color", c_text)

		r.icon.active = is_play and not is_paused
		r.icon.queue_redraw()


func _refresh_scrollbar() -> void:
	var need := tracks.size() > visible_rows
	scroll_track.visible = need
	if not need:
		return
	var h := scroll_track.size.y
	var th := maxf(20.0, h * float(visible_rows) / tracks.size())
	var max_off := tracks.size() - visible_rows
	scroll_thumb.size = Vector2(5, th)
	scroll_thumb.position = Vector2(0, (h - th) * float(scroll_offset) / max_off)


func _refresh_hint() -> void:
	if tracks.is_empty():
		hint_label.text = "Agrega .mp3 / .ogg a " + music_folder
		return
	var vol := int(round(db_to_linear(player.volume_db) * 100.0))
	hint_label.text = "Arriba/Abajo elegir  |  Enter reproducir  |  P pausa  |  Izq/Der vol %d%%  |  M ocultar" % vol


func _process(_delta: float) -> void:
	if player == null or visualizer == null:
		return
	visualizer.active = player.playing and not is_paused
	if playing_index >= 0:
		var pos := paused_pos if is_paused else player.get_playback_position()
		time_label.text = "%s / %s" % [_fmt(pos), _fmt(tracks[playing_index].length)]
	else:
		time_label.text = "0:00 / 0:00"


# ============================================================
#  MOSTRAR / OCULTAR PANEL
# ============================================================

func _shown_x() -> float:
	var vw := get_viewport_rect().size.x
	if dock_right:
		return vw - panel_size.x * ui_scale - margin
	return margin


func _hidden_x() -> float:
	var vw := get_viewport_rect().size.x
	if dock_right:
		return vw + 40.0
	return -panel_size.x * ui_scale - 40.0


func _snap_panel() -> void:
	if panel == null:
		return
	var y := get_viewport_rect().size.y - panel_size.y * ui_scale - margin
	panel.position = Vector2(_shown_x() if panel_open else _hidden_x(), y)


func _tween_to(x: float) -> void:
	if tween:
		tween.kill()
	tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "position:x", x, 0.35)


func show_panel() -> void:
	panel_open = true
	_snap_panel_y()
	_tween_to(_shown_x())
	_restart_hide_timer()


func hide_panel() -> void:
	panel_open = false
	_tween_to(_hidden_x())


func _snap_panel_y() -> void:
	panel.position.y = get_viewport_rect().size.y - panel_size.y * ui_scale - margin


func _restart_hide_timer() -> void:
	if auto_hide_seconds > 0.0:
		hide_timer.start(auto_hide_seconds)


# ============================================================
#  TECLADO
# ============================================================

func _select(idx: int) -> void:
	if tracks.is_empty():
		_refresh_all()
		return
	selected = wrapi(idx, 0, tracks.size())
	if selected < scroll_offset:
		scroll_offset = selected
	elif selected >= scroll_offset + visible_rows:
		scroll_offset = selected - visible_rows + 1
	_refresh_all()


func _change_volume(delta_db: float) -> void:
	player.volume_db = clampf(player.volume_db + delta_db, -40.0, 0.0)
	_save_settings()
	_refresh_hint()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return

	if key.keycode == KEY_M and not key.echo:
		if panel_open:
			hide_panel()
		else:
			show_panel()
		get_viewport().set_input_as_handled()
		return

	if not panel_open:
		return

	match key.keycode:
		KEY_UP:
			_select(selected - 1)
		KEY_DOWN:
			_select(selected + 1)
		KEY_ENTER, KEY_KP_ENTER:
			if not key.echo:
				play_track(selected)
		KEY_P:
			if not key.echo:
				toggle_pause()
		KEY_LEFT:
			_change_volume(-2.0)
		KEY_RIGHT:
			_change_volume(2.0)
		_:
			return

	_restart_hide_timer()
	get_viewport().set_input_as_handled()


# ============================================================
#  GUARDAR / CARGAR LA ÚLTIMA ELECCIÓN
# ============================================================

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	if playing_index >= 0:
		cfg.set_value("musica", "ultima", tracks[playing_index].file)
	cfg.set_value("musica", "volumen_db", player.volume_db)
	cfg.save(SAVE_PATH)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	player.volume_db = cfg.get_value("musica", "volumen_db", start_volume_db)
	var last: String = cfg.get_value("musica", "ultima", "")
	for i in tracks.size():
		if tracks[i].file == last:
			selected = i
