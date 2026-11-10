extends Node

signal leaderboard_received(data: Array)
signal score_submitted_successfully()
signal network_error(msg: String)

const SERVER_URL: String = "http://127.0.0.1:8080"

var http: HTTPRequest

func _ready() -> void:
	http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_request_completed)

func fetch_leaderboard() -> void:
	var err: Error = http.request(SERVER_URL + "/api/v1/leaderboard")
	if err != OK:
		network_error.emit("Failed to start leaderboard request: %s" % err)

func submit_score(player_name: String, score: int) -> void:
	var payload: Dictionary = {
		"player_name": player_name,
		"score": score,
		"validation_hash": "sha256_mock_hash"
	}
	var json_body: String = JSON.stringify(payload)
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var err: Error = http.request(
		SERVER_URL + "/api/v1/score",
		headers,
		HTTPClient.METHOD_POST,
		json_body
	)
	if err != OK:
		network_error.emit("Failed to start score submit: %s" % err)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code >= 400:
		network_error.emit("HTTP Error %d" % response_code)
		return

	var response_text: String = body.get_string_from_utf8()
	var json: Variant = JSON.parse_string(response_text)
	if json == null:
		network_error.emit("Invalid JSON response")
		return

	if json is Dictionary and json.has("top"):
		leaderboard_received.emit(json["top"])
	else:
		score_submitted_successfully.emit()
