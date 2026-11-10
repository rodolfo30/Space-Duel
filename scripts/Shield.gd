extends Area2D

@export var max_hp: int = 5
var current_hp: int = 5

@onready var sprite: Sprite2D = $Sprite2D
@onready var hp_label: Label = $HPLabel

func _ready() -> void:
	add_to_group("shield")
	current_hp = max_hp
	_update_visuals()

func take_hit(dmg: int) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		current_hp -= dmg
		sync_hp.rpc(current_hp)
		if current_hp <= 0:
			queue_free()

@rpc("call_local", "reliable")
func sync_hp(hp: int) -> void:
	current_hp = hp
	_update_visuals()
	if current_hp <= 0:
		queue_free()

func _update_visuals() -> void:
	if hp_label:
		hp_label.text = "%d" % max(0, current_hp)
	if sprite:
		# Modula el color haciéndose más rojizo y transparente al dañarse
		var ratio: float = float(current_hp) / float(max_hp)
		sprite.modulate = Color(1.0, 0.4 + (0.6 * ratio), 0.4 + (0.6 * ratio), 0.5 + (0.5 * ratio))

