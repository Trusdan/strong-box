# rng

`WyrdRng` is an in-script PCG32 (XSH-RR 64/32). For a given seed and stream, the full sequence, `stream_id`, `for_decision`, and `to_state` stay the same across Godot versions. Wyrd never uses Godot's built-in generator.

`WyrdHash` is FNV-1a 64, including `combine`. Godot's `hash()` is not used.

`WyrdRuntime.rng_stream(name)` keeps one stream per name, seeded with `seed_with(game_seed, stream_id(name))`. `draw_u32` draws from it. `save_state` stores each stream's `to_state()`, with the state word as hex. Chance rolls stay on `for_decision` and are not a saved stream. `format_u64` / `parse_u64` are the hex helpers saves use.
