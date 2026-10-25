extends VehicleBody3D

# --- VARIABLES DE AJUSTE (Puedes cambiarlas desde el Inspector sin abrir el código) ---
@export_group("Configuración de Conducción")
@export var max_engine_force: float = 2500.0  # Fuerza para avanzar/retroceder
@export var max_steering: float = 0.5         # Ángulo máximo de giro de las ruedas
@export var brake_force: float = 50.0         # Fuerza del freno
@export var steering_speed: float = 2.5       # Qué tan rápido giran las ruedas al mando
@export var min_steering_factor: float = 0.25 # Qué tanto giro (%) se mantiene a velocidad máxima
@export var steering_reduction_speed_kmh: float = 250.0  # Velocidad a la que el giro llega a su mínimo

@export_group("Interfaz (UI)")
@export var speedometer_label: Label         # Arrastra aquí tu nodo Label del velocímetro

@export_group("Sonido del Motor")
@export var motor_sound: AudioStreamPlayer3D  # Arrastra aquí tu nodo MotorSound
@export var max_speed_kmh: float = 300.0      # Velocidad "de referencia" para el tono máximo del motor
@export var min_pitch: float = 0.7            # Tono del motor cuando el auto está casi detenido
@export var max_pitch: float = 2.2            # Tono del motor a velocidad máxima
@export var min_volume_db: float = -20.0      # Volumen cuando el auto está casi detenido (bien bajito)
@export var max_volume_db: float = 0.0        # Volumen a velocidad máxima

@export_group("Aerodinámica")
@export var downforce_coefficient: float = 4.0  # Qué tan fuerte "pega" el auto al piso con la velocidad

var motor_encendido: bool = false

# --- LÓGICA DE FÍSICA ---

func _physics_process(delta: float) -> void:
	handle_engine(delta)
	handle_steering(delta)
	handle_brake()
	update_speedometer()
	handle_engine_sound()
	apply_downforce()

# 1. Control del motor (Acelerar y Reversa)
func handle_engine(_delta: float) -> void:
	# get_axis devuelve: 1 si presionas "acelerar", -1 si presionas "frenar"
	var throttle = Input.get_axis("frenar", "acelerar")
	engine_force = throttle * max_engine_force

	# Encendemos el sonido del motor la primera vez que se presiona acelerar
	if throttle > 0.0 and not motor_encendido:
		motor_encendido = true
		if motor_sound and not motor_sound.playing:
			motor_sound.play()

# 2. Control de la dirección (Girar)
func handle_steering(delta: float) -> void:
	# get_axis devuelve: 1 si presionas "izquierda", -1 si presionas "derecha"
	# (Nota: El orden depende de cómo quieras que responda el eje)
	var steer_input = Input.get_axis("derecha", "izquierda")

	# Calculamos la velocidad actual en km/h
	var speed_kmh = linear_velocity.length() * 3.6

	# Mientras más rápido vaya, menos ángulo de giro permitimos (evita el trompo a alta velocidad)
	var speed_factor = clamp(1.0 - (speed_kmh / steering_reduction_speed_kmh), min_steering_factor, 1.0)
	var steering_actual = max_steering * speed_factor

	# move_toward hace que el giro no sea instantáneo, dándole realismo
	steering = move_toward(steering, steer_input * steering_actual, delta * steering_speed)

# 3. Control del freno
func handle_brake() -> void:
	# Si presionas la tecla "frenar" (S), se aplica la fuerza de freno
	if Input.is_action_pressed("frenar"):
		brake = brake_force
	else:
		brake = 0.0

# 4. Actualizar el texto de la velocidad en pantalla
func update_speedometer() -> void:
	if speedometer_label:
		# Obtenemos la velocidad lineal del carro
		var speed_ms = linear_velocity.length()
		# Convertimos de metros por segundo a km/h (multiplicando por 3.6)
		var speed_kmh = speed_ms * 3.6
		# Mostramos el texto redondeado
		speedometer_label.text = "Velocidad: " + str(round(speed_kmh)) + " km/h"

# 5. Sonido del motor sincronizado con la velocidad real del auto
func handle_engine_sound() -> void:
	if not motor_sound:
		return

	var speed_kmh = linear_velocity.length() * 3.6
	var throttle = Input.get_axis("frenar", "acelerar")

	# "factor" va de 0.0 (detenido) a 1.0 (velocidad máxima de referencia)
	var factor = clamp(speed_kmh / max_speed_kmh, 0.0, 1.0)

	motor_sound.pitch_scale = lerp(min_pitch, max_pitch, factor)
	motor_sound.volume_db = lerp(min_volume_db, max_volume_db, factor)

	# Solo apagamos el motor si la velocidad es casi 0 Y no se está presionando acelerar
	# (si está atascado en una subida presionando W, el motor sigue sonando como esforzándose)
	if speed_kmh < 1.0 and throttle <= 0.0 and motor_encendido:
		motor_encendido = false
		if motor_sound.playing:
			motor_sound.stop()

# 6. Downforce: empuja el auto hacia el piso proporcional al CUADRADO de la velocidad
# (así es como funciona el downforce real: a baja velocidad casi no hay, a alta velocidad es enorme)
func apply_downforce() -> void:
	var speed_ms = linear_velocity.length()
	var downforce = speed_ms * speed_ms * downforce_coefficient
	apply_central_force(-global_transform.basis.y * downforce)
