extends "res://scripts/gameplay/arena.gd"

## Arena that blocks real scene changes and restarts so only the post-result
## destination can be observed.
##
## Tests do not put this in the tree. Combat, audio, and enemy spawning never
## start, so `_on_result_dismissed()` state transitions can be checked on their
## own.

var restart_calls: int = 0
var title_calls: int = 0
var title_requested_shrine: bool = false
var settlement_calls: int = 0
var record_submit_calls: int = 0
var release_audio_calls: int = 0
var title_store_open_calls: int = 0
var _settlement_responses: Array = []
var _record_responses: Array = []


func prepare(result_control: Control, ladder_control: Control, score: int) -> void:
	_result = result_control
	_ladder = ladder_control
	_board_score = score
	_board_rank = "A"
	_board_cycles = 3


func request_restart() -> void:
	_on_result_dismissed(ResultAction.RESTART)


func request_shrine() -> void:
	_on_result_dismissed(ResultAction.SHRINE)


func request_record() -> void:
	_on_result_record()


func request_continue_purchase() -> void:
	await _on_continue_purchase_requested()


func set_board_score(score: int) -> void:
	_board_score = score


func complete_ladder() -> void:
	_on_ladder_closed()


func configure_persistence(
		settlement_responses: Array, record_responses: Array) -> void:
	_settlement_responses = settlement_responses.duplicate(true)
	_record_responses = record_responses.duplicate()


func persist_finished_result(score: int, rank: String) -> bool:
	return _persist_finished_result(score, rank)


func retry_pending_persistence() -> bool:
	return _retry_pending_result_persistence()


func persistence_pending() -> bool:
	return _run_settlement_pending or _record_submission_pending


func run_shards_awarded() -> int:
	return _run_shards_awarded


func pending_action() -> int:
	return int(_pending_result_action)


func no_pending_action() -> int:
	return int(ResultAction.NONE)


func restart_pending_action() -> int:
	return int(ResultAction.RESTART)


func leaving_for_title() -> bool:
	return _leaving_for_title


func title_store_open_requested() -> bool:
	return title_store_open_calls == 1


func _restart() -> void:
	restart_calls += 1


func _return_to_title(open_shrine: bool = false) -> void:
	title_calls += 1
	title_requested_shrine = open_shrine


func _release_audio() -> void:
	release_audio_calls += 1


func _mark_title_store_open() -> void:
	title_store_open_calls += 1


func _vault_settle_run_score(_score: int, _already_awarded: int) -> Dictionary:
	settlement_calls += 1
	if _settlement_responses.is_empty():
		return {
			"status": Vault.RunSettlementStatus.NO_CHANGE,
			"awarded": 0,
		}
	return _settlement_responses.pop_front()


func _records_submit_result(_score: int, _rank: String) -> int:
	record_submit_calls += 1
	if _record_responses.is_empty():
		return Records.SubmitResult.NOT_BEST
	return _record_responses.pop_front()
