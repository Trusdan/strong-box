# effects

`WyrdEffects` runs the slice effects: `set`, `inc`, `record deed`, `unlock topic`, `do`, `outcome`, `believe`, `unbelieve`, `declare`, `retract`, `learn`, and `forget`.

`set` and `inc` write stored facts. Provenance keeps `scene`, `choice`, and `time` (game minutes). A console `set` uses scene `console` and choice `set`. `deeds.compact` drops that provenance unless the fact is marked `recap: true`. `inc` of a missing fact starts at 0. A type mismatch is `push_error` and the fact stays.

`believe` and `declare` write a stored fact into `believed/<agent>` or `held/<group>`. `unbelieve` and `retract` remove one key. Those writes do not change `world` or `known`, and they do not update provenance. A change logs one `belief` line when tracing is on. The same value again, or clearing a missing key, does not.

`learn` writes `known/<agent>`. `forget` removes one key. Neither changes `world`, `believed`, or `held`, and learning does not clear a belief. A change logs one `knowledge` line. A deed with `reveals` and `claim` writes that fact for each witness: `saw` learns it, and `heard` or `inferred` believes it. Other agents are left alone. A registered rumor policy may also offer that claim along relationship kinds. That offer writes `believed/<listener>` only. See `runtime/rumor/README.md`.

`record deed` calls the deed log. Set literals in arguments are read from the argument's source text, because the expression emitter does not push a set value.

`unlock topic` stores the id and emits `topic_unlocked` once. A repeat unlock does not emit again. `lock topic` removes a stored id. `outcome` emits `outcome_changed`. A failed `do` returns the `on_fail` target and later effects in that list do not run. A missing action adapter fails the command.
