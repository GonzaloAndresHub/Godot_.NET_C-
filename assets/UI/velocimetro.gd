extends Control

@export var car: VehicleBody3D                 # Opcional: si está vacío, se busca solo
@export var max_speed_kmh: float = 300.0       # Velocidad máxima del auto
@export var max_rpm: float = 12.0              # RPM máximas (x1000)
@export var idle_rpm: float = 1.0              # RPM en ralentí (x1000)
@export var gears: int = 6                     # Cantidad de marchas
@export var smoothing: float = 8.0             # Suavidad de la animación

@onready var gauge: TextureRect = $Gauge
@onready var speed_label: Label = $SpeedLabel
@onready var rpm_label: Label = $RpmLabel
@onready var gear_label: Label = $GearLabel

var shown_speed: float = 0.0
var shown_rpm: float = 1.0

func _ready() -> void:
	if car == null:
		find_car()

# Busca el VehicleBody3D en la escena si no fue asignado a mano
func find_car() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	if root is VehicleBody3D:
		car = root
		return
	var found := root.find_children("*", "VehicleBody3D", true, false)
	if found.size() > 0:
		car = found[0] as VehicleBody3D
		print("Velocimetro: auto encontrado -> ", car.name)
	else:
		push_warning("Velocimetro: no se encontró ningún VehicleBody3D en la escena")

func _process(delta: float) -> void:
	# Si todavía no hay auto, lo seguimos buscando
	if car == null:
		find_car()
		return

	# Velocidad real del auto en km/h
	var speed_kmh: float = car.linear_velocity.length() * 3.6

	# Velocidad hacia adelante (negativa si va en reversa)
	var forward_kmh: float = car.linear_velocity.dot(car.global_transform.basis.z) * 3.6

	# --- Marcha y RPM simuladas según la velocidad ---
	var gear_width: float = max_speed_kmh / gears
	var gear: int = clampi(int(speed_kmh / gear_width) + 1, 1, gears)
	var ratio: float = clampf((speed_kmh - (gear - 1) * gear_width) / gear_width, 0.0, 1.0)

	var low_rpm: float = idle_rpm if gear == 1 else max_rpm * 0.55
	var target_rpm: float = lerpf(low_rpm, max_rpm, ratio)

	# --- Suavizado para que los números y las luces no den saltos ---
	var k: float = 1.0 - exp(-smoothing * delta)
	shown_speed = lerpf(shown_speed, speed_kmh, k)
	shown_rpm = lerpf(shown_rpm, target_rpm, k)

	# --- Textos ---
	speed_label.text = str(int(round(shown_speed)))
	rpm_label.text = "%.1f\nRPM x1000" % shown_rpm

	if speed_kmh < 1.0:
		gear_label.text = "N"
	elif forward_kmh < -2.0:
		gear_label.text = "R"
	else:
		gear_label.text = "G " + str(gear)

	# --- Luces de neón (la "aguja digital") ---
	var progress: float = clampf(shown_speed / max_speed_kmh, 0.0, 1.0)
	var mat := gauge.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("progress", progress)
