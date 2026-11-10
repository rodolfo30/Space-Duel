extends Node2D

@export var player_scene: PackedScene
@export var shield_scene: PackedScene

@onready var players_container: Node2D = $Players
@onready var shields_container: Node2D = $Shields
@onready var bullets_container: Node2D = $Bullets
@onready var network_setup: Control = $CanvasLayer/NetworkSetup
@onready var status_banner: Label = $CanvasLayer/StatusBanner
@onready var restart_button: Button = $CanvasLayer/RestartButton
@onready var top_hp_label: Label = $CanvasLayer/UI/TopHPLabel
@onready var bottom_hp_label: Label = $CanvasLayer/UI/BottomHPLabel

var is_battle_active: bool = false
var host_name: String = "Host"
var client_name: String = "Rival"

func _ready() -> void:
	if network_setup:
		network_setup.connect("game_started", _on_network_game_started)
	
	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)
		restart_button.visible = false
		
	status_banner.text = ""
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _on_network_game_started(player_name: String, is_host: bool) -> void:
	if is_host:
		host_name = player_name
		status_banner.text = "ESPERANDO A QUE SE UNA EL JUGADOR 2..."
	else:
		client_name = player_name
		register_client_name.rpc_id(1, client_name)

@rpc("any_peer", "call_local", "reliable")
func register_client_name(c_name: String) -> void:
	if multiplayer.is_server():
		client_name = c_name
		_start_match_sequence()

func _on_peer_connected(_id: int) -> void:
	if multiplayer.is_server():
		status_banner.text = "¡JUGADOR 2 CONECTADO!"

func _on_peer_disconnected(_id: int) -> void:
	if status_banner:
		status_banner.text = "EL RIVAL SE HA DESCONECTADO"
	if restart_button:
		restart_button.visible = true

func _start_match_sequence() -> void:
	if not multiplayer.is_server():
		return
		
	# 1. Limpiar proyectiles residuales en ambos peers
	clear_all_bullets.rpc()

	# 2. Re-instanciar o re-posicionar Escudos
	for s in shields_container.get_children():
		s.queue_free()
		
	var shield_positions: Array[Vector2] = [
		Vector2(288.0, 324.0),
		Vector2(576.0, 324.0),
		Vector2(864.0, 324.0)
	]
	for pos in shield_positions:
		var sh: Node = shield_scene.instantiate()
		sh.position = pos
		shields_container.add_child(sh, true)
		
	# 3. Limpiar jugadores anteriores si existen
	for c in players_container.get_children():
		c.queue_free()
		
	# Esperar un cuadro para que se complete el queue_free en el árbol
	await get_tree().process_frame

	# 4. Instanciar Jugador 1 (Host - Abajo)
	var p1: CharacterBody2D = player_scene.instantiate() as CharacterBody2D
	p1.name = "1"
	p1.position = Vector2(576.0, 560.0)
	p1.rotation = 0.0 # Mirando hacia arriba
	p1.set("player_id", 1)
	p1.set("is_top_player", false)
	p1.set("player_name", host_name)
	p1.set("can_move", false)
	p1.connect("died", _on_player_died)
	p1.connect("hp_changed", _on_player_hp_changed)
	players_container.add_child(p1, true)
	
	# 5. Instanciar Jugador 2 (Cliente - Arriba)
	var peer_ids: PackedInt32Array = multiplayer.get_peers()
	var client_id: int = peer_ids[0] if peer_ids.size() > 0 else 2
	var p2: CharacterBody2D = player_scene.instantiate() as CharacterBody2D
	p2.name = str(client_id)
	p2.position = Vector2(576.0, 88.0)
	p2.rotation = PI # Mirando hacia abajo
	p2.set("player_id", client_id)
	p2.set("is_top_player", true)
	p2.set("player_name", client_name)
	p2.set("can_move", false)
	p2.connect("died", _on_player_died)
	p2.connect("hp_changed", _on_player_hp_changed)
	players_container.add_child(p2, true)
	
	p1.call("_apply_authority_setup")
	p2.call("_apply_authority_setup")
	
	sync_player_names.rpc(host_name, client_name)
	_run_countdown.call_deferred()

@rpc("call_local", "reliable")
func clear_all_bullets() -> void:
	if bullets_container:
		for b in bullets_container.get_children():
			b.queue_free()

@rpc("call_local", "reliable")
func sync_player_names(h_name: String, c_name: String) -> void:
	host_name = h_name
	client_name = c_name
	_update_ui_labels(3, 3)

func _update_ui_labels(top_hp: int, bottom_hp: int) -> void:
	if top_hp_label:
		top_hp_label.text = "%s (TOP): %d/3 HP" % [client_name, max(0, top_hp)]
	if bottom_hp_label:
		bottom_hp_label.text = "%s (BOTTOM): %d/3 HP" % [host_name, max(0, bottom_hp)]

func _run_countdown() -> void:
	set_countdown_text.rpc("3...")
	await get_tree().create_timer(1.0).timeout
	set_countdown_text.rpc("2...")
	await get_tree().create_timer(1.0).timeout
	set_countdown_text.rpc("1...")
	await get_tree().create_timer(1.0).timeout
	set_countdown_text.rpc("¡FIGHT!")
	
	set_players_can_move.rpc(true)
	is_battle_active = true
	
	await get_tree().create_timer(1.0).timeout
	set_countdown_text.rpc("")

@rpc("call_local", "reliable")
func set_players_can_move(val: bool) -> void:
	for p in players_container.get_children():
		p.set("can_move", val)

@rpc("call_local", "reliable")
func set_countdown_text(txt: String) -> void:
	if status_banner:
		status_banner.text = txt

func _on_player_hp_changed(_p_id: int, _new_hp: int) -> void:
	if multiplayer.is_server():
		sync_match_ui.rpc()

@rpc("call_local", "reliable")
func sync_match_ui() -> void:
	var top_hp: int = 3
	var bottom_hp: int = 3
	for p in players_container.get_children():
		if p.get("is_top_player"):
			top_hp = p.get("current_hp")
		else:
			bottom_hp = p.get("current_hp")
	_update_ui_labels(top_hp, bottom_hp)

func _on_player_died(dead_id: int) -> void:
	if not multiplayer.is_server() or not is_battle_active:
		return
	is_battle_active = false
	var winner_name: String = host_name if dead_id != 1 else client_name
	end_battle.rpc(winner_name)

@rpc("call_local", "reliable")
func end_battle(winner_name: String) -> void:
	is_battle_active = false
	if status_banner:
		status_banner.text = "¡HA GANADO %s!" % winner_name.to_upper()
	if restart_button:
		restart_button.visible = true
	set_players_can_move(false)

func _on_restart_pressed() -> void:
	if multiplayer.has_multiplayer_peer():
		request_restart_server.rpc_id(1)
	else:
		get_tree().reload_current_scene()

@rpc("any_peer", "call_local", "reliable")
func request_restart_server() -> void:
	if multiplayer.is_server():
		restart_match_rpc.rpc()

@rpc("call_local", "reliable")
func restart_match_rpc() -> void:
	if restart_button:
		restart_button.visible = false
	if multiplayer.is_server():
		_start_match_sequence()
