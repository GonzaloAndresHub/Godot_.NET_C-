extends Control

# ============================================================
#  CAPA DE DIBUJO SOBRE EL MAPA (recorrido, meta y auto)
# ============================================================

class MapOverlay extends Control:
	var cam: Camera3D
	var ratio: float = 0.5
	var trail_color := Color("#e10600")
	var accent := Color("#e10600")
	var trail := PackedVector3Array()
	var car_pos := Vector3.ZERO
	var car_dir := Vector3(0, 0, 1)
	var start_pos := Vector3.ZERO
	var has_start: bool = false
	var ready_to_draw: bool = false

	func _init() -> void:
		clip_contents = true

	func _pt(p: Vector3) -> Vector2:
		if cam.is_position_behind(p):
			return Vector2(-10000, -10000)
		return cam.unproject_position(p) * ratio

	func _draw() -> void:
		if cam == null or not cam.is_inside_tree() or not ready_to_draw:
			return

		if trail.size() > 1:
			var pts := PackedVector2Array()
			for p in trail:
				pts.append(_pt(p))
			pts.append(_pt(car_pos))
			draw_polyline(pts, Color(1, 1, 1, 0.55), 6.0, true)
			draw_polyline(pts, Color(trail_color, 0.25), 8.0, true)
			draw_polyline(pts, trail_color, 3.0, true)

		if has_start:
			var s := _pt(start_pos)
			draw_circle(s, 7.0, Color.WHITE)
			draw_arc(s, 7.0, 0.0, TAU, 24, accent, 2.5, true)

		var c := _pt(car_pos)
		var d := _pt(car_pos + car_dir * 6.0) - c
		if d.length() < 0.001:
			d = Vector2.UP
		d = d.normalized()
		var n := Vector2(-d.y, d.x)
		var arrow := PackedVector2Array([
			c + d * 11.0,
			c - d * 7.0 + n * 7.0,
			c - d * 3.0,
			c - d * 7.0 - n * 7.0
		])
		draw_circle(c, 14.0, Color(accent, 0.25))
		draw_colored_polygon(arrow, accent)
		var closed := arrow.duplicate()
		closed.append(arrow[0])
		draw_polyline(closed, Color.WHITE, 1.5, true)


# ============================================================
#  AJUSTES (Inspector)
# ============================================================

@export_group("Carrera")
@export var car: VehicleBody3D
@export var total_laps: int = 3
@export var finish_marker: Node3D
@export var far_distance: float = 60.0
@export var finish_radius: float = 15.0
@export var min_lap_distance: float = 150.0

@export_group("Mapa")
@export var map_3d: bool = true
@export var map_tilt_deg: float = 55.0
@export var map_yaw_deg: float = 0.0
@export var map_zoom: float = 1.0
@export_range(1, 3) var map_quality: int = 2
@export var track_mesh: Node3D
@export var use_manual_bounds: bool = false
@export var manual_bounds := Rect2(-500, -500, 1000, 1000)
@export_flags_3d_render var map_cull_mask: int = 1048575
@export var model_faces_plus_z: bool = true
@export var show_trail: bool = true
@export var trail_step: float = 3.0

@export_group("Mapa solo carretera")
@export var only_road: bool = true
@export var road_texture: Texture2D
@export_range(0.0, 1.0) var road_threshold: float = 0.55
@export var map_transparent: bool = true

@export_group("Panel de vueltas (arriba centro)")
@export var lap_scale: float = 0.55
@export var lap_top_margin: float = 20.0
@export var remember_lap_scale: bool = true     # Recuerda el tamaño que dejes con las teclas - y +

@export_group("Panel del mapa (arriba izquierda)")
@export var map_scale: float = 0.8
@export var map_margin: float = 20.0

@export_group("Estilo")
@export_enum("Plata F1", "Carbono Neón", "Rojo Racing", "Azul Hielo") var theme_preset: int = 0
@export var ui_font: Font

const SAVE_PATH := "user://carrera.cfg"
const PAD := 12.0
const MAP_LAYER := 1 << 19   # capa 20: solo la ve la cámara del mapa

const LAP_W := 440.0
const LAP_INNER_H := 100.0

const MAP_W := 400.0
const MAP_INNER_H := 220.0

