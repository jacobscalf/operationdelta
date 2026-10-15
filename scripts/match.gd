extends Node
## The match referee. Runs warm-up, rounds and scoring.
## The host makes every decision here and tells the other computers with _sync().
##
## Flow:  WAITING (warm-up, respawns on) -> COUNTDOWN (frozen) -> LIVE (one life each)
##        -> ROUND_OVER -> next COUNTDOWN ... -> MATCH_OVER -> back to WAITING.
## Practice mode stays in PRACTICE forever (respawns on, no rounds).

enum State { PRACTICE, WAITING, COUNTDOWN, LIVE, ROUND_OVER, MATCH_OVER }

const TEAM_OPS := 0
const TEAM_TERRORISTS := 1
const TEAM_NAMES := ["OPS", "TERRORISTS"]
const TEAM_COLORS := [Color(0.35, 0.6, 1.0), Color(1.0, 0.45, 0.3)]

const COUNTDOWN_TIME := 5.0
const ROUND_OVER_TIME := 6.0
const MATCH_OVER_TIME := 12.0
const WARMUP_RESPAWN_TIME := 5.0

## Emitted on every computer whenever the state changes, e.g. for the HUD.
signal changed

var state := State.WAITING
var time_left := 0.0
var scores := [0, 0]
var round_number := 0
var banner := ""  # big message in the middle of the screen
var friendly_fire := false
var rounds_to_win := 4

var _round_time := 300.0
## Set by main.gd: the node holding every player.
var players_node: Node
## Set by main.gd: Callable(team, index) -> Vector3 spawn position.
var spawn_point_for: Callable


func _ready() -> void:
	friendly_fire = Network.friendly_fire
	rounds_to_win = Network.rounds_to_win
	_round_time = Network.round_minutes * 60.0
	if Network.mode == Network.Mode.PRACTICE:
		state = State.PRACTICE


func _process(delta: float) -> void:
	time_left = maxf(time_left - delta, 0.0)
	if not multiplayer.is_server():
		return

	match state:
		State.WAITING:
			if _both_teams_present():
				_start_countdown()
		State.COUNTDOWN:
			if not _both_teams_present():
				_enter_waiting()
			elif time_left <= 0.0:
				_set_state(State.LIVE, _round_time, "")
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
					_enter_waiting()
		State.MATCH_OVER:
			if time_left <= 0.0:
				scores = [0, 0]
				round_number = 0
				_enter_waiting()


# --- Questions other scripts ask -----------------------------------------------------

## Players can't move or shoot during the countdown before a round.
func is_frozen() -> bool:
	return state == State.COUNTDOWN


## In warm-up and practice you come back after a few seconds; in a live round you don't.
func respawns_enabled() -> bool:
	return state == State.PRACTICE or state == State.WAITING


## Should a player who joins right now start alive, or wait for the next round?
func joiner_starts_alive() -> bool:
	return state == State.PRACTICE or state == State.WAITING or state == State.COUNTDOWN


# --- Events the host reports ------------------------------------------------------------

## Host only. Called by a player when they die.
func on_player_killed(victim: Node) -> void:
	if respawns_enabled():
		await get_tree().create_timer(WARMUP_RESPAWN_TIME).timeout
		if is_instance_valid(victim) and respawns_enabled() and not victim.get("alive"):
			victim.call("respawn_at", spawn_point_for.call(victim.get("team"), -1))
	elif state == State.LIVE:
		_check_round_end()


## Host only. Called when a player disconnects (after their node is gone).
func on_player_left() -> void:
	if state == State.LIVE:
		_check_round_end()


## Host only. Sends the current state to a player who just joined.
func send_state_to(peer_id: int) -> void:
	_sync.rpc_id(peer_id, state, time_left, scores, round_number, banner, friendly_fire, rounds_to_win)


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


func _enter_waiting() -> void:
	for player in _players():
		if not player.get("alive"):
			player.call("respawn_at", spawn_point_for.call(player.get("team"), -1))
	_set_state(State.WAITING, 0.0, "")


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


func _set_state(new_state: State, duration: float, banner_text: String) -> void:
	_sync.rpc(new_state, duration, scores, round_number, banner_text, friendly_fire, rounds_to_win)


## Runs on every computer: the host's word on the match state.
@rpc("authority", "call_local", "reliable")
func _sync(new_state: int, duration: float, new_scores: Array, new_round: int, banner_text: String,
		ff: bool, to_win: int) -> void:
	state = new_state as State
	time_left = duration
	scores = new_scores.duplicate()
	round_number = new_round
	banner = banner_text
	friendly_fire = ff
	rounds_to_win = to_win
	changed.emit()


# --- Helpers ---------------------------------------------------------------------------------

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


## Host only: which team should a new player join? The smaller one (Ops on a tie).
func team_for_new_player() -> int:
	var counts := _team_counts()
	return TEAM_TERRORISTS if counts[TEAM_TERRORISTS] < counts[TEAM_OPS] else TEAM_OPS
