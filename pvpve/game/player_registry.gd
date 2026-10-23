class_name PlayerRegistry
extends RefCounted
## Who is in the match. Players are referred to by id everywhere in gameplay code,
## never by node, so the same ids can travel over the network later.
## The human host is always id 1 (the Godot convention for the server peer).

enum Kind { HUMAN, BOT, DUMMY }

const HOST_ID := 1

class Record extends RefCounted:
	var id := 0
	var kind := 0
	var display_name := ""
	var player: Player

var _records: Dictionary = {}
var _next_bot_id := 2


func add(kind: int) -> Record:
	var record := Record.new()
	record.kind = kind
	if kind == Kind.HUMAN and not _records.has(HOST_ID):
		record.id = HOST_ID
	else:
		while _records.has(_next_bot_id):
			_next_bot_id += 1
		record.id = _next_bot_id
		_next_bot_id += 1
	_records[record.id] = record
	return record


func remove(id: int) -> void:
	_records.erase(id)


func get_record(id: int) -> Record:
	return _records.get(id)


func ids() -> Array[int]:
	var result: Array[int] = []
	for id: int in _records:
		result.append(id)
	result.sort()
	return result


func count() -> int:
	return _records.size()


func count_kind(kind: int) -> int:
	var total := 0
	for id: int in _records:
		if _records[id].kind == kind:
			total += 1
	return total