var pal := {}

# ============================================================
#  ESTADO
# ============================================================

var initialized: bool = false
var start_pos := Vector2.ZERO
var start_y: float = 0.0
var last_pos := Vector2.ZERO
var last_trail_pos := Vector2.ZERO
var armed: bool = false
var path_len: float = 0.0
var race_started: bool = false
var finished: bool = false
var laps_done: int = 0
var lap_time: float = 0.0
var last_lap: float = -1.0
var best_lap: float = -1.0

var lap_panel: Panel
var lap_panel_size := Vector2.ZERO
var map_panel: Panel
var map_panel_size := Vector2.ZERO
var map_vp: SubViewport
var map_cam: Camera3D
var overlay: MapOverlay
var track_box := AABB(Vector3(-500, -5, -500), Vector3(1000, 10, 1000))
var road_copy_built: bool = false
var lap_big: Label
var cur_label: Label
var last_label: Label
var best_label: Label
var banner: Label
var banner_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_saved()
	_apply_theme()
	_build_ui()
	_layout()
	_refresh_laps()
	get_viewport().size_changed.connect(_layout)
	if car == null:
		_find_car()
	await get_tree().process_frame
	_compute_bounds()


# ============================================================
#  TEMAS
# ============================================================

func _theme_data(id: int) -> Dictionary:
	match id:
		0:
			return {
				"panel": "#d9dee3", "panel_border": "#aab2ba", "sec": "#e4e8ec",
				"sec_border": "#b9c0c7", "text": "#2b3440", "hint": "#6b7681",
				"accent": "#e10600", "map_bg": "#c3cad1"
			}
		1:
			return {
				"panel": "#12161c", "panel_border": "#2b3440", "sec": "#0b0e13",
				"sec_border": "#1f2833", "text": "#e8eef5", "hint": "#7f8c99",
				"accent": "#00e5ff", "map_bg": "#0b0e13"
			}
		2:
			return {
				"panel": "#1a0d0f", "panel_border": "#4a1a1f", "sec": "#120709",
				"sec_border": "#5c2027", "text": "#f5e9ea", "hint": "#a08488",
				"accent": "#ff2d3d", "map_bg": "#120709"
			}
		_:
			return {
				"panel": "#dfe9f3", "panel_border": "#9fb4c8", "sec": "#eaf2fa",
				"sec_border": "#aec3d6", "text": "#1c2b3a", "hint": "#5d7186",
				"accent": "#0a84ff", "map_bg": "#c3d2e0"
			}


func _apply_theme() -> void:
	var t := _theme_data(theme_preset)
	for k in t:
		pal[k] = Color(t[k])


# ============================================================
#  CONSTRUCCIÓN DE LA INTERFAZ
# ============================================================

