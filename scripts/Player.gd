extends CharacterBody2D

signal hp_changed(player_id: int, new_hp: int)
signal died(player_id: int)

@export var speed: float = 380.0
@export var normal_bullet_scene: PackedScene
@export var heavy_bullet_scene: PackedScene
@export var normal_fire_rate: float = 0.25
@export var heavy_fire_rate: float = 1.6

@export var player_id: int = 1:
	set(value):
		player_id = value
		set_multiplayer_authority(value)
		if is_inside_tree():
			_apply_authority_setup()

@export var player_name: String = "Player":
	set(value):
		player_name = value
		if name_label:
			name_label.text = value

@export var max_hp: int = 3
@export var current_hp: int = 3
@export var is_top_player: bool = false:
	set(value):
		is_top_player = value
		if is_inside_tree():
			_apply_orientation()

@export var can_move: bool = false # Controlado por el servidor / cuenta atrás

var can_shoot_normal: bool = true
var can_shoot_heavy: bool = true

@onready var sprite: Sprite2D = $Sprite2D
@onready var muzzle: Marker2D = $Muzzle
@onready var hp_bar: ProgressBar = $HUD/HPBar
@onready var name_label: Label = $HUD/NameLabel
@onready var synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer

func _ready() -> void:
	add_to_group("player")
	if name.is_valid_int():
		player_id = name.to_int()
	
	_apply_authority_setup()
	_apply_orientation()
	_update_hud()

func _apply_authority_setup() -> void:
	set_multiplayer_authority(player_id)
	if synchronizer:
		# La autoridad del sincronizador debe ser quien mueve la nave para replicar su posición
		synchronizer.set_multiplayer_authority(player_id)

func _apply_orientation() -> void:
	if is_top_player or player_id != 1:
		rotation_degrees = 180.0
		if has_node("HUD"):
			$HUD.rotation_degrees = 180.0
		if sprite:
			sprite.modulate = Color(1.0, 0.45, 0.45) # Tinte rojo
	else:
		rotation_degrees = 0.0
		if has_node("HUD"):
			$HUD.rotation_degrees = 0.0
		if sprite:
			sprite.modulate = Color(0.45, 0.75, 1.0) # Tinte azul

func _process(delta: float) -> void:
	# Únicamente el dueño de este jugador lee teclado y ratón
	if not is_multiplayer_authority():
		return
		
	if can_move:
		_handle_movement(delta)
		_handle_shooting()

func _handle_movement(_delta: float) -> void:
	var input_vec: Vector2 = Vector2.ZERO
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_vec.x -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_vec.x += 1.0
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_vec.y -= 1.0
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_vec.y += 1.0
		
	# Invertir controles para el jugador de arriba para que sea intuitivo desde su vista
	if is_top_player:
		input_vec.x = -input_vec.x
		input_vec.y = -input_vec.y

	velocity = input_vec.normalized() * speed
	move_and_slide()
	
	# Delimitar dentro de su propia mitad de pantalla
	# Viewport: 1152 x 648 -> Línea divisoria central Y: 324
	var vp: Rect2 = get_viewport_rect()
	var margin_x: float = 32.0
	var min_y: float = 0.0
	var max_y: float = 0.0
	
	if is_top_player:
		min_y = 35.0
		max_y = 300.0
	else:
		min_y = 348.0
		max_y = vp.size.y - 35.0
		
	global_position.x = clamp(global_position.x, vp.position.x + margin_x, vp.position.x + vp.size.x - margin_x)
	global_position.y = clamp(global_position.y, min_y, max_y)

func _handle_shooting() -> void:
	var shoot_dir: Vector2 = Vector2.DOWN if is_top_player else Vector2.UP
	var m_pos: Vector2 = muzzle.global_position if muzzle else (global_position + shoot_dir * 30.0)

	# Click Izquierdo o Barra espaciadora: Disparo Normal
	if (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_action_just_pressed("ui_accept")) and can_shoot_normal:
		can_shoot_normal = false
		request_fire.rpc_id(1, m_pos, shoot_dir, false)
		var timer: SceneTreeTimer = get_tree().create_timer(normal_fire_rate)
		timer.timeout.connect(func(): can_shoot_normal = true)
		
	# Click Derecho: Ataque Potente / Pesado
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and can_shoot_heavy:
		can_shoot_heavy = false
		request_fire.rpc_id(1, m_pos, shoot_dir, true)
		var timer: SceneTreeTimer = get_tree().create_timer(heavy_fire_rate)
		timer.timeout.connect(func(): can_shoot_heavy = true)

@rpc("any_peer", "call_local", "reliable")
func request_fire(spawn_pos: Vector2, dir: Vector2, is_heavy: bool) -> void:
	if not multiplayer.is_server():
		return
		
	var scene_to_spawn: PackedScene = heavy_bullet_scene if is_heavy else normal_bullet_scene
	if scene_to_spawn:
		var bullet: Node = scene_to_spawn.instantiate()
		bullet.global_position = spawn_pos
		if bullet.has_method("set_bullet"):
			bullet.call("set_bullet", dir, player_id)
		
		var bullets_container: Node = get_tree().current_scene.get_node_or_null("Bullets")
		if bullets_container:
			bullets_container.add_child(bullet, true)
		else:
			get_tree().current_scene.add_child(bullet, true)

func apply_damage(dmg: int) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		current_hp = max(0, current_hp - dmg)
		sync_health.rpc(current_hp)
		if current_hp <= 0:
			died.emit(player_id)

@rpc("call_local", "reliable")
func sync_health(hp: int) -> void:
	current_hp = hp
	_update_hud()
	hp_changed.emit(player_id, current_hp)

func _update_hud() -> void:
	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value = current_hp
	if name_label:
		name_label.text = player_name
