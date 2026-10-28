class_name WyrdScheduler
extends RefCounted

## Fixed-work queues for one game tick.
##
## @experimental
## Queues, in round-robin order: waits, rumor, publish, cache_refresh, generate,
## ai_prefetch. A unit is one waiting-condition recheck, one rumor hop, one
## slice of a frozen issue, one cache-entry rebuild, one generate offer, or one
## AI pre-fetch visit. [code]run[/code] spends at most the tick budget. Token
## queues keep a read cursor so a unit does not shift the array. The saved
## tokens are the ones still waiting. Generate and AI pre-fetch have no tokens.
## Their shares default to 0, so each runs only by spill when it has work and
## the earlier queues are idle. AI pre-fetch has work only when AI is active
## and a bark sweep has storylets left.
## Each queue's config weight is its share of that budget. Share a queue cannot
## use moves to the earliest queue that still has work, so a waits-only tick
## still spends the whole budget. A pass that would only run rumor is handled
## in one loop, including a spill onto rumor from an earlier idle queue. The
## loop stops when another queue would run, after finishing any later queue
## that the hop just gave work. Unfinished items stay in queue order. The
## round-robin starts at waits every tick. Token queues and the dirty waits
## are saved in [code]flight.scheduler[/code]. The leftover slice is saved there too.

const QUEUE_COUNT := 6
## waits, rumor, publish, and cache_refresh. Generate and AI pre-fetch are not
## in [code]spent[/code] or [code]carry[/code].
const _SAVED_QUEUES := 4


static func queues() -> PackedStringArray:
	return PackedStringArray(["waits", "rumor", "publish", "cache_refresh", "generate", "ai_prefetch"])
## One game minute, in units. 720 divides a 30 fps slice and a 144 fps slice
## when one real second advances one game minute.
const SLICE_UNITS_PER_MINUTE := 720

var last_units: int = 0

var trace_hook: Callable = Callable()
## [code]() -> bool[/code]. When this is valid and false, queue traces are not built.
var tracing_of: Callable = Callable()
var rumor_handler: Callable = Callable()
var publish_handler: Callable = Callable()
var cache_handler: Callable = Callable()
## [code]() -> bool[/code]. True when a generate handler is set and an offer is waiting.
var generate_has_work: Callable = Callable()
## [code]() -> void[/code]. Hands the oldest offer to the generate handler.
var generate_unit: Callable = Callable()
## [code]() -> int[/code]. Pending offers when a handler is set, otherwise 0.
var generate_pending: Callable = Callable()
## [code]() -> bool[/code]. True when AI is active and a bark sweep has storylets left.
var ai_prefetch_has_work: Callable = Callable()
## [code]() -> void[/code]. Visits the next bark storylet in the sweep.
var ai_prefetch_unit: Callable = Callable()
## [code]() -> int[/code]. Storylets left in the sweep, otherwise 0.
var ai_prefetch_carry: Callable = Callable()
## Set when [method mark] is given indexes. Not saved and not traced.
## The runtime clears it when a bark sweep is armed.
var marked: bool = false

var _waits := WyrdTickQueue.new()
var _rumor: Array[String] = []
var _publish: Array[String] = []
var _cache: Array[String] = []
var _rumor_at: int = 0
var _publish_at: int = 0
var _cache_at: int = 0


func clear() -> void:
	_waits.clear()
	_rumor.clear()
	_publish.clear()
	_cache.clear()
	_rumor_at = 0
	_publish_at = 0
	_cache_at = 0
	last_units = 0


## Drops rumor, publish, and cache items. Waiting conditions stay.
func clear_carry() -> void:
	_rumor.clear()
	_publish.clear()
	_cache.clear()
	_rumor_at = 0
	_publish_at = 0
	_cache_at = 0


## Drops the dirty set. Watched conditions stay watched.
func clear_dirty() -> void:
	_waits.restore_dirty([])


func watch(index: int) -> void:
	_waits.watch(index)


func unwatch(index: int) -> void:
	_waits.unwatch(index)


