extends Control

signal game_started(player_name: String, is_host: bool)

@export var default_port: int = 8910
@export var default_ip: String = "127.0.0.1"

@onready var name_line_edit: LineEdit = $VBoxContainer/NameLineEdit
@onready var host_button: Button = $VBoxContainer/HostButton
@onready var join_button: Button = $VBoxContainer/JoinButton
@onready var ip_line_edit: LineEdit = $VBoxContainer/HBoxContainer/IPLineEdit
@onready var status_label: Label = $VBoxContainer/StatusLabel

var peer: ENetMultiplayerPeer
var my_player_name: String = "Player"

func _ready() -> void:
	if ip_line_edit:
		ip_line_edit.text = default_ip
	
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _get_entered_name() -> String:
	var entered: String = name_line_edit.text.strip_edges()
	return entered if not entered.is_empty() else ("Host" if multiplayer.is_server() else "Rival")

func _on_host_pressed() -> void:
	my_player_name = _get_entered_name()
	peer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(default_port, 2)
	if error != OK:
		_set_status("Error al crear servidor: %d" % error)
		return
	
	multiplayer.multiplayer_peer = peer
	_set_status("Servidor creado (Puerto %d). Esperando al Rival..." % default_port)
	host_button.disabled = true
	join_button.disabled = true
	name_line_edit.editable = false
	
	game_started.emit(my_player_name, true)

func _on_join_pressed() -> void:
	my_player_name = _get_entered_name()
	var ip: String = ip_line_edit.text.strip_edges()
	if ip.is_empty():
		ip = default_ip
	
	peer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(ip, default_port)
	if error != OK:
		_set_status("Error al conectar: %d" % error)
		return
		
	multiplayer.multiplayer_peer = peer
	_set_status("Conectando con %s:%d..." % [ip, default_port])
	host_button.disabled = true
	join_button.disabled = true
	name_line_edit.editable = false

func _on_peer_connected(id: int) -> void:
	_set_status("Rival conectado (ID: %d)" % id)
	if multiplayer.is_server():
		visible = false

func _on_peer_disconnected(id: int) -> void:
	_set_status("El rival se ha desconectado.")

func _on_connected_to_server() -> void:
	_set_status("¡Conectado! Preparando combate...")
	visible = false
	game_started.emit(my_player_name, false)

func _on_connection_failed() -> void:
	_set_status("Fallo al conectar con el servidor.")
	host_button.disabled = false
	join_button.disabled = false
	name_line_edit.editable = true

func _on_server_disconnected() -> void:
	_set_status("Servidor desconectado.")
	visible = true
	host_button.disabled = false
	join_button.disabled = false
	name_line_edit.editable = true

func _set_status(msg: String) -> void:
	if status_label:
		status_label.text = msg