func _flat(bg: Color, border: Color, radius: int = 12, border_w: int = 2, glow: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	if glow.a > 0.0:
		sb.shadow_size = 12
		sb.shadow_color = glow
		sb.shadow_offset = Vector2.ZERO
	return sb


func _gloss(parent: Control, w: float, h: float, radius: int, alpha: float = 0.08) -> void:
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
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if ui_font:
		l.add_theme_font_override("font", ui_font)
	parent.add_child(l)
	return l


func _build_ui() -> void:
	var accent: Color = pal["accent"]
	var txt: Color = pal["text"]
	var hint: Color = pal["hint"]

	_build_lap_panel(accent, txt, hint)
	_build_map_panel(accent)

	banner = _make_label(self, "", 26, accent, HORIZONTAL_ALIGNMENT_CENTER)
	banner.add_theme_stylebox_override("normal", _flat(pal["panel"], accent, 14, 2, Color(accent, 0.35)))
	banner.size = Vector2(520, 56)
	banner.modulate.a = 0.0


func _build_lap_panel(accent: Color, txt: Color, hint: Color) -> void:
	var inner_w := LAP_W - PAD * 2.0
	lap_panel_size = Vector2(LAP_W, PAD * 2.0 + LAP_INNER_H)

	lap_panel = Panel.new()
	lap_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lap_panel.add_theme_stylebox_override("panel", _flat(pal["panel"], pal["panel_border"], 20, 2, Color(accent, 0.25)))
	lap_panel.size = lap_panel_size
	lap_panel.scale = Vector2.ONE * lap_scale
	add_child(lap_panel)

	var sec := Panel.new()
	sec.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sec.add_theme_stylebox_override("panel", _flat(pal["sec"], pal["sec_border"], 14, 2))
	lap_panel.add_child(sec)
	_place(sec, Vector2(PAD, PAD), Vector2(inner_w, LAP_INNER_H))
	_gloss(sec, inner_w, LAP_INNER_H, 14)

	var cap := _make_label(sec, "VUELTA", 12, hint)
	_place(cap, Vector2(18, 8), Vector2(110, 18))
	lap_big = _make_label(sec, "1 / 3", 44, accent)
	_place(lap_big, Vector2(16, 28), Vector2(170, 64))

	var names := ["ACTUAL", "ÚLTIMA", "MEJOR"]
	var vals: Array[Label] = []
	for i in 3:
		var y := 8.0 + i * 29.0
		var c := _make_label(sec, names[i], 12, hint)
		_place(c, Vector2(200, y), Vector2(60, 24))
		var v := _make_label(sec, "--:--.---", 18, txt, HORIZONTAL_ALIGNMENT_RIGHT)
		_place(v, Vector2(255, y), Vector2(inner_w - 255 - 14, 24))
		vals.append(v)
	cur_label = vals[0]
	last_label = vals[1]
	best_label = vals[2]


func _build_map_panel(accent: Color) -> void:
	var inner_w := MAP_W - PAD * 2.0
	var view_size := Vector2(inner_w - 12.0, MAP_INNER_H - 12.0)
	map_panel_size = Vector2(MAP_W, PAD * 2.0 + MAP_INNER_H)

	map_panel = Panel.new()
	map_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if map_transparent:
		map_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
		map_panel.add_theme_stylebox_override("panel", _flat(pal["panel"], pal["panel_border"], 20, 2, Color(accent, 0.25)))
	map_panel.size = map_panel_size
	map_panel.scale = Vector2.ONE * map_scale
	add_child(map_panel)

	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if map_transparent:
		frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
		frame.add_theme_stylebox_override("panel", _flat(pal["sec"], pal["sec_border"], 14, 2))
	map_panel.add_child(frame)
	_place(frame, Vector2(PAD, PAD), Vector2(inner_w, MAP_INNER_H))

	map_vp = SubViewport.new()
	map_vp.size = Vector2i(int(view_size.x) * map_quality, int(view_size.y) * map_quality)
	map_vp.msaa_3d = Viewport.MSAA_2X
	map_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	map_vp.transparent_bg = map_transparent
	add_child(map_vp)

	map_cam = Camera3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0) if map_transparent else pal["map_bg"]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.7
	map_cam.environment = env
	map_vp.add_child(map_cam)
	map_cam.current = true

	var view := TextureRect.new()
	view.texture = map_vp.get_texture()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(view)
	_place(view, Vector2(6, 6), view_size)

	overlay = MapOverlay.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.cam = map_cam
	overlay.ratio = 1.0 / float(map_quality)
	overlay.trail_color = accent
	overlay.accent = accent
	frame.add_child(overlay)
	_place(overlay, Vector2(6, 6), view_size)


func _layout() -> void:
	if lap_panel == null or map_panel == null:
		return
	var vp := get_viewport_rect().size
	lap_panel.position = Vector2((vp.x - lap_panel_size.x * lap_scale) * 0.5, lap_top_margin)
	map_panel.position = Vector2(map_margin, map_margin)
	banner.position = Vector2((vp.x - banner.size.x) * 0.5, lap_top_margin + lap_panel_size.y * lap_scale + 14.0)


# Cambia el tamaño del panel de vueltas (teclas - y +)
func _apply_lap_scale() -> void:
	if lap_panel == null:
		return
	lap_panel.scale = Vector2.ONE * lap_scale
	_layout()
	_save_settings()
	_flash("Tamaño: %.2f" % lap_scale, 1.0)


func _flash(text: String, secs: float = 2.5) -> void:
	banner.text = text
	banner.modulate.a = 1.0
	if banner_tween:
		banner_tween.kill()
	banner_tween = create_tween()
	banner_tween.tween_interval(secs)
	banner_tween.tween_property(banner, "modulate:a", 0.0, 0.6)