func mark(indexes: PackedInt32Array) -> void:
	_waits.mark(indexes)
	if not indexes.is_empty():
		marked = true


func dirty_count() -> int:
	return _waits.dirty_count()


func is_dirty(index: int) -> bool:
	return _waits.is_dirty(index)


func last_rechecks() -> int:
	return _waits.last_rechecks


func recheck_some(indexes: PackedInt32Array, eval_one: Callable) -> PackedInt32Array:
	return _waits.recheck_some(indexes, eval_one)


## Appends one rumor hop, frozen issue, or cache rebuild. Tokens stay in order.
func push(queue: String, token: String) -> void:
	match queue:
		"rumor":
			_rumor.append(token)
			_emit(queue, 0, _live(_rumor, _rumor_at))
		"publish":
			_publish.append(token)
			_emit(queue, 0, _live(_publish, _publish_at))
		"cache_refresh":
			_cache.append(token)
			_emit(queue, 0, _live(_cache, _cache_at))
		"generate", "ai_prefetch":
			return
		_:
			push_error("WyrdScheduler.push: unknown queue \"%s\"" % queue)


func carry(queue: String) -> int:
	match queue:
		"waits":
			return _waits.dirty_count()
		"rumor":
			return _live(_rumor, _rumor_at)
		"publish":
			return _live(_publish, _publish_at)
		"cache_refresh":
			return _live(_cache, _cache_at)
		"generate":
			if generate_pending.is_valid():
				return int(generate_pending.call())
			return 0
		"ai_prefetch":
			if ai_prefetch_carry.is_valid():
				return int(ai_prefetch_carry.call())
			return 0
		_:
			return 0


## Token queues and dirty waits. Empty arrays are omitted. The slice is added by the save.
func export_carry() -> Dictionary:
	var out := {}
	var cache := _token_rows(_cache, _cache_at)
	if not cache.is_empty():
		out["cache_refresh"] = cache
	var publish := _token_rows(_publish, _publish_at)
	if not publish.is_empty():
		out["publish"] = publish
	var rumor := _token_rows(_rumor, _rumor_at)
	if not rumor.is_empty():
		out["rumor"] = rumor
	var waits: Array = []
	for index in _waits.dirty_indexes():
		waits.append(int(index))
	if not waits.is_empty():
		out["waits"] = waits
	return out


## Replaces rumor, publish, and cache tokens, and the dirty waits.
## Does not log. Waiting conditions stay watched.
func import_carry(data: Dictionary) -> void:
	_cache = _as_tokens(data.get("cache_refresh", []))
	_publish = _as_tokens(data.get("publish", []))
	_rumor = _as_tokens(data.get("rumor", []))
	_cache_at = 0
	_publish_at = 0
	_rumor_at = 0
	var waits: Array = []
	var raw: Variant = data.get("waits", [])
	if raw is Array:
		waits = raw
	_waits.restore_dirty(waits)


func carry_tokens(queue: String) -> PackedStringArray:
	var items: Array[String] = []
	var at := 0
	match queue:
		"rumor":
			items = _rumor
			at = _rumor_at
		"publish":
			items = _publish
			at = _publish_at
		"cache_refresh":
			items = _cache
			at = _cache_at
		_:
			return PackedStringArray()
	var out := PackedStringArray()
	for index in range(at, items.size()):
		out.append(items[index])
	return out


