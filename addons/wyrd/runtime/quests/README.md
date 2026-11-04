# quests

`WyrdQuestRunner` is the facade's `quests` object.

A generated instance id is `<template>#<n>`. The counter is the last `n` for that template and is saved under `generator`. `create_instance` is internal: tests call it, and there is no `Wyrd` facade method. It freezes the supplied casts, then starts the instance on the normal quest path. A finished instance keeps its casts. Hand-written quests are unchanged.

Statuses: `dormant`, `available`, `active`, `completed`, `failed`, `abandoned`, `unavailable`. A true `start when` becomes `available` and then `active` in the same check. There is no accept step.

Entry steps (journal, effect, scene offer) run in source order, once. A variant whose slot state matches replaces that body. `on_empty: wait` holds the stage when a slot that stage references is empty or contested and no variant matched. A reference is a scene `with` name, a variant slot, or a `holder`, `filled`, or `slot_state` call in a step or condition, including variant bodies and region stages. `Wyrd.quests.summary(quest)` returns those frozen journal entries joined in order, or validated cached journal-summary text.

`waiting_reason` is `host:<screen>`, `scene:<id>`, `waits_until: <text>`, `on_empty`, or empty.

`await_host` is an entry step. It calls `request_host_step` and pauses the steps after it. `complete_host_step` continues them. A scene offer does not pause the steps before it; the stage waits on the scene after those steps have run.

A `region` inside a stage runs at the same time as that stage's other regions. `quests.regions_of(quest)` returns the active leaves. They are saved on the quest row. A region scene or host step uses the quest's single open slot and waits when that slot is busy. With tracing on, a leaf change logs `region`. `WyrdSequences` is the facade's `sequences` object. `progress(id)` and `done(id)` read a sequence. Partial progress is saved under `sequences`. A step, finish, reset, or expiry logs `sequence` when tracing is on.
