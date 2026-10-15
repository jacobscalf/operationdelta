extends Node
## The match referee. Runs the lobby, rounds and scoring.
## The host makes every decision here and tells the other computers with _sync() and _sync_lobby().
##
## Flow:  LOBBY (pick a side, green up) -> STARTING (everyone green: 10 s to cancel)
##        -> COUNTDOWN (frozen at spawn) -> LIVE (one life each) -> ROUND_OVER
##        -> next COUNTDOWN ... -> MATCH_OVER -> back to LOBBY.
## Practice mode stays in PRACTICE forever (respawns on, no rounds).

enum State { PRACTICE, LOBBY, STARTING, COUNTDOWN, LIVE, ROUND_OVER, MATCH_OVER }

const TEAM_OPS := 0
const TEAM_TERRORISTS := 1
const TEAM_NAMES := ["OPS", "TERRORISTS"]
const TEAM_COLORS := [Color(0.35, 0.6, 1.0), Color(1.0, 0.45, 0.3)]

const STARTING_TIME := 10.0  # after everyone greens up, before the match starts
const COUNTDOWN_TIME := 5.0
const ROUND_OVER_TIME := 6.0
const MATCH_OVER_TIME := 12.0
const PRACTICE_RESPAWN_TIME := 5.0
const LOBBY_BROADCAST_INTERVAL := 0.5

## Emitted on every computer whenever the match state changes, e.g. for the HUD.
signal changed
## Emitted on every computer whenever the lobby list (sides, names, green-ups) changes.
signal lobby_changed

var state := State.LOBBY
var time_left := 0.0
var scores := [0, 0]
var round_number := 0
var banner := ""  # big message in the middle of the screen
var friendly_fire := false
var rounds_to_win := 4
var round_minutes := 5
## Everyone in the lobby: [{ "id": int, "name": String, "team": int, "ready": bool }, ...]
var lobby: Array = []

## Set by main.gd: the node holding every player.
var players_node: Node
## Set by main.gd: Callable(team, index) -> Vector3 spawn position.
var spawn_point_for: Callable

var _ready_peers := {}  # host only: peer id -> has greened up
var _lobby_broadcast_left := 0.0


func _ready() -> void:
	friendly_fire = Network.friendly_fire
	rounds_to_win = Network.rounds_to_win
	round_minutes = Network.round_minutes
	if Network.mode == Network.Mode.PRACTICE:
		state = State.PRACTICE


func _process(delta: float) -> void:
	time_left = maxf(time_left - delta, 0.0)
	if not multiplayer.is_server():
		return

	match state:
		State.LOBBY:
			if _everyone_green():
				_set_state(State.STARTING, STARTING_TIME, "MATCH STARTING")
		State.STARTING:
			if not _everyone_green():
				_set_state(State.LOBBY, 0.0, "")
			elif time_left <= 0.0:
				scores = [0, 0]
				round_number = 0
				_start_countdown()
		State.COUNTDOWN:
			if not _both_teams_present():
				_enter_lobby()
			elif time_left <= 0.0:
				_set_state(State.LIVE, round_minutes * 60.0, "")
		State.LIVE:
			if time_left <= 0.0:
				_end_round_on_time()
		State.ROUND_OVER:
			if time_left <= 0.0:
				if scores.max() >= rounds_to_win:
					var winner: int = scores.find(scores.max())
					_set_state(State.MATCH_OVER, MATCH_OVER_TIME, "%s WIN THE MATCH   %d – %d" % [
						TEAM_NAMES[winner], scores[TEAM_OPS], scores[TEAM_TERRORISTS]])
				elif _both_teams_present():
					_start_countdown()
				else:
					_enter_lobby()
		State.MATCH_OVER:
			if time_left <= 0.0:
				_enter_lobby()

	# Keep everyone's lobby list fresh (names arrive a moment after players join).
	if in_lobby():
		_lobby_broadcast_left -= delta
		if _lobby_broadcast_left <= 0.0:
			_lobby_broadcast_left = LOBBY_BROADCAST_INTERVAL
			_broadcast_lobby()


# --- Questions other scripts ask -----------------------------------------------------

## True while the lobby screen is up.
func in_lobby() -> bool:
	return state == State.LOBBY or state == State.STARTING


## Players can't move or shoot during the countdown before a round.
func is_frozen() -> bool:
	return state == State.COUNTDOWN


## Only practice brings you back after dying; in a match you wait for the next round.
func respawns_enabled() -> bool:
	return state == State.PRACTICE


## Should a player who joins right now start alive, or wait for the next round?
func joiner_starts_alive() -> bool:
	return state == State.PRACTICE or state == State.COUNTDOWN


# --- Requests from players in the lobby ------------------------------------------------

## A player asks to switch sides. Switching un-greens you.
@rpc("any_peer", "call_local", "reliable")
func request_team(team: int) -> void:
	if not multiplayer.is_server() or not in_lobby() or team not in [TEAM_OPS, TEAM_TERRORISTS]:
		return
	var player := _player_for(_sender())
	if player and player.get("team") != team:
		player.call("set_team", team)
		_ready_peers[_sender()] = false
		_broadcast_lobby()


## A player greens up (ready) or cancels it.
@rpc("any_peer", "call_local", "reliable")
func request_green_up(is_ready: bool) -> void:
	if not multiplayer.is_server() or not in_lobby():
		return
	if _player_for(_sender()):
		_ready_peers[_sender()] = is_ready
		_broadcast_lobby()


# --- Events the host reports ------------------------------------------------------------