## [param weights] match [method queues]. [param waits_eval] receives a condition index.
func run(budget: int, weights: PackedInt32Array, waits_eval: Callable) -> Dictionary:
	_compact_queues()
	var cap := budget if budget > 0 else 0
	var shares: Array[int] = []
	var split := apportion(_weights(weights), cap)
	for index in split.size():
		shares.append(int(split[index]))
	var spent := PackedInt32Array()
	spent.resize(QUEUE_COUNT)
	var total := 0
	var guard := cap * 3 + 4
	while total < cap and guard > 0:
		guard -= 1
		if _pass_is_rumor_only(shares):
			var extra := _drain_rumor(shares, spent, cap, total, waits_eval)
			total += extra
			if extra > 0:
				continue
		var ran := false
		for index in QUEUE_COUNT:
			if total >= cap or shares[index] <= 0:
				continue
			if not _run_one(index, waits_eval):
				continue
			shares[index] -= 1
			spent[index] = int(spent[index]) + 1
			total += 1
			ran = true
		if ran:
			continue
		if not _spill_one(shares):
			break
	_waits.last_rechecks = int(spent[0])
	last_units = total
	var left := PackedInt32Array([
		_waits.dirty_count(),
		_live(_rumor, _rumor_at),
		_live(_publish, _publish_at),
		_live(_cache, _cache_at),
	])
	var names := queues()
	for index in _SAVED_QUEUES:
		if int(spent[index]) > 0 or int(left[index]) > 0:
			_emit(String(names[index]), int(spent[index]), int(left[index]))
	var generate_spent := int(spent[4])
	var generate_carry := carry("generate")
	if generate_spent > 0 or generate_carry > 0:
		_emit("generate", generate_spent, generate_carry)
	var ai_prefetch_spent := int(spent[5])
	var ai_prefetch_left := carry("ai_prefetch")
	if ai_prefetch_spent > 0 or ai_prefetch_left > 0:
		_emit("ai_prefetch", ai_prefetch_spent, ai_prefetch_left)
	var spent_saved := PackedInt32Array([
		int(spent[0]),
		int(spent[1]),
		int(spent[2]),
		int(spent[3]),
	])
	return {
		"ai_prefetch_carry": ai_prefetch_left,
		"ai_prefetch_spent": ai_prefetch_spent,
		"carry": left,
		"generate_carry": generate_carry,
		"generate_spent": generate_spent,
		"spent": spent_saved,
		"total": total,
	}


static func apportion(weights: PackedInt32Array, budget: int) -> PackedInt32Array:
	var shares := PackedInt32Array()
	shares.resize(QUEUE_COUNT)
	if budget <= 0:
		return shares
	var sum := 0
	for index in QUEUE_COUNT:
		sum += _weight_at(weights, index)
	if sum <= 0:
		shares[0] = budget
		return shares
	var frac: Array[float] = []
	var used := 0
	for index in QUEUE_COUNT:
		var weight := _weight_at(weights, index)
		var exact := float(weight) * float(budget) / float(sum)
		var whole := int(floor(exact))
		shares[index] = whole
		frac.append(exact - float(whole))
		used += whole
	var left := budget - used
	while left > 0:
		var best := 0
		var best_frac := -1.0
		for index in frac.size():
			if frac[index] > best_frac:
				best = index
				best_frac = frac[index]
		shares[best] = int(shares[best]) + 1
		frac[best] = -1.0
		left -= 1
	return shares


