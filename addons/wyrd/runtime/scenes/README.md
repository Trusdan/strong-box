# scenes

`WyrdSceneRunner` is the facade's `dialogue` object. One conversation is a stack of scene frames.

`line_ready` carries a `WyrdLineView`: `id`, `speaker`, `display_name`, `text`, `tags`, `audio`. Text is interpolated, then passed through `TranslationServer.translate` with the line id. A holder variant uses the variant's id for that translation and for `line_audio`. `register_line_audio(line_id, locale)` supplies `audio`, which may be null. The line stays until `advance()`.

`choices_ready` carries `WyrdChoiceView` rows. A false condition hides the choice. `show_disabled_when` shows it disabled with the quoted reason. `disabled_when` is the deprecated spelling. `choose(index)` uses the index in that list. A disabled choose logs an error and stays. A choice may carry `check` and `check_args`. `choose` asks `WyrdSkillAdapter` before the choice effects, then restores `quest_id`, `scene_id`, and `choice_id`. A failed check, or no adapter, diverts to the check's `on_fail` and runs none of those effects. A later host role change for a bound slot aborts the scene `holder_left`. A role effect inside the choice still does not abort that scene.

`-> scene` pushes a sub-scene and returns. `-> end` finishes the frame. `abort(reason)` runs `on_abort` from the inner frame outward and emits `scene_ended` for the root scene. A bound holder who dies or leaves the role aborts the same way.

`can_save()` is false while any frame is open.