# ============================================================
#  MAPA: ZONA DEL MUNDO Y CÁMARA
# ============================================================

func _compute_bounds() -> void:
	var cy := 0.0
	if car != null:
		cy = car.global_position.y
	track_box = AABB(
		Vector3(manual_bounds.position.x, cy - 5.0, manual_bounds.position.y),
		Vector3(manual_bounds.size.x, 10.0, manual_bounds.size.y))

	if not use_manual_bounds:
		var src: Node = track_mesh
		if src == null:
			src = get_tree().current_scene.find_child("Pista", true, false)
		if src != null:
			var meshes: Array = src.find_children("*", "MeshInstance3D", true, false)
			if src is MeshInstance3D:
				meshes.append(src)
			var have := false
			var box := AABB()
			for m in meshes:
				var mi := m as MeshInstance3D
				var b: AABB = mi.global_transform * mi.get_aabb()
				if have:
					box = box.merge(b)
				else:
					box = b
					have = true
			if have and box.size.x > 0.1 and box.size.z > 0.1:
				track_box = box
		else:
			push_warning("CarreraUI: no encontré el nodo 'Pista'. Uso los límites manuales.")

	_build_map_copy()
	_setup_camera()


# Copia de la pista que solo ve el mapa, con el shader que deja solo la carretera
func _build_map_copy() -> void:
	if road_copy_built or not only_road or road_texture == null or map_vp == null:
		return
	var src: Node = track_mesh
	if src == null:
		src = get_tree().current_scene.find_child("Pista", true, false)
	if src == null:
		return

	var shader := load("res://assets/UI/mapa_solo_pista.gdshader") as Shader
	if shader == null:
		push_warning("CarreraUI: falta res://assets/UI/mapa_solo_pista.gdshader")
		return

	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("mapa", road_texture)
	mat.set_shader_parameter("umbral", road_threshold)

	var meshes: Array = src.find_children("*", "MeshInstance3D", true, false)
	if src is MeshInstance3D:
		meshes.append(src)
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var copy := MeshInstance3D.new()
		copy.mesh = mi.mesh
		copy.material_override = mat
		copy.layers = MAP_LAYER
		map_vp.add_child(copy)
		copy.global_transform = mi.global_transform
	road_copy_built = true


func _setup_camera() -> void:
	if map_cam == null or map_vp == null:
		return
	var center := track_box.get_center()
	var w := track_box.size.x
	var depth := track_box.size.z

	if int(round(posmod(map_yaw_deg, 180.0) / 90.0)) == 1:
		var tmp := w
		w = depth
		depth = tmp

	var aspect := float(map_vp.size.x) / float(map_vp.size.y)
	if road_copy_built:
		map_cam.cull_mask = MAP_LAYER
	else:
		map_cam.cull_mask = map_cull_mask
	map_cam.near = 0.5
	map_cam.far = 8000.0

	if not map_3d:
		map_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		map_cam.size = maxf(depth, w / aspect) * 1.1 / map_zoom
		map_cam.rotation_degrees = Vector3(-90.0, map_yaw_deg, 0.0)
		map_cam.position = Vector3(center.x, track_box.end.y + 300.0, center.z)
	else:
		map_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		map_cam.fov = 40.0
		var tilt := clampf(map_tilt_deg, 20.0, 85.0)
		map_cam.rotation_degrees = Vector3(-tilt, map_yaw_deg, 0.0)
		var th := tan(deg_to_rad(map_cam.fov) * 0.5)
		var dist_w := (w * 0.55) / (th * aspect)
		var proj_h := depth * sin(deg_to_rad(tilt)) + track_box.size.y * cos(deg_to_rad(tilt))
		var dist_h := (proj_h * 0.55) / th
		var dist := maxf(dist_w, dist_h) * 1.15 / map_zoom
		map_cam.position = center + map_cam.basis.z * dist

	overlay.ready_to_draw = true


func _find_car() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	if root is VehicleBody3D:
		car = root
		return
	var found := root.find_children("*", "VehicleBody3D", true, false)
	if found.size() > 0:
		car = found[0] as VehicleBody3D