## Host only. Called by a player when they die.
func on_player_killed(victim: Node) -> void:
	if respawns_enabled():
		await get_tree().create_timer(PRACTICE_RESPAWN_TIME).timeout
		if is_instance_valid(victim) and respawns_enabled() and not victim.get("alive"):
			victim.call("respawn_at", spawn_point_for.call(victim.get("team"), -1))
	elif state == State.LIVE:
		_check_round_end()


## Host only. Called when a player disconnects (after their node is gone).
func on_player_left(peer_id: int) -> void:
	_ready_peers.erase(peer_id)
	if state == State.LIVE:
		_check_round_end()
	elif in_lobby():
		_broadcast_lobby()


## Host only. Sends the current state to a player who just joined.
func send_state_to(peer_id: int) -> void:
	_sync.rpc_id(peer_id, state, time_left, scores, round_number, banner,
		friendly_fire, rounds_to_win, round_minutes)


## Host only: which team should a new player start on? The smaller one (Ops on a tie).
## In the lobby they can switch.
func team_for_new_player() -> int:
	var counts := _team_counts()
	return TEAM_TERRORISTS if counts[TEAM_TERRORISTS] < counts[TEAM_OPS] else TEAM_OPS


# --- Round logic (host only) ---------------------------------------------------------------

func _start_countdown() -> void:
	round_number += 1
	# Everyone comes back to life at their team's spawn.
	var index := [0, 0]
	for player in _players():
		var team: int = player.get("team")
		player.call("respawn_at", spawn_point_for.call(team, index[team]))
		index[team] += 1
	_set_state(State.COUNTDOWN, COUNTDOWN_TIME, "ROUND %d" % round_number)


## Back to the lobby: everyone off the field and un-greened.
func _enter_lobby() -> void:
	_ready_peers.clear()
	for player in _players():
		player.call("leave_field")
	_set_state(State.LOBBY, 0.0, "")
	_broadcast_lobby()


func _check_round_end() -> void:
	var alive := _alive_counts()
	if alive[TEAM_OPS] == 0 and alive[TEAM_TERRORISTS] == 0:
		_end_round(-1)
	elif alive[TEAM_OPS] == 0:
		_end_round(TEAM_TERRORISTS)
	elif alive[TEAM_TERRORISTS] == 0:
		_end_round(TEAM_OPS)


## Time ran out: the team with more players alive wins; equal numbers is a draw.
func _end_round_on_time() -> void:
	var alive := _alive_counts()
	if alive[TEAM_OPS] > alive[TEAM_TERRORISTS]:
		_end_round(TEAM_OPS)
	elif alive[TEAM_TERRORISTS] > alive[TEAM_OPS]:
		_end_round(TEAM_TERRORISTS)
	else:
		_end_round(-1)


func _end_round(winner: int) -> void:
	var text := "ROUND DRAW"
	if winner >= 0:
		scores[winner] += 1
		text = "%s WIN THE ROUND" % TEAM_NAMES[winner]
	_set_state(State.ROUND_OVER, ROUND_OVER_TIME, text)


## The match can start when there's someone on each side and every player is green.
func _everyone_green() -> bool:
	if not _both_teams_present():
		return false
	for player in _players():
		if not _ready_peers.get(String(player.name).to_int(), false):
			return false
	return true


func _set_state(new_state: State, duration: float, banner_text: String) -> void:
	_sync.rpc(new_state, duration, scores, round_number, banner_text,
		friendly_fire, rounds_to_win, round_minutes)


func _broadcast_lobby() -> void:
	var entries: Array = []
	for player in _players():
		var peer_id := String(player.name).to_int()
		entries.append({
			"id": peer_id,
			"name": player.get("display_name"),
			"team": player.get("team"),
			"ready": _ready_peers.get(peer_id, false),
		})
	_sync_lobby.rpc(entries)


## Runs on every computer: the host's word on the match state.
@rpc("authority", "call_local", "reliable")
func _sync(new_state: int, duration: float, new_scores: Array, new_round: int, banner_text: String,
		ff: bool, to_win: int, minutes: int) -> void:
	state = new_state as State
	time_left = duration
	scores = new_scores.duplicate()
	round_number = new_round
	banner = banner_text
	friendly_fire = ff
	rounds_to_win = to_win
	round_minutes = minutes
	changed.emit()


## Runs on every computer: the host's word on who's in the lobby.
@rpc("authority", "call_local", "reliable")
func _sync_lobby(entries: Array) -> void:
	if entries != lobby:
		lobby = entries
		lobby_changed.emit()


# --- Helpers ---------------------------------------------------------------------------------

func _sender() -> int:
	var sender := multiplayer.get_remote_sender_id()
	return sender if sender != 0 else multiplayer.get_unique_id()


func _player_for(peer_id: int) -> Node:
	var player := players_node.get_node_or_null(str(peer_id))
	return player if player and not player.is_queued_for_deletion() else null


func _players() -> Array[Node]:
	var list: Array[Node] = []
	for player in players_node.get_children():
		if not player.is_queued_for_deletion():
			list.append(player)
	return list


func _team_counts() -> Array:
	var counts := [0, 0]
	for player in _players():
		counts[player.get("team")] += 1
	return counts


func _alive_counts() -> Array:
	var counts := [0, 0]
	for player in _players():
		if player.get("alive"):
			counts[player.get("team")] += 1
	return counts


func _both_teams_present() -> bool:
	var counts := _team_counts()
	return counts[TEAM_OPS] > 0 and counts[TEAM_TERRORISTS] > 0
