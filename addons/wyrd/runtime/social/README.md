# social

`WyrdSocial` stores relationship kinds and axis baselines. An axis is the baseline plus deed contributions.

A deed adds `delta × decayed weight × kind scale` to `axis(observer, subject)` when `subject` is the actor and `observer` is the target or a witness. Deltas come from `WyrdConfig.set_axis_delta`. The kind scale starts at 1. Each kind the observer holds toward the subject multiplies by `WyrdConfig.kind_scale` for that axis. A kind in the other direction does not. The baseline is not scaled. Scales are host config and are not saved.

`reputation(subject, group)` is the mean `disposition(member, subject)` of `WyrdWorldAdapter.members(group)`. The subject is excluded. Duplicate members count once. No members returns 0. The value is rounded like an axis sum. It is not stored in the save; kinds, baselines, and deeds reconstruct it. Emitting `groups_changed`, or calling `invalidate_groups`, wakes a condition that reads it. One `reputation` line is logged per call when tracing is on.

Disposition is `disposition_default + affinity / 2`, clamped to 0..100, unless the host registers a formula. The formula is `(a, b, axes) -> int` and is not saved.

`path_exists(source, target, kinds, max_hops)` is true when `target` is reachable from `source` in at most `max_hops` directed steps. A step may use any listed kind. `source == target` is true when `max_hops` is at least 0. Neighbors are visited in sorted order. A condition that calls it is marked when a relationship changes. It is not marked on every minute.

Axes, disposition, reputation, and `path_exists` share one cache for the current time bucket. A read stores a missing entry immediately. `reputation` checks the cache stamp once, then fills the same axis and disposition keys a direct read would store. `set_cache(false)` recomputes and does not store. A relationship, deed, membership, formula, config, or time-bucket change drops every entry and queues no `cache_refresh` unit. Entries refill on read. The axis walk uses `witness_indexes` as a membership set when that list is shorter than the actor's rows, and still adds in actor-log order. Cache entries are not saved. `cache_refresh` tokens from an older save still load and drain. With tracing on, one `wyrd social cache` line is logged for an invalidation, a miss, or a hit. Load does not log one. A precise rumor walks `targets` for one kind list. Adoption reads disposition, which uses this cache.