# ============================================================
#  LÓGICA DE VUELTAS
# ============================================================

func _physics_process(delta: float) -> void:
	if car == null:
		_find_car()
		return

	var p := Vector2(car.global_position.x, car.global_position.z)
	var py := car.global_position.y

	if not initialized:
		initialized = true
		start_pos = p
		start_y = py
		if finish_marker:
			start_pos = Vector2(finish_marker.global_position.x, finish_marker.global_position.z)
			start_y = finish_marker.global_position.y
		last_pos = p
		last_trail_pos = p
		overlay.start_pos = Vector3(start_pos.x, start_y, start_pos.y)
		overlay.has_start = true
		if show_trail:
			overlay.trail.append(Vector3(p.x, py, p.y))

	var speed_kmh := car.linear_velocity.length() * 3.6
	if not race_started and speed_kmh > 3.0:
		race_started = true

	if finished:
		return

	if race_started:
		lap_time += delta

	path_len += p.distance_to(last_pos)
	last_pos = p

	if show_trail and p.distance_to(last_trail_pos) >= trail_step:
		overlay.trail.append(Vector3(p.x, py, p.y))
		last_trail_pos = p

	var d := p.distance_to(start_pos)
	if d > far_distance:
		armed = true
	if armed and race_started and d < finish_radius and path_len >= min_lap_distance:
		_complete_lap()


func _complete_lap() -> void:
	var t := lap_time
	last_lap = t
	if best_lap < 0.0 or t < best_lap:
		best_lap = t
		_save_settings()
	laps_done += 1
	armed = false
	path_len = 0.0
	lap_time = 0.0
	overlay.trail.clear()

	if total_laps > 0 and laps_done >= total_laps:
		finished = true
		_flash("¡CARRERA TERMINADA!   Mejor: %s" % _fmt_time(best_lap), 5.0)
	else:
		_flash("VUELTA %d   %s" % [laps_done, _fmt_time(t)])
	_refresh_laps()


# ============================================================
#  ACTUALIZAR LO QUE SE VE
# ============================================================

func _fmt_time(sec: float) -> String:
	if sec < 0.0:
		return "--:--.---"
	var ms: int = int(round(sec * 1000.0))
	var minutes: int = ms / 60000
	var seconds: int = (ms / 1000) % 60
	var millis: int = ms % 1000
	return "%d:%02d.%03d" % [minutes, seconds, millis]


func _refresh_laps() -> void:
	var shown := laps_done + 1
	if total_laps > 0:
		shown = mini(shown, total_laps)
		lap_big.text = "%d / %d" % [shown, total_laps]
	else:
		lap_big.text = str(shown)
	last_label.text = _fmt_time(last_lap)
	best_label.text = _fmt_time(best_lap)


func _process(_delta: float) -> void:
	if car == null or overlay == null:
		return
	cur_label.text = _fmt_time(lap_time) if race_started else "--:--.---"

	overlay.car_pos = car.global_position
	var b := car.global_transform.basis.z
	if not model_faces_plus_z:
		b = -b
	overlay.car_dir = Vector3(b.x, 0.0, b.z).normalized()
	overlay.queue_redraw()


# ============================================================
#  TECLADO Y GUARDADO
# ============================================================

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_N:
		map_panel.visible = not map_panel.visible
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_B:
		lap_panel.visible = not lap_panel.visible
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_MINUS or key.keycode == KEY_KP_SUBTRACT:
		lap_scale = clampf(lap_scale - 0.05, 0.3, 1.5)
		_apply_lap_scale()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_EQUAL or key.keycode == KEY_KP_ADD:
		lap_scale = clampf(lap_scale + 0.05, 0.3, 1.5)
		_apply_lap_scale()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_V:
		map_3d = not map_3d
		_setup_camera()
		get_viewport().set_input_as_handled()


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("carrera", "mejor", best_lap)
	if remember_lap_scale:
		cfg.set_value("carrera", "lap_scale", lap_scale)
	cfg.save(SAVE_PATH)


func _load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	best_lap = cfg.get_value("carrera", "mejor", -1.0)
	if remember_lap_scale:
		lap_scale = cfg.get_value("carrera", "lap_scale", lap_scale)
