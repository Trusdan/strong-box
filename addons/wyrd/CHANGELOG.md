# Changelog

## Unreleased

## 1.0.0 - 2026-10-24

1.0 release (M12 PRs 1–8: #122–#128 and this PR). `addons/wyrd/VERSION` is `1.0.0`. `plugin.cfg` version is `1.0.0`. The stable surface, the save promise, the deprecation policy, and the support note are in `docs/stability.md`. Save schema stays 4, and 1.0.0 loads every schema 1–4 save. `known` is removed; use `knows`. Benchmarks are informational and do not gate 1.0. Known: the `load.time` median was 1.336 s at the `v0.9.0-m11` tag run (`bench/TREND.md`) and 1.142 s → 0.891 s locally after the M12 load-time pass (`bench/README.md`); the `v1.0.0` tag run records the 1.0.0 number. The tag `v1.0.0` and the first GitHub Release are cut only on request.

- **Performance:** loading a current-schema save skips the deep copy of deed rows and reads the deed time bucket once per import. Saves, traces and replays are unchanged.
- **Example:** Gullhaven adds the secret role `smugglers_contact` and a `hostile` guild variant. `example/versions/gullhaven_next/` renames one ferry stage with `was:`. A coverage test lists the 1.0 features. The playtest gains a route list, a load-report panel, a journal grouped by quest, and Tell secret.
- **Docs:** `docs/tutorial.md` walks the ferry quest in the playtest.
- **Docs:** a docs site built from `docs/` for GitHub Pages, with a quick start, adapter guide, cookbook and design rationale. A workflow builds it and checks its links on every pull request.
- **Docs:** `docs/api/`, an API reference generated from the `##` doc comments by `tools/gen_api_docs.sh`, with Stable and Experimental marks. CI checks that it is current.
- **Docs:** `docs/language.md`, the language 1 reference, replaces the grammar and draft files, which now point to it.
- **Added:** `scene_started`, the facade relays, `register_disposition_formula`, the deprecation table and warning, `docs/stability.md`, and the stable marks.
- **Removed:** `known`, now `E_KNOWN_REMOVED`; use `knows`. Breaking for content.
- A golden snapshot test of the public API surface, with a list of where the code differs from the design.
- 1.0 exit suite (`tests/scenario/test_1_0_exit.gd`), version `1.0.0`, and the support note in `docs/stability.md`.

## 0.9.0-m11 - 2026-10-23

M11 Migration and hardening (M11 PRs 1–8, including 6a (#117) and 6b (#118), plus #110). `addons/wyrd/VERSION` is `0.9.0-m11`. `plugin.cfg` version is `0.9.0-m11`. Save schema stays 4. Saves without aliases or removed content load as before. The tag `v0.9.0-m11` is cut only on request.

- M11 exit suite (`tests/migration/test_m11_exit.gd`) and `docs/migration.md`, a guide to renaming and removing content.
- Performance: a save is deep-copied on load only when an alias or a missing stage rewrites it, deed rows are shape-checked without sorting each row, quest expiry walks only instances that can expire, and host-call tracing allocates nothing while tracing is off. Saves, traces and replays are unchanged.
- Host calls that change Wyrd state (fact, deed, relationship, role, topic and quest writes, `director.query`, and AI `cancel` and `clear_cache`) are recorded as `host_call` trace rows and replayed by `WyrdTrace.replay`. Calls Wyrd makes inside its own work are not recorded. Calls that change nothing are skipped. Traces without these rows replay as before.
- Determinism replay suite: every Gullhaven route and every runtime matrix and exit scenario from M4 to M10 is recorded and replayed twice in the same build with byte-identical traces, including after a save and a load into a fresh runtime; a call inventory test lists every public call as a replay input or as not one, with a reason.
- Replay fixes: a social cache invalidation no longer queues `cache_refresh` units, so the saved scheduler carry and the gameplay save are the same whether the cache was warm or cold (for example after a load); `cache_refresh` tokens in older saves still load and drain. `gen_accept` rows carry `origin` (`host` or `queue`), and `WyrdTrace.replay` replays only host accepts. Emit, proposal and AI request ids restart after a load.
- Missing-stage handling on load: a quest on a removed stage moves by `on_missing_stage:`, then its saved `trail`, then its first stage, arriving entered with no effects; a removed sub-state leaf restarts its region; each move adds a `missing_stage` row with `W_SAVE_STAGE`. Quest rows save an optional `trail`, rewritten through stage aliases. A removed hand-written quest is kept and reported as a `kept` row. New compile error `E_MISSING_STAGE_TARGET`. Document aliases also rewrite periodic publish state and verb aliases the verbs in in-flight rumors; a saved role that neither the content nor the host defines adds a `kept` row.
- Load rewrites saves through the content's `was:` alias tables (`WyrdSaveMigrate`): quest stages, role ids, deed verbs and document ids. Each rewrite adds an `alias` load-report row; an old id whose new id is also saved is dropped with `W_SAVE_ALIAS`.
- Content aliases: `was:` on stage, role and document headers and an alias-only `verb` statement, resolved at compile time into alias tables (in `export-json`, and in the manifest hash only when non-empty), with `E_ALIAS_CONFLICT`, `E_ALIAS_DUPLICATE` and `E_ALIAS_CYCLE`. Nothing reads the tables at runtime yet.
- Replay: a trace row whose presence or content depends on measured time sets `timing` true. The scheduler frame warning (`queue=frame`, `us`) is that row. `WyrdTrace.diff` leaves timing rows out and still compares every other row exactly. The rows stay in the trace.
- Migration fixture tests: a schema 1 save and two earlier Gullhaven saves load and round-trip.
- Load report rows and `load_report_ready`; a refused or malformed save is rejected before anything is imported; seeded loader fuzz.

## 0.8.0-m10 - 2026-10-22

M10 AI hooks (M10 PRs 1–9, PR 5 in two parts, plus the report-only performance workflow change). `addons/wyrd/VERSION` is `0.8.0-m10`. `plugin.cfg` version is `0.8.0-m10`. Save schema stays 4. With the null provider, the default, no AI text is shown. The tag `v0.8.0-m10` is cut only on request.

- Bench: the milestone bench and the informational CI bench step add `ai.packet`, `ai.validate`, `ai.present_overhead` (null provider, with authored and fake-provider timings beside it) and `ai.cache_lookup` (256 entries), timed on a small inline pack with fake providers. They are trend rows judged only by the report-only regression check, with no absolute ceiling. No model is downloaded. `bench/scale_pack.sha256` is unchanged; no change under `addons/wyrd`.
- Bench: the hosted performance workflow reports a regression or a budget overage and does not fail the job for it. A checksum that changes between samples still fails the job. The tag run still records `bench/results/<tag>.json` and `bench/TREND.md` when the bench script exits 0. Pull requests still don't run the suite.
- AI: the provider interface (`WyrdAIProvider`, `WyrdAIRequest`, `WyrdAIResult`) and `Wyrd.ai` (`request`, `deliver`, `cancel`, `set_enabled`). The `null` provider (`WyrdNullAIProvider`) is registered by default and answers nothing. Delivered results are not shown or cached yet. A CI step checks that `addons/wyrd/` has no `await`, thread, network or process code. No behavior change; save schema stays 4.
- AI: content opts in with `#tag:ai` on spoken and storylet lines and `ai_context: [<fact keys>]` on storylets and scenes. `E_AI_LINE` rejects voiced, secrecy-tier and interpolating opt-ins; `E_AI_CONTEXT_UNKNOWN` and `W_AI_CONTEXT_RESOLVED_PER_QUERY` check the listed keys. `export-json` carries `ai_context`. Nothing reads them at runtime yet; no behavior change.
- AI: Wyrd builds the context packet for an opted-in line (`Wyrd.ai.packet_for_line`: authored text, speaker name and the roles the player may know, the `ai_context` facts the player knows, and the entity list; canonical JSON) and validates each delivered result in order: limits, names, `ai_banned_terms`, spoilers, and an optional `Wyrd.ai.register_classifier` hook. Results are still not shown or cached. No behavior change; save schema stays 4.
- AI: validated results are cached by a stable key (FNV-1a 64 of kind, canonical packet, provider id, prompt version and locale) with `ai_cache_max` entries (default 256, oldest inserted evicted first), and saved in an optional top-level `ai` key when `ai_save_cache` is true and the cache isn't empty. An older loader ignores the key; a malformed one warns `W_SAVE_AI` and is ignored. `ai_*` trace lines carry `key=`. Cached text is not shown yet. Save schema stays 4.
- AI: opted-in lines now show validated cached text for `bark_paraphrase` when the provider lists the current locale (`WyrdLineView.text_source` is `ai`; otherwise the authored line shows and dialogue never waits). Wyrd sends requests when a scene opens and when a topic menu opens, at most `ai_max_inflight` at once (default 4). Requests still open when their scene ends are cancelled; a late result is still validated and cached but never shown retroactively. `ai_deliver` is a recorded replay input. Trace lines `ai_prefetch`, `ai_use` and `ai_late`. No behavior change for content without opt-ins; save schema stays 4.
- AI: a sixth scheduler queue, `ai_prefetch` (`scheduler_share_ai_prefetch`, default 0, so it runs only on spill), sends `bark_paraphrase` requests for opted-in barks whose `when` holds. Barks use at most `ai_max_inflight - 1` open requests, and a bark request open for 60 game minutes is cancelled (a late result is still cached). The existing five-queue split is unchanged. Trace lines `scheduler queue=ai_prefetch` and `ai_sweep`. No behavior change for content without opt-ins; save schema stays 4.
- AI: an opted-in line that also has `#tag:gossip` uses kind `gossip`, whose packet adds up to 5 deeds the player knows (newest first). `Wyrd.quests.summary(quest)` returns the frozen journal entries joined in order, or validated cached `journal_summary` text, and requests one when missing; `summary_source` says which. `Wyrd.ai.host_text` reads cached text for host-called kinds such as `epilogue_stitch` and `tts_prep`. Host requests and summary calls are replay inputs. No behavior change for content without opt-ins; save schema stays 4.
- Example: a reference local AI provider (`example/ai/`) sends each request to an OpenAI-compatible server on 127.0.0.1 or localhost only, with one prompt per kind (prompt version 1), a JSON-schema reply, a seed from the cache key and a 10 s timeout. It has no API-key setting. The playtest's "Local AI flavor" toggle starts off. `docs/ai.md` covers a free setup with llama.cpp's `llama-server` and SmolLM2-360M-Instruct. CI uses a fake local server; no model is downloaded or committed. No change under `addons/wyrd`; save schema stays 4.
- Example: Gullhaven opts six lines into AI flavor. The `toll.depart` narrator line and the two lantern barks are `bark_paraphrase`. The tavern ferry-toll pair and the storm rumour are `gossip`, and the storm storylet lists `ai_context: [world.storm_heard]`. The authored text is unchanged. With AI off or the null provider, play is unchanged; the pack hash changes. The M10 exit suite runs on Gullhaven.

## 0.7.0-m9 - 2026-10-21

M9 procedural generator (M9 PRs 1–10 plus a lint fix). `addons/wyrd/VERSION` is `0.7.0-m9`. `plugin.cfg` version is `0.7.0-m9`. Save schema is 4. The tag `v0.7.0-m9` is cut only on request, after the M9 bench.

- Bench: the milestone bench adds `generator.propose`, `generator.cast_object`, `generator.cast_person`, `generator.validate`, `generator.tick`, `memory.generated`, `save.generated_bytes` and `load.generated` at the full profile, measured on the cast-candidate index (the bench world reports changes), from a `<pack>_templates/` sibling (eight tiered templates, 5,000 tagged objects, 32 pressure entries, 100 generated instances). `bench/scale_pack.sha256` is unchanged. A proposal's ceiling is the 2 ms frame warn, and the generated save and load share the flight ceilings. Other new ceilings warn until they are confirmed. The new metrics use smaller per-metric sample counts. Pull requests still don't run the suite.
- Casting: cast slots and params compile a cast plan from their top-level `and` clauses. For a world adapter that returns `reports_changes()` true and calls `Wyrd.invalidate_world(ids)` on entity changes, casts reuse the host's candidate answer and cache per-entity clause results until the next change. Other hosts scan as before. With tracing off, the generator no longer hashes candidates or builds `gen_*` lines. Cast results, traces with tracing on, and saves are unchanged. Save schema stays 4.
- Example: Gullhaven gains seven generated-quest templates (deliver, recover, investigate, escort and a three-tier recurring favor) and an M9 exit suite that validates, plays every route, saves mid-generation and replays them; version `0.7.0-m9`. Save schema stays 4.
- Generator: validators reject proposals that use missing, protected or out-of-bounds entities, or whose `assumes:` is false or contradicts what the player knows (`gen_reject`); rejected proposals retry up to `generator_retries` (8) with varied keys; `gen_cap` logs a `max_active` exclusion; an optional template `expires:` abandons old instances (`gen_expire`); `why-not <template>` and `generate --dry-run` explain picks; conditions can read `owner_of(<item>)`. An empty place is not a rejection. Save schema stays 4.
- Generator: propose/accept pick, cast and bind templates with per-decision seeds; the generate queue creates instances at the end of the tick; offers, proposals and accepts replay; conditions, effects and chance inside a generated instance use that instance's casts and params.
- Generator: `Wyrd.generator.offer` queues unsaved story pressure; `WyrdConfig.pressure_tiers` ranks tiers; template `on_deed` hooks queue deed offers; a fifth scheduler queue, `generate`, has share 0 by default (`W_TEMPLATE_TIER_UNKNOWN`, `W_TEMPLATE_TIER_ORDER` with `check --pressure-tiers`).
- Compiler: `template` blocks (params, when/priority/weight/max_active/tier/assumes/allow_protected) compile, link and lint like quests, with W_TEMPLATE_TIE, E_TEMPLATE_REF and E_TEMPLATE_UNKNOWN; content.templates is filled from the pack.
- Saves: schema 4. Generated quest instances (`<template>#<n>`) save with `template` and `n` on their quest row, and a `generator` block holds instance counters and casts; it is omitted when there are none. Schema 2 and 3 saves load as before, with an empty generator block. A schema 4 save is refused by an older Wyrd. A save whose template is no longer in the content keeps those instances ignored and warns `W_SAVE_TEMPLATE`. Conditions can read `active_count(<template>)`. Hand-written quests, their saves and traces are unchanged apart from `schema_version`.
- Fixed: CLI runs other than `check --watch` no longer print a `tick` on Nil script error after their output. CI runs every command headless and fails on a script error.
- Fixed: `tag-lines` proposes ids exactly where `check` requires them: no longer on a choice's skill-check line, and now on variant lines. Document titles and paragraphs still get ids. Ids already written never change; an untagged line after a fixed site may get a different proposed id.
- Fixed: `W_STAGE_UNREACHABLE` now follows a stage's `do … on_fail -> <stage>` target, also in variant bodies and region stages, so a stage reached only that way no longer warns. A `do … on_fail` in an `on <event>` handler is not a path, because handler effects do not divert. The warning text is unchanged. No golden and no Gullhaven result changes.
- Tests: a schema 3 Gullhaven save fixture loads and round-trips on every run, and a schema 3 save without `flight` is checked to clear the dirty waits. The flight check is pinned to schema 3, so a later schema bump can't change how schema 3 saves load. No behavior change; save schema stays 3.
- Quests: a slot can be cast from world objects or items by tag (`slot <name> kind: object|item mode: cast(has_tag(candidate, <tag>) and …)`). The world adapter's `candidates` gets the kind and tag. The pick is frozen at quest start and saved. The slot is `empty` when nothing matches and `locked_gone` when the object no longer exists or the item changed owner. `E_OBJECT_SUCCESSION` rejects a role or succession state on such a slot. Gullhaven adds the mooring post quest. Role casts are unchanged. Save schema stays 3.

## 0.6.4-m3 - 2026-10-20

M3 editor support in VS Code and the CLI (M3 PRs 1–8). `addons/wyrd/VERSION` is `0.6.4-m3`. `plugin.cfg` version is `0.6.4-m3`. Save schema stays 3. Corey cuts the tag `v0.6.4-m3` only when he asks.

- Fixed: the fact cross-reference counts storylet effects and scene effect lines as writers, so `W_FACT_NEVER_SET` no longer fires for facts set only there.
- Tools: a local VS Code extension in `tools/vscode-wyrd/` (not published) colors `.wyrd` files and adds the `$wyrd` problem matcher for `check` output. `.vscode/tasks.json` runs check and `tag-lines` through the `wyrd.godotPath` setting.
- CI: a `vscode` job runs grammar snapshot tests and builds the VSIX. Node is pinned in `tools/pins.env`.
- Docs: the in-Godot highlighting spike is closed with findings; the editor plugin stays a stub that registers nothing.
- CLI: `check --watch` re-checks a pack whenever a listed file changes. Each run is wrapped in `wyrd: check started` and `wyrd: check finished errors=<n> warnings=<n>`. Plain `check` output is unchanged.
- Tools: the VS Code extension adds the `$wyrd-watch` background problem matcher, and `.vscode/tasks.json` adds a check --watch task for Gullhaven.
- CI: a watch smoke step runs `check --watch` as a real process.
- CLI: `pot --manifest <path> [--out <file>]` writes a gettext POT of a pack's player text: dialogue, choices, storylet and journal lines, and document titles and paragraphs. `msgctxt` is the line id.
- Docs: the host checklist explains making `.po` files from `wyrd.pot` next to the game's own translations.
- Tools: `.vscode/tasks.json` adds a pot task for Gullhaven.
- CI: the POT is checked with gettext `msgfmt --check`.
- Lines with `{…}` now translate by template: the translation is compiled and its placeholders, named by their expression, are filled at display time. A translation whose placeholders don't match falls back to the source line with a warning and a `text_translate ok=false` trace row.
- Lints: `W_STAGE_UNREACHABLE` warns on a quest stage that no `->`, `advance` or region path reaches.
- `check --tiers a,b,c` (lowest first) adds `W_SECRECY_LEAK`, which warns when visible text at a lower secrecy tier shows a stored fact that only higher-tier content sets. Without `--tiers`, `check` output is unchanged.
- CLI: `defs --manifest <path>` writes a sorted ctags `tags` file of the pack's quests, stages, scenes, roles, storylets, documents and facts. With the free ctagsx extension, F12 and Ctrl+click in VS Code jump to the definition. The `Wyrd: defs (Gullhaven)` task writes the gitignored `tags` at the project root.
- Tools: the VS Code language configuration keeps dotted ids such as `harbor.rope_done` as one word.
- Tests: an M3 exit scenario checks that a Gullhaven edit shows as one `$wyrd` row through a watch cycle and clears when fixed, that `defs` has every demo F12 target, and that `pot` has scene lines and document paragraphs.
- Docs: `docs/m3-exit-demo.md` lists the manual VS Code demo steps and what CI proves for each M3 exit criterion.

## 0.6.3-m8 - 2026-10-19

M1–M3 gap work (gap PRs 1–6). `addons/wyrd/VERSION` is `0.6.3-m8`. `plugin.cfg` version is `0.6.3-m8`. Save schema stays 3. Corey cuts the tag `v0.6.3-m8` only when he asks.

- Golden tests cover the built-ins that had no snapshot, `learn` and `forget`, storylets, `lines:` sets, voiced variants, secrecy on lines, sequences, regions and handlers, events, periodic documents, and every compile-time diagnostic code. The statement golden adds a `publish` object when `period_minutes` is greater than zero. `tests/golden/test_golden_inventory.gd` fails when an expected file has no source, a diagnostic code is missing from the snapshots, or a built-in call is missing from a golden source. The allowlist is the four save codes and `E_RESOLVER_INVALIDATION`. `tests/golden/README.md` records the families, the update command, and the determinism rules.

- Readable `document` blocks take a title, `text: live` or `text: frozen`, `meta`, tags, secrecy tiers, pages, and paragraphs. `on_first_read:` and `on_read:` run effects. `~ create document <doc_id> copy <copy_id>` copies a frozen document. An unknown document is `E_DOCUMENT_UNKNOWN`. A live or periodic document is `E_DOCUMENT_NOT_FROZEN`. `has_read(reader, doc)` reads a `(reader, document)` pair. Those pairs are not stored facts. `Wyrd.documents` opens a document into a `WyrdDocumentView` and emits `document_read`. The `documents` save bag holds read flags and frozen copies. Schema stays 3. With tracing on, the lines are `wyrd document_open`, `wyrd document_copy`, and `wyrd document_stale`. Host replay rows are `open_document` and `create_copy`. export-json gains a `documents` key when a readable document exists. Gullhaven adds `ferry_schedule`, `reeve_letter`, and `dock_letter`. Content aliases, POT extraction, and `create_copy` params are not supported yet.

- `show_disabled_when` compiles the disabled condition. `disabled_when` is an alias and warns `W_DISABLED_WHEN_DEPRECATED`. A choice may start with `check <skill>(...) on_fail -> <label>`. A bad check is `E_CHECK_SYNTAX`. When `wyrd_commands.json` has `skills`, an unknown skill is `E_SKILL_UNKNOWN`. `WyrdSkillAdapter.check` answers a `WyrdSkillCheck`. `WyrdChoiceView` carries `check` and `check_args`. The roll is `WyrdRng.decision_unit` on stream `skill`. With tracing on, the line is `wyrd skill_check scene=%s choice=%s skill=%s roll=%s ok=%s reason=%s`. Replay compares that host answer. Choice effects restore `quest_id`, `scene_id`, and `choice_id`, so a later host role change aborts the scene `holder_left`. Gullhaven adds `dock_crate` and a `strength` skill. Save schema stays 3.

- `lock topic` compiles and runs. Unlocked topic ids live in `Wyrd.topics` and, when any exist, in the save bag `topics` (a sorted id list; a missing key clears it; an unknown id is kept). `Wyrd.topics.is_unlocked` and `Wyrd.topics.unlocked` are read-only. A repeat unlock traces `already` and does not emit `topic_unlocked` again. A lock of a topic that is not unlocked traces `not_unlocked` and does not warn. `Wyrd.dialogue.open(npc)` lists the sorted unlocked topics that have an eligible storylet for that npc and does not record a selection. `Wyrd.dialogue.ask_topic(npc, topic)` runs the winning storylet: a line or set emits `topic_answered`, and a `-> scene` body opens that scene. The facade relays `topic_unlocked` and `topic_locked`. A storylet `~` list runs on a director win, after the selection is recorded and the body is drawn, before presentation. A scene-level `~` line runs when the runner reaches it. `unlock topic` or `lock topic` with no `scope: topic` storylet warns `W_TOPIC_NO_STORYLET`. With tracing on, the lines are `wyrd topic_unlock topic=%s ok=%s reason=%s`, `wyrd topic_lock topic=%s ok=%s reason=%s`, `wyrd topic_ask npc=%s topic=%s storylet=%s ok=%s reason=%s`, `wyrd topic_open npc=%s topics=%d`, and `wyrd effect_run source=%s id=%s kind=%s`. Gullhaven adds `harbor_gossip.storm` and `dock_rumour`. Save schema stays 3.

- `~ assign role <role> to <entity>`, `~ vacate role <role>`, and `~ adjust baseline <axis>(a, b) by <n>` compile and run. A role that no `role` block declares warns `W_ROLE_UNKNOWN`. Assign refuses `abolished`, `contested`, `no_entity`, `ineligible`, and `same_holder`. Vacate refuses `abolished`, `contested`, and `empty`. Baseline refuses `no_entity`, `self_edge`, and `zero`. With tracing on, the lines are `wyrd role_assign role=%s from=%s to=%s ok=%s reason=%s`, `wyrd role_vacate role=%s from=%s to=%s ok=%s reason=%s`, and `wyrd baseline_adjust a=%s b=%s axis=%s from=%s to=%s ok=%s reason=%s`. A frozen `locked_at` holder replaced by `assign`, from the host or from content, stays bound and usable. Only a vacate, or that person no longer being alive, makes the slot `locked_gone`. Gullhaven adds `dock_runner` and uses the three effects on the dock errand. Save schema stays 3.

- `~ start quest <id>` and `~ advance <quest> to <stage>` compile and run. An unknown quest is `E_QUEST_UNKNOWN`. A stage that is not a top-level stage of that quest, including a nested sub-state, is `E_STAGE_UNKNOWN`. With tracing on, a start logs `wyrd quest_start quest=%s ok=%s reason=%s`, an advance logs `wyrd quest_advance quest=%s from=%s to=%s ok=%s reason=%s`, and every status change logs `wyrd quest_status quest=%s from=%s to=%s`. Gullhaven adds `dock_errand`, started from a choice in `toll.offer_room` and moved to its second stage by `advance`. Save schema stays 3.

## 0.6.2-m8 - 2026-10-18

Bench measurement fix. `VERSION` is `0.6.2-m8`. `plugin.cfg` version is `0.6.2-m8`. Save schema stays 3. Seeded checksums stay the same. No runtime code changed. Corey cuts the tag `v0.6.2-m8` after this merges.

- `reputation.cached` still primes `reputation(player, harbor_council)` once, untimed. It then times `REPUTATION_CACHE_BATCH` hits (32) and divides, the same way `believes.own` divides `BELIEVE_CALLS`. The old sample timed one hit immediately after that fill. That hit was cold: the fill checks the social-cache stamp once, so `_ensure` is not warm. Later hits in the same burst match the steady call. The checksum stays `50.000000`. `reputation.cold` still times the miss. The tag job runs each checkout's own harness, so `v0.6.2-m8` compares this average with `v0.6.1-m8`'s single call. That delta is the measurement change. The following tag compares two averages.

## 0.6.1-m8 - 2026-10-18

Perf fixes for the v0.6.0-m8 regression gate. `VERSION` is `0.6.1-m8`. `plugin.cfg` version is `0.6.1-m8`. Save schema stays 3. Seeded checksums stay the same. Corey cuts the tag `v0.6.1-m8` after this merges.

- An empty reach list returns the belief hot cache before the agent and key are built. The hot path reads `WyrdRumor.reach_any`, kept in step by `on_reach`, so it does not call into the rumor table. A reach row still calls `materialize` before that cache, so a later rise can write. `has_reach` reads `reach_any` and is true for a level 0 row.
- Hour buckets stay a PackedInt32Array in append order. An Array bucket, packed lazily on read, left `load.time` next to the v0.6.0-m8 tag and made `tick.recheck` about three times that tag in the same three-way job, so the buckets stay packed. The witness index is still built at import.
- `reputation` checks the social cache stamp once per call, then fills the same axis and disposition keys a direct read would store, in the same order.
- Dirty waits are sorted once per `tick` call and popped in ascending order. A mark during that call joins the next call. The number of rechecks is unchanged.

### Accepted regressions vs v0.5.0-m7

Corey accepted these two remaining costs against v0.5.0-m7. The numbers are the same-machine full-profile medians. Budgets stay as they are.

- `reputation.cold` is 19.222 ms on this branch and 10.875 ms on v0.5.0-m7, +76.8%. That is the cost of filling the M8 social cache in one pass. It keeps `save.bytes` stable and makes `reputation.cached` about 65% faster than v0.5.0-m7.
- `load.time` is 985 ms on this branch and 754 ms on v0.5.0-m7, +30.7%. That is the cost of building the M8 witness, believer, and time indexes at import. They make deed lookups about 24× faster and the full snapshot about 65% faster.

## 0.6.0-m8 - 2026-10-17

M8 rumors, documents, and save schema 3. `VERSION` is `0.6.0-m8`. `plugin.cfg` version is `0.6.0-m8`. Corey cuts the tag `v0.6.0-m8` after the milestone benchmark. Save schema is 3. A schema 2 save loads with empty token queues and a zero slice, and the dirty waits stay armed. A schema 3 save omits `flight` when that set is empty too, and that load clears it. A rumor whose policy id is not registered at load reports `error[E_SAVE_POLICY]` and `push_error`, naming the policy and the deed, and that deed's in-flight state is dropped. Other rumors load. Beliefs already written stay. Schema 4 is refused.

- A frozen issue is built across publish units. `WyrdConfig.publish_slice_rows` (default 128, not saved) is the candidate rows one unit reads. The claim, the candidate rows, and the member believer minutes are frozen on the first slice, so the finished line matches a one-shot from that moment. A handler that returns false keeps the token. `flight.publish.cursor` is the open issue token and is omitted when no issue is open. The gathered rows are not saved. An open issue also stores `flight.publish.beliefs` (rows of `deed`, `t`, and `who`, the member snapshot from the first slice) and `flight.publish.claim` (`source` and `value`). Load keeps that snapshot and continues the issue. With tracing on, the next slice logs `wyrd publish cursor document=%s issue=%s phase=%s rows=%d budget=%d` with phase `resume`. A save that has `cursor` and no `beliefs` starts the issue over and logs phase `restart`. Other phases are `start`, `continue`, and `done`. Schema stays 3. Skip lines are unchanged. `deeds_known_to` reads the verb index, the witness index, hour buckets, and the believer field. Lookup off still walks every row, and the two walks match. A full snapshot reads deed columns and a pair index instead of building a row dictionary per deed. The pair index is built on the first read, not while rows are imported. Filtered pages are unchanged. Token queues keep a read cursor. A pass that would only run rumor hops does those hops in one loop, and unused share still spills onto rumor. Rumor rolls use `WyrdRng.decision_unit`, the same first draw as `for_decision`. A chance of 0 or 1 does not draw. A full-scale busy tick is about 4.2 ms, still over the 2 ms frame warning, because about 64 rumor hops still run when waits are empty. One hop is about 66 µs. The warn-only ceilings for `rumor.tick` and `scheduler.tick` are 8 ms, about 2× the new medians. They stay warn-only until Corey confirms them. They are not 2 ms.
- Gullhaven adds `harbor_gazette`, a daily document that writes `harbor.gazette`, and the playtest registers rumor policy `harbor_whisper` (kind `apprentice`, two hops, verb `whispered`).
- `wyrd check` warns `W_RECAP_UNMARKED` when a concrete stored fact is `set` or `inc` in a stage that sets an outcome, or by a choice effect, and the declaration has no `recap:` key. `recap: true` keeps provenance through deed compaction. `recap: false` silences the warning and drops that provenance on compact. The warning exits 0. `wyrd check --strict` exits 1. Gullhaven marks the outcome and choice writes that the lint names.
- A `document` block publishes a frozen issue on the `publish` queue. `deeds_known_to(group, since, filter)` lists deeds a current group member witnessed or believes through a rumor. `saw` counts as `known:`. `heard`, `inferred`, and a rumor believer count as `believed:`. The believer index stores the adoption minute, and `since` uses that minute for the listener. It is rebuilt from the optional `believers` field on each deed row in the deeds bag. A plain `believed/` write is not indexed. Compaction moves those listeners onto the newest merged id and drops them with a dropped row. The issue claim prefers a matching fragment slant, then the lowest member's `believed:` value, then `known:`, then the world fact. A mutated belief is that `believed:` value. The deed row stays. After a jump, one visit enqueues at most `publish_catchup_max` missed issues per document, oldest first. The default is 3. Issues past the cap are numbered and stored as `skip <id>#<n> due=<minute>` lines in the document fact, so they are never published later. A save and a load publish the same later issues as a run that did not save. The issue counter, the covered minute, queued dues, and publish tokens are saved in `flight`. A schema 2 save still loads with an empty queue. Load does not log `wyrd publish`. With tracing on, one `wyrd publish` line is logged per frozen issue. A skip line is not logged.
- A registered `WyrdRumorPolicy` may list `mutations`. Each accepted hop, and each accepted aggregate materialize, rolls `keep_chance_fn` with the rumor hash and either keeps the claim, replaces it, or drops it. The listener stores that copy in `believed/<listener>`. The next hop offers the copy. The deed row, `known:`, and `world:` stay unchanged. There is no `.wyrd` syntax for a policy. The copies are saved in `flight`. Mutation callables are rebound from the registered policy. A schema 2 save still loads with an empty queue. With tracing on, each mutation logs `wyrd rumor mutate`. Load does not log it.
- A deed in a coarse place stores a reach level for that deed and place. `WyrdConfig.rumor_coarse_minutes` (default 60) raises it by one rumor unit per crossed game hour. `belief` and `believes` roll that level once for the asked NPC and, on accept, write `believed/<listener>`. A reject is also once. Precise hops are unchanged. Reach rows, pending counts, the once-set, and reach tokens are saved in `flight`. A schema 2 save still loads with an empty queue. With tracing on, a rise logs `wyrd rumor reach` and a draw logs `wyrd rumor materialize`. Load does not log them.
- A deed with a reveal claim can spread along the relationship kinds in a registered `WyrdRumorPolicy`. One rumor unit offers that deed to one listener. The offer is a seeded roll per deed, speaker, listener, and hop. Adoption uses the credibility threshold and writes `believed/<listener>` only. A `saw` witness still learns through the reveal path. `known:` and `world:` stay unchanged. A coarse deed place does not start a precise hop, and a listener in a coarse place does not adopt one. The claim table, seen and queued sets, and rumor tokens are saved in `flight`. A schema 2 save still loads with an empty queue. With tracing on, a hop logs `wyrd rumor hop` and an offer logs `wyrd rumor adopt`. Load does not log them.
- Axes, disposition, reputation, and `path_exists` share one cache for the current time bucket. A read stores a missing entry. `set_cache(false)` recomputes and does not store, and those results match. A relationship, deed, membership, formula, config, or time-bucket change drops the entries. Each dropped entry is one `cache_refresh` unit. `path_exists(a, b, kinds, max_hops)` is a directed search; a step may use any listed kind. Cache entries are not saved. `cache_refresh` tokens are saved in `flight`. With tracing on, one `wyrd social cache` line is logged for an invalidation, a miss, or a hit. Load does not log one. A full-scale affinity and disposition matrix for 500 NPCs is 21,207,500 bytes by the key-text model.
- `Wyrd.tick` accepts any non-negative slice and runs whole game ticks of `scheduler_tick_minutes` (default 1). A zero slice still runs one tick and does not move the clock. One scheduler spends `scheduler_work_per_tick` units across waits, rumor, publish, and cache refresh. Shares are 40, 12, 8, and 4. Unused share moves to the earliest queue that still has work. Unfinished items stay in order. A debug build can log `wyrd scheduler queue=frame` when a tick's units exceed `scheduler_frame_warn_usec` (default 2000 microseconds, 2 ms; 0 disables it). The line does not change the work. The queues, the dirty waits, and the leftover slice are saved in `flight` when any of that remains. A schema 2 save still loads with empty token queues and a zero slice, and the dirty waits stay armed. Load does not log `wyrd scheduler`.
- Deed rows are indexed by witness and by hour bucket. A witness is the knower of that deed, and `saw`, `heard`, and `inferred` share one list. Snapshot deed, social, and precedence reads use the indexes. A prefix visits only names that can start the row key. Precedence reads the name lists and does not walk every deed. The rows match a full scan. The indexes are not saved.
- Storylet queries read a link-time index of sorted ids per scope kind, scope id, and speaker, plus a bucket for speaker `any`. The winners match a full scan. A bark query still runs inside the call. The index is not saved.
- The proposed `memory.peak` warning budget is 384 MiB, sized for an 8 GB laptop. It still warns only. `memory.resident` uses the same ceiling for the high-water after the rumor samples. It warns only.
- The scale bench keeps `bench/scale_pack.sha256` and adds `<pack>_rumors/`: a friend graph over the scale NPCs, `harbor_whisper` (a mutation of `harbor.toll_fate`) and `harbor_reach` (coarse `gullhaven`), and one `harbor_gazette`. New timings are `rumor.tick`, `scheduler.tick`, `publish.issue`, `deeds_known_to`, `memory.quests`, `memory.believers`, `memory.per_belief`, `save.believers`, `save.flight`, `save.flight_bytes`, `load.flight`, `deeds.index`, and `deeds.scan`. `compile.strict` and `compile.tie_lint` are judged by the 20% regression gate only. Other absolute budgets warn until they are confirmed.
- The scale bench times director query, why-not, storylet tie-lint, a full debug snapshot, a filtered snapshot page, a single-section facts page, and the same query with coverage counting on. Budgets warn.
- `Wyrd.debug.snapshot` builds only the requested sections. The prefix filter runs while those rows are collected, and the kept rows are sorted and paged as before. Social rows and precedence agents read deed witness names without building a full deed row.

## 0.5.0-m7 - 2026-10-16

M7 inspector data, choices, coverage, and the console. `VERSION` is `0.5.0-m7`. `plugin.cfg` version is `0.5.0-m7`. Corey cuts the tag `v0.5.0-m7` after the milestone benchmark. Save schema is 2.

- `wyrd console <pack>` runs the playtest commands: set a fact, kill or vacate or replace a role holder, advance time, fire an event, and run a scene in a text UI. Every command records source `console` and, when tracing is on, one `wyrd console` line. A direct `set` stores provenance scene `console`. Release exports exclude `addons/wyrd/runtime/console/*`. `--out` writes the JSON save after those commands when every command succeeded. An open scene refuses that write.
- `Wyrd.coverage` counts storylet draws, slot-variant entries, and shown line ids. Recording is off until `enabled` is set, including in a release build. Counts stay out of saves. `merge` adds them to `user://wyrd_coverage.json`. `wyrd coverage` lists never-hit ids by file:line. One `coverage` line is logged per hit when tracing is on, and one `coverage_report` line per report.
- `Wyrd.facts.choice_summary` lists stored-fact writes from the provenance map. It filters by scene, choice, key prefix, and an inclusive time range. `wyrd choices` prints that table. A concrete stored fact may say `recap: true`. Deed compaction drops other provenance and keeps those rows. One `choice_summary` line is logged for a read when tracing is on, and one `choice_compact` line when compaction drops rows.
- `Wyrd.debug.snapshot(sections)` reads live facts, role bindings and history, quest stages with waiting reasons, the dirty condition set, deeds with decayed weights, social axes and disposition, belief and group precedence, and fact provenance. The document is built on demand and is not saved. A prefix and a page window filter each section. One `wyrd debug snapshot` line is logged when tracing is on. Load does not log it.
- Gullhaven marks `ferry.toll_coins` with `recap: true`. A headless test kills each Gullhaven role holder with `wyrd console --cmd` and checks the example quest. The ferry lock re-routes through `ferry.locked_gone`.

## 0.4.0-m6 - 2026-10-16

M6 director and reactivity. `VERSION` is `0.4.0-m6`. Corey cuts the tag `v0.4.0-m6`. Save schema is 2.

- Storylet queries, bark clocks, quest regions, sequences, voiced lines, and secrecy tiers.
- `wyrd why-not` takes `--tiers` and `--secrecy-fact`. `wyrd storylets` lists storylets. `wyrd cooldowns` lists clocks.
- `WyrdConfig.trace_director` logs one `director_candidate` line per scope-and-speaker match when tracing is on. Load does not log it.

## 0.3.0-m5 - 2026-10-16

M5 deeds and social. `VERSION` is `0.3.0-m5`. Corey cuts the tag. Save schema is 2.

- Gullhaven's toll tale: the harbor council declares the toll lost at sea, a fisher believes it was stolen, and `dock_hand` inherits that council line. The council member is unwilling while that belief is the official line, and barred while the player believes it was stolen. One witness hears the tale through a wall. One statement fails credibility. The role × belief matrix writes and retracts each of those conditions.
- `W_STALE_BELIEF` warns when a scene `learn` writes `known/<agent>` and that agent still has a contradicting `believed/` value that no `unbelieve` clears.
- Player-visible text may interpolate `belief`, `believes`, and `held`. That interpolation warns `W_CLAIM`. Interpolating a stored fact's world value while a gate reads that fact from the world, and the gate does not also `knows` it, is `E_FACT_LEAK`.
- Save schema is 2. A schema 1 save gains empty `facts.believed` and `facts.held` bags. New saves write those bags sparse, one map per agent or group.
- `~ believe <agent> <fact> = <expr>`, `~ unbelieve <agent> <fact>`, `~ declare <group> <fact> = <expr>`, and `~ retract <group> <fact>` write schema stored facts. A resolved fact is `E_WRITE_RESOLVED`. A type mismatch is `E_WRITE_TYPE`. A belief write does not change `world` or `known`. One `belief` trace line is logged when a value changes.
- `knows(agent, key)` reads a role reveal or `known/<agent>`. `known` is the same read and warns `W_KNOWN_DEPRECATED`. `believes(agent, key)` is truthy of the agent's belief, then each group's `held` value in `groups_of` order. An explicit false stops the walk. `belief(agent, key)` and `believes(...) == v` read the value. `held(group, key)` reads that group only. None of them fall back to `known` or `world`. `register_group_precedence` replaces the membership order. `invalidate_groups`, or emitting `groups_changed`, drops the cache and wakes conditions that read `group.membership`. A lookup logs one `belief_lookup` line. `unwilling`, `barred`, eligibility, and `cast` may call these, and a belief write re-checks slot state on the next tick.
- `conflicted(agent, key)` is the WFR9 group-position check. The M4 slot state stays `contested`. It is true when two of the agent's groups hold different present values. Absence is not a position. Explicit false is. The agent's own belief, `known:`, and `world:` are not positions. `believes` still follows precedence. One `conflict` trace line is logged per resolution.
- `~ learn <agent> <fact> = <expr>` and `~ forget <agent> <fact>` write `known/<agent>`. A resolved fact is `E_WRITE_RESOLVED`. A type mismatch is `E_WRITE_TYPE`. Learning does not change `world` or a belief, and it does not clear one. One `knowledge` line is logged when the value changes. A role reveal logs the same line.
- A deed witness stores a perception mode, `saw`, `heard`, or `inferred`, from `WyrdSpatialAdapter.perceive`. The default is `saw`. `reveals` and `claim` write that stored fact for each witness: `saw` learns it, and `heard` or `inferred` believes it. Other agents are not copied. `perceived(agent, verb)` returns the latest mode. One `perception` line is logged per witness.
- `statement: true` on `record deed` is a statement deed. Perception modes are still stored, and the mode does not write the fact. Each witness is a listener. The default score is `disposition(listener, speaker) / 100`, and the listener accepts when that score is at least `credibility_threshold` (default 0.5). `register_credibility` replaces the score and is not saved. Acceptance writes `believed/<listener>` only. One `credibility` line is logged per listener, including a rejection.
- A kind the observer holds toward the subject multiplies that axis's deed delta by `WyrdConfig.kind_scale`. Several kinds multiply. The baseline is not scaled. `reputation(subject, group)` is the mean disposition of the group's members toward the subject. The subject is excluded. The value is derived, not saved. One `reputation` line is logged per call.
- `deeds.compact` merges rows that share a minute and the same witnesses, and drops weight that has rounded to zero without moving `perceived`. Scores stay within that rounding. `deed_count` may fall. `compact_after` of 0 does not compact on tick. One `compact` line is logged per call.

## 0.2.0-m4 - 2026-10-15

M4 roles and casting. `VERSION` is `0.2.0-m4`. Corey cuts the tag. Save schema stays 1.

- `wyrd roles` prints a sorted table of every role: holder, status, strategy, pending or abolished, and frozen slots. `--prefix` keeps ids that start with that text. `--save` loads a JSON save first. The same table is `WyrdRoles.render_table`.
- Gullhaven adds the harbor guild: a guild-assigned factor, an elected reeve, a barred visitor, an unwilling factor, abolish when the guild has no successor, and a `locked_gone` variant on the ferry lock. The lookout cast slot stays.
- The Gullhaven acceptance matrix kills, replaces, or vacates every role holder at every stage, checks the fallback, and save/loads back to the same state.
- `cast(<condition>)` picks once at quest start from `WyrdWorldAdapter.candidates`, keeps the entities the condition accepts, and freezes a seeded pick. No candidate leaves the slot `empty`. The freeze is saved on the existing roles blob. One filterable `cast` line is logged. A constant cast condition uses the existing always/never slot warning.
- Slot states `unwilling($h)`, `barred`, `locked_gone`, and `contested` resolve live. Precedence is `locked_gone`, `contested`, `empty`, then `barred`, `hostile`, `unwilling`, `successor`, and `default`, and the first covered variant wins. `outcome = route_closed` keeps the quest open and is readable with `outcome(quest, branch)`. Coverage warns for a used slot with no `empty` variant, a `locked_at` slot with no `locked_gone` variant, a constant `unwilling` or `barred` condition, and a branch whose every reachable route closes. A quest resolution logs one filterable `slot_state` line.
- A `role <id>` block compiles `scope`, `eligibility`, `default_holder`, `visibility`, `succession`, and `vacancy`. `roles.define()` stores the same definition. `eligible(role, entity)` tests `candidate`. `relation` succession also requires eligibility. `faction_assigns` picks a living eligible member by `faction_rank` and a seeded tie-break. `host_decides` and `election` stay `contested` until `assign`. `election` emits `election_needed` and calls `WyrdElectionAdapter.start_election`. `vacancy: abolish` runs when a strategy finds nobody.
- Slot state `contested` sits after `locked_gone` and before `empty`. A missing `contested` variant uses the `empty` variant and the state stays `contested`. A `contested` variant does not cover the empty lint.
- `line_ready` carries the speaker entity and the role ids they hold in that scene. A successor records `role_changed` and is never the departed holder. Each succession step logs one filterable `succession` line.

## 0.1.0-s3 - 2026-10-15

WFR13 host world events. A pack declares an `events` block. `Wyrd.events.emit` type-checks the payload, drops `on_event` caches (a pattern key drops every concrete cache), and re-checks dirty conditions before it returns. `begin_batch` / `end_batch` coalesce that re-check. A missing invalidate mode on a resolved fact is `E_RESOLVER_NO_INVALIDATE`. A wait that reads a resolved fact with an empty or `per_query` mode is `E_WAIT_RESOLVER_MODE`. The event log is not part of `save_state`. See `docs/events-draft.md`.

S2 slice runtime. S2 exit met. Draft. Saves, replay, `await_host`, and the Gullhaven playtest scene are in this slice. See `docs/playtest.md`.

- `save_state` / `load_state` round-trip facts, deeds, roles, quests, journal text, and every named RNG stream. Schema version 1. Hex for 64-bit values. No save while a scene is open.
- `WyrdTrace` records and replays inputs. A changed host answer is visible in the diff.
- `await_host` is parsed and pauses the remaining entry steps until `complete_host_step`.

S2c quest runner, scene runner, and the six slice effects. Draft.

- The six slice effects run at play time, including `do` failure divert and outcome signals.
- Quest stages, waits, variants, outcomes, and a frozen journal. Default date `day N, HH:MM`.
- Scene playback keeps text on screen with or without `line_audio`. `can_save()` is false while a scene is open.
- Host-modal step is `request_host_step` / `complete_host_step`. The statement form is approved in S2d.

S2b deeds, disposition, and roles. Draft. Quests, scenes, and saves are later slices.

- Deed log stores packed rows, decays by the hour bucket, and keeps memorable rows. No compaction.
- `deed_count` and `deed_score` replace the zero stub. Sums round to 6 decimal places.
- Relationship baselines plus a verb-to-axis table. Default disposition is `disposition_default + affinity / 2`. Hostile is that disposition toward `player` below `hostile_threshold` (default 20).
- `live` follows the role. `locked_at` freezes when the stage is entered. `cast` binds once at quest start and logs that casting is M4.
- Succession is `relation(kind|kind)` or `none`. Secret holders are written to `known/<agent>` only through `tell`.
- Linker warning `W_EMPTY_UNCOVERED` when a slot has no empty variant and no `on_empty`.
- Linker warning `W_HOLDER_UNGUARDED` when prose interpolates `holder(slot)` and that slot can be empty without `filled(slot)` or an empty variant on that branch.

S2a runtime core and fact store. Draft. Deeds, quests, scenes, and saves are later slices.

- `load_content` compiles a manifest's `.wyrd` sources into a runtime `WyrdContent` and refuses the load on any error.
- Fact store: stored types, `world` and `known/<agent>`, resolver cache (`on_event`, `poll`, `per_query`), `fact_changed` for subscribed prefixes.
- `tick` advances game minutes, refreshes due polls, and re-checks dirty conditions up to `scheduler_work_per_tick`.
- A concrete key under a `{id}` pattern still loads that key. `reads` stays the pattern.

PCG32 swap: `WyrdRng` is now an in-script PCG32 (XSH-RR 64/32) with streams, per-decision seeding and saveable state; sequences no longer depend on the Godot version. Seeded bench fixtures were regenerated.

- New `tag-lines` ids follow this sequence. An id already written on a line is not rewritten.

S1d slice compiler, part 4 of 4: linking and the pack CLI. Draft, not frozen (`docs/statements-draft.md`). S1 exit met.

- `check` links a pack: merged facts, quests, scenes, speakers, commands, line ids, and the fact cross-reference.
- `WyrdContentManifest` plus optional `wyrd_commands.json`. A directory with no manifest is one pack named after the folder.
- `tag-lines`, `export-json`, and `facts`. `export-json` is a debug document, not the runtime load format. `test` stays unimplemented.
- Gullhaven is a four-file slice. `check --manifest` on `harbor.wyrdmanifest.tres` is clean.

S1b-perf: dependency index, dirty-set benchmark, and the condition-evaluator speed pass. Draft, not a CI gate (`docs/spikes/s0-condition-speed.md`).

- `WyrdDepIndex` maps exact keys and `{id}` patterns to condition indexes. A pattern depends on the whole key. The index is rebuilt from `reads` and is never saved.
- The seeded 10k-fact / 5k-condition bench times dirty-set ticks at 1, 10, and 100 changed facts. Incremental results must match a full scan. Timings stay informational.
- `WyrdRpnEval` lives in `runtime/conditions`. `tests/support/wyrd_rpn_eval.gd` is a thin shim. Saved opcodes are unchanged.
- The measured speed pass kept fact-slot loads, frequency-ordered dispatch, and load-time superinstructions. A fixed stack, hoisting consts, and an inlined jump pop were slower or not reliable, and were dropped. Numbers are in the spike doc.

S1c slice compiler, part 3 of 4: statements and effects. Draft, not frozen (`docs/statements-draft.md`).

- Quest, stage, slot, variant, scene, line, choice, and effect records, compiled from the block tree.
- Slice effects: `set`, `inc`, `record deed`, `unlock topic`, `do`, and `outcome`. Stored facts only.
- `#line:` required on spoken lines, journal entries, and choice labels.
- `check` runs the single-file pipeline through statements. Linking, `tag-lines`, and `export-json` stay in PR 5. The S1b-perf pass is a separate change.

S1b slice compiler, part 2 of 4: condition language. Draft, not frozen (`docs/conditions-draft.md`).

- Expression lexer, parser, type checker, and flat instruction emit, including prose interpolation spans.
- `WyrdFactSchema.lookup` and a signature registry (belief names registered and marked M5).
- Specificity, fact reads (including short-circuit arms), and a test-only stack walker.
- 10k-fact / 5k-condition benchmark recorded beside the placeholder runner. Not a CI gate.
- S1b left quest and scene statements uncompiled. Linking, `tag-lines`, and `export-json` stayed for later.

S1a slice compiler, part 1 of 4: lexer, block parser, diagnostics, and parse-level `check`.

- Lexical and block rules from grammar v1 sections 1–6, with golden cases for each rule.
- `facts` entries are parsed into a `WyrdFactSchema` (stored, resolved, invalidation, and a trailing `doc` string).
- CLI `check` prints `path:line:col: error[CODE]: message` and exits 1 when a file has errors.
- Gullhaven example `example/content/gullhaven/ferry_toll.wyrd`.
- Conditions, quest and scene statement semantics, linking, `tag-lines`, and `export-json` stay later.
- Grammar v1 §4 example corrected so source `{{two coins}` displays as `{two coins}`. Quoted titles are never interpolated, and a trailing `//` comment may follow `language 1`. Example corrected and clarifications approved by Corey, 2026-10-14.

## 0.0.1 - 2026-10-14

S0 skeleton. No runtime features yet.

- Godot project layout, editor-plugin stub, and versioned runtime facade.
- Typed adapter stubs, a seeded RNG wrapper, and a stable hash.
- Fake host, GUT 9.7.1, a placeholder benchmark runner, and CI.
- Grammar v1: lexical and block rules approved (Corey, 2026-10-14) and frozen. Quest, scene, and facts examples stay illustrations.
