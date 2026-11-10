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

@export var can_move: bool = false # Controlado por la cuenta regresiva

var can_shoot_normal: bool = true
var can_shoot_heavy: bool = true

@onready var sprite: Sprite2D = $Sprite2D
@onready var muzzle: Marker2D = $Muzzle
@onready var hud: Node2D = $HUD
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
		synchronizer.set_multiplayer_authority(player_id)

func _apply_orientation() -> void:
	if sprite:
		if is_top_player:
			sprite.modulate = Color(1.0, 0.45, 0.45) # Tinte rojo/naranja
		else:
			sprite.modulate = Color(0.45, 0.75, 1.0) # Tinte azul

func _process(delta: float) -> void:
	# Mantener el HUD flotante sobre la nave (sin rotar)
	if hud:
		hud.global_position = global_position
		hud.rotation = 0.0

	# Únicamente el dueño de esta nave lee teclado y ratón
	if not is_multiplayer_authority():
		return
		
	if can_move:
		_handle_aim_and_movement(delta)
		_handle_shooting()

func _handle_aim_and_movement(_delta: float) -> void:
	var mouse_pos: Vector2 = get_global_mouse_position()
	var to_mouse: Vector2 = mouse_pos - global_position
	
	# Apuntar la nave hacia el ratón (la nave mira hacia -Y por defecto, por lo que sumamos PI/2)
	var aim_dir: Vector2 = Vector2.UP
	if to_mouse.length_squared() > 10.0:
		aim_dir = to_mouse.normalized()
		rotation = aim_dir.angle() + (PI * 0.5)

	# Ejes relativos al apuntado
	var forward: Vector2 = aim_dir
	var right: Vector2 = Vector2(-forward.y, forward.x)

	# Movimiento con W, S, A, D relativo a la dirección del ratón
	var move_vec: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"):
		move_vec += forward
	if Input.is_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"):
		move_vec -= forward
	if Input.is_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"):
		move_vec += right
	if Input.is_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"):
		move_vec -= right

	velocity = move_vec.normalized() * speed
	move_and_slide()
	
	# Delimitar dentro de su propia mitad de pantalla
	# Viewport: 1152 x 648 -> Línea divisoria central Y: 324
	var vp: Rect2 = get_viewport_rect()
	var margin_x: float = 32.0
	var min_y: float = 0.0
	var max_y: float = 0.0
	
	if is_top_player:
		# Mitad superior
		min_y = 35.0
		max_y = 300.0
	else:
		# Mitad inferior
		min_y = 348.0
		max_y = vp.size.y - 35.0
		
	global_position.x = clamp(global_position.x, vp.position.x + margin_x, vp.position.x + vp.size.x - margin_x)
	global_position.y = clamp(global_position.y, min_y, max_y)

func _handle_shooting() -> void:
	# El vector de disparo va hacia el ratón
	var mouse_pos: Vector2 = get_global_mouse_position()
	var shoot_dir: Vector2 = (mouse_pos - global_position).normalized()
	if shoot_dir.length_squared() < 0.1:
		shoot_dir = Vector2.DOWN if is_top_player else Vector2.UP

	var m_pos: Vector2 = muzzle.global_position if muzzle else (global_position + shoot_dir * 32.0)

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