func _weights(weights: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(QUEUE_COUNT)
	for index in mini(weights.size(), out.size()):
		out[index] = maxi(int(weights[index]), 0)
	return out


static func _weight_at(weights: PackedInt32Array, index: int) -> int:
	if index < 0 or index >= weights.size():
		return 0
	return maxi(int(weights[index]), 0)


## True when this pass would run a rumor hop and no other queue, or when the
## pass would run nothing and the spill would land on rumor.
func _pass_is_rumor_only(shares: Array[int]) -> bool:
	for index in QUEUE_COUNT:
		if index == 1:
			continue
		if shares[index] > 0 and _has_work(index):
			return false
	var rumor_work := _rumor_at < _rumor.size()
	if shares[1] > 0 and rumor_work:
		return true
	if not rumor_work or shares[1] > 0:
		return false
	return _waits.dirty_count() == 0


## Rumor hops, in queue order, while each pass would only run rumor.
## Idle share moves the same way [method _spill_one] does. A hop that gives a
## later queue work runs that queue before the loop stops.
func _drain_rumor(
	shares: Array[int],
	spent: PackedInt32Array,
	cap: int,
	total: int,
	waits_eval: Callable
) -> int:
	var ran := 0
	while total + ran < cap and _pass_is_rumor_only(shares):
		if shares[1] <= 0:
			if not _spill_one(shares):
				break
			continue
		if not _take_rumor():
			break
		shares[1] = int(shares[1]) - 1
		spent[1] = int(spent[1]) + 1
		ran += 1
		for index in range(2, QUEUE_COUNT):
			if total + ran >= cap or shares[index] <= 0:
				continue
			if not _run_one(index, waits_eval):
				continue
			shares[index] = int(shares[index]) - 1
			spent[index] = int(spent[index]) + 1
			ran += 1
	return ran


func _spill_one(shares: Array[int]) -> bool:
	var donor := -1
	for index in shares.size():
		if shares[index] > 0:
			donor = index
			break
	if donor < 0:
		return false
	var needy := -1
	for index in QUEUE_COUNT:
		if _has_work(index):
			needy = index
			break
	if needy < 0:
		return false
	shares[donor] -= 1
	shares[needy] += 1
	return true


func _has_work(index: int) -> bool:
	match index:
		0:
			return _waits.dirty_count() > 0
		1:
			return _rumor_at < _rumor.size()
		2:
			return _publish_at < _publish.size()
		3:
			return _cache_at < _cache.size()
		4:
			return generate_has_work.is_valid() and bool(generate_has_work.call())
		5:
			return ai_prefetch_has_work.is_valid() and bool(ai_prefetch_has_work.call())
		_:
			return false


func _run_one(index: int, waits_eval: Callable) -> bool:
	match index:
		0:
			return _waits.tick(1, waits_eval) == 1
		1:
			return _take_rumor()
		2:
			return _take_publish()
		3:
			return _take_cache()
		4:
			if not generate_unit.is_valid():
				return false
			generate_unit.call()
			return true
		5:
			if not ai_prefetch_unit.is_valid():
				return false
			ai_prefetch_unit.call()
			return true
		_:
			return false


func _take_rumor() -> bool:
	if _rumor_at >= _rumor.size():
		return false
	var token := String(_rumor[_rumor_at])
	_rumor_at += 1
	if rumor_handler.is_valid():
		rumor_handler.call(token)
	return true


## A publish handler that returns false keeps the token for the next unit.
func _take_publish() -> bool:
	if _publish_at >= _publish.size():
		return false
	var token := String(_publish[_publish_at])
	var done := true
	if publish_handler.is_valid():
		var result: Variant = publish_handler.call(token)
		if result is bool:
			done = bool(result)
	if done:
		_publish_at += 1
	return true


func _take_cache() -> bool:
	if _cache_at >= _cache.size():
		return false
	var token := String(_cache[_cache_at])
	_cache_at += 1
	if cache_handler.is_valid():
		cache_handler.call(token)
	return true


func _live(items: Array[String], at: int) -> int:
	return maxi(items.size() - at, 0)


func _compact_queues() -> void:
	if _rumor_at >= 512 and _rumor_at * 2 >= _rumor.size():
		_rumor = _tail(_rumor, _rumor_at)
		_rumor_at = 0
	if _publish_at >= 512 and _publish_at * 2 >= _publish.size():
		_publish = _tail(_publish, _publish_at)
		_publish_at = 0
	if _cache_at >= 512 and _cache_at * 2 >= _cache.size():
		_cache = _tail(_cache, _cache_at)
		_cache_at = 0


func _tail(items: Array[String], at: int) -> Array[String]:
	var next: Array[String] = []
	var count := items.size() - at
	if count <= 0:
		return next
	next.resize(count)
	for index in count:
		next[index] = items[at + index]
	return next


func _token_rows(items: Array[String], at: int) -> Array:
	var out: Array = []
	for index in range(maxi(at, 0), items.size()):
		out.append(items[index])
	return out


func _as_tokens(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if raw is Array:
		for item in raw:
			out.append(WyrdSave.text_of(item, ""))
	return out


func _emit(queue: String, units: int, left: int) -> void:
	if tracing_of.is_valid() and not bool(tracing_of.call()):
		return
	if not trace_hook.is_valid():
		return
	trace_hook.call({
		"carry": left,
		"key": queue,
		"queue": queue,
		"units": units,
	})
