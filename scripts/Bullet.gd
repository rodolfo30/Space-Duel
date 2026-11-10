extends Area2D

@export var speed: float = 650.0
@export var damage: int = 1
@export var direction: Vector2 = Vector2.UP
@export var shooter_id: int = 0

func _ready() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		set_physics_process(false)
		return
		
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	var notifier: VisibleOnScreenNotifier2D = get_node_or_null("VisibleOnScreenNotifier2D")
	if notifier:
		notifier.screen_exited.connect(_on_screen_exited)

func set_bullet(dir: Vector2, who: int) -> void:
	direction = dir.normalized()
	shooter_id = who

func _physics_process(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	global_position += direction * speed * delta

func _on_body_entered(body: Node) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
		
	# Colisión con jugador
	if body.is_in_group("player"):
		var p_id: int = body.get("player_id") if body.get("player_id") != null else 0
		if p_id != shooter_id and body.has_method("apply_damage"):
			body.call("apply_damage", damage)
			queue_free()
			return

	# Colisión con escudo / cobertura
	if body.is_in_group("shield") and body.has_method("take_hit"):
		body.call("take_hit", damage)
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
		
	if area.is_in_group("player"):
		var p_id: int = area.get("player_id") if area.get("player_id") != null else 0
		if p_id != shooter_id and area.has_method("apply_damage"):
			area.call("apply_damage", damage)
			queue_free()
			return
			
	if area.is_in_group("shield") and area.has_method("take_hit"):
		area.call("take_hit", damage)
		queue_free()

func _on_screen_exited() -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		queue_free()
