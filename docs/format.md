# Strongbox save format

This is the specification of the files Strongbox writes. Save files come from players' disks, so Strongbox treats them as **untrusted input**. Reading one never creates objects, loads resources or runs code.

Two classes do the work:

- `StrongboxCodec` (`addons/strongbox/core/codec.gd`) turns plain Godot values into JSON-safe data, and back.
- `StrongboxEnvelope` (`addons/strongbox/core/envelope.gd`) wraps that data with a header and a checksum, as JSON text.

Both report problems through `StrongboxResult` (`ok`, `value`, `code`, `message`) instead of pushing engine errors.

## File layout

A save file is one JSON object, written with sorted keys and UTF-8 text:

```json
{"body":{"chest_position":{"$t":"Vector3","v":[1.5,0.0,-2.25]},"coins":3,"current_room":"Cellar"},
 "header":{"checksum":"sha256:df73306989237d71dcac2d0de40d6e42e0c0c05812e626f03f95978d0f86a7fa",
  "format":"strongbox","format_version":1,"game_version":"0.1.0","meta":{"location":"Cellar"},
  "playtime_s":{"$t":"float","v":754.25},"saved_unix":1767225600,"schema_version":1}}
```

(Line breaks added here for reading. Strongbox writes it on one line. Any whitespace or key order is accepted when reading.)

- `body` is the game's state, encoded by the codec. It must be a Dictionary.
- `header` is described below. It is also encoded by the codec, which is why `playtime_s` is a tagged float.

## Header

| Field | Type | Owner | Meaning |
| --- | --- | --- | --- |
| `format` | String | addon | Always `"strongbox"`. |
| `format_version` | int | addon | Version of this file format. Starts at **1**. Strongbox refuses files with a newer version. |
| `schema_version` | int | game | Version of the game's body layout. The game bumps it when its save data changes shape. |
| `game_version` | String | game | Free-form game version, for example `"0.1.0"`. |
| `saved_unix` | int | addon | When the file was written, in Unix seconds. |
| `playtime_s` | float | game | Total play time in seconds. |
| `meta` | Dictionary | game | Labels for a load menu, such as a location name. Encoded by the codec, so any allowed type works. |
| `checksum` | String | addon | `"sha256:"` plus 64 lowercase hex digits; see below. |

Unknown extra header fields are ignored.

### Checksum and canonical form

The checksum is the SHA-256 of the body's **canonical JSON**: the encoded body written with sorted keys and full float precision, with every whole number up to 2^53 written as an integer.

The whole-number rule exists because parsing JSON in Godot turns every number into a float, so `3` comes back as `3.0`. Normalizing on both sides gives the same text before and after a round trip. The result:

- Reformatting a file (whitespace, key order) does not break it.
- Changing any value does break it: `"coins":3` → `"coins":4` fails with `E_CHECKSUM`.

`unpack` checks the layout, then the header, then the format version, then the checksum, and only then decodes the body.

## Body encoding

### Plain values

`null`, `bool`, `String`, Arrays and Dictionaries whose keys are all Strings are written as the matching JSON values. An `int` up to 2^53 in magnitude is a plain JSON number. Typed arrays (`Array[int]`) are written as plain arrays and come back untyped.

```json
{"coins":3,"items":[1,"two"],"name":"Hub","open":true}
```

### Tagged values

Every other allowed type is written as a tagged object with exactly two keys:

```json
{"$t": "<type>", "v": <payload>}
```

The tag is Godot's own type name, the same as `type_string(typeof(value))`; `StrongboxCodec.tag_for_type()` returns it. **Floats are always tagged**, so `1.0` stays a float and never becomes an int.

| Tag | Example value | Written as |
| --- | --- | --- |
| `int` | `9007199254740993` (beyond 2^53) | `{"$t":"int","v":"20000000000001"}` |
| `float` | `1.5` | `{"$t":"float","v":1.5}` |
| `float` | `123456789.123456789` | `{"$t":"float","v":"419d6f34547e6b75"}` |
| `float` | `-0.0` | `{"$t":"float","v":"8000000000000000"}` |
| `float` | `NAN` | `{"$t":"float","v":"7ff8000000000000"}` |
| `StringName` | `&"coin"` | `{"$t":"StringName","v":"coin"}` |
| `NodePath` | `^"Cellar/Chest"` | `{"$t":"NodePath","v":"Cellar/Chest"}` |
| `Vector2` | `Vector2(1.5, -2)` | `{"$t":"Vector2","v":[1.5,-2.0]}` |
| `Vector2i` | `Vector2i(3, -4)` | `{"$t":"Vector2i","v":[3,-4]}` |
| `Vector3` | `Vector3(0.5, 1, -2.25)` | `{"$t":"Vector3","v":[0.5,1.0,-2.25]}` |
| `Vector3i` | `Vector3i(1, 2, 3)` | `{"$t":"Vector3i","v":[1,2,3]}` |
| `Vector4` | `Vector4(1, 2, 3, 4)` | `{"$t":"Vector4","v":[1.0,2.0,3.0,4.0]}` |
| `Color` | `Color(1, 0.5, 0, 1)` | `{"$t":"Color","v":[1.0,0.5,0.0,1.0]}` |
| `Quaternion` | `Quaternion(0, 0, 0, 1)` | `{"$t":"Quaternion","v":[0.0,0.0,0.0,1.0]}` |
| `Rect2` | `Rect2(0, 0, 16, 8)` | `{"$t":"Rect2","v":[0.0,0.0,16.0,8.0]}` |
| `Rect2i` | `Rect2i(0, 0, 16, 8)` | `{"$t":"Rect2i","v":[0,0,16,8]}` |
| `AABB` | `AABB(Vector3(0, 0, 0), Vector3(1, 2, 3))` | `{"$t":"AABB","v":[0.0,0.0,0.0,1.0,2.0,3.0]}` |
| `Basis` | `Basis.IDENTITY` | `{"$t":"Basis","v":[1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,1.0]}` |
| `Transform2D` | `Transform2D(Vector2(1, 0), Vector2(0, 1), Vector2(4, 5))` | `{"$t":"Transform2D","v":[1.0,0.0,0.0,1.0,4.0,5.0]}` |
| `Transform3D` | `Transform3D(Basis.IDENTITY, Vector3(4, 5, 6))` | `{"$t":"Transform3D","v":[1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,1.0,4.0,5.0,6.0]}` |
| `Dictionary` | `{1: "Hub", &"room": "Cellar"}` | `{"$t":"Dictionary","v":[[1,"Hub"],[{"$t":"StringName","v":"room"},"Cellar"]]}` |
| `Dictionary` | `{"$t": "note"}` | `{"$t":"Dictionary","v":[["$t","note"]]}` |
| `PackedByteArray` | `PackedByteArray([0, 255, 7])` | `{"$t":"PackedByteArray","v":"AP8H"}` |
| `PackedInt32Array` | `PackedInt32Array([1, -2])` | `{"$t":"PackedInt32Array","v":[1,-2]}` |
| `PackedInt64Array` | `PackedInt64Array([1, 9007199254740993])` | `{"$t":"PackedInt64Array","v":[1,{"$t":"int","v":"20000000000001"}]}` |
| `PackedFloat32Array` | `PackedFloat32Array([0.5, 0.1])` | `{"$t":"PackedFloat32Array","v":[0.5,0.10000000149011612]}` |
| `PackedFloat64Array` | `PackedFloat64Array([0.5, INF])` | `{"$t":"PackedFloat64Array","v":[0.5,"7ff0000000000000"]}` |
| `PackedStringArray` | `PackedStringArray(["Hub", "Cellar"])` | `{"$t":"PackedStringArray","v":["Hub","Cellar"]}` |
| `PackedVector2Array` | `PackedVector2Array([Vector2(1, 2)])` | `{"$t":"PackedVector2Array","v":[[1.0,2.0]]}` |
| `PackedVector3Array` | `PackedVector3Array([Vector3(1, 2, 3)])` | `{"$t":"PackedVector3Array","v":[[1.0,2.0,3.0]]}` |
| `PackedColorArray` | `PackedColorArray([Color(1, 0, 0, 1)])` | `{"$t":"PackedColorArray","v":[[1.0,0.0,0.0,1.0]]}` |

The order of components:

- **Vectors, Color, Quaternion:** their components in order (`x, y, z, w` or `r, g, b, a`).
- **Rect2 and AABB:** position first, then size.
- **Basis:** its `x`, `y` and `z` columns.
- **Transform2D:** `x`, `y`, then `origin`.
- **Transform3D:** the basis (9 values), then `origin`.
- **Integer vectors** (`Vector2i`, `Vector3i`, `Rect2i`) hold 32-bit ints.

### Real numbers: two forms

Godot's JSON is not exact for every float. Measured on Godot 4.7.2:

- about half of random doubles change after `JSON.stringify` (full precision) and then `JSON.parse_string`;
- about 20% of float32 values change the same way;
- `-0.0` loses its sign.

So every real number (a `float`, or a component of a vector, color, rect, basis, transform or packed float array) is written in one of two forms:

1. **A plain JSON number**, when Godot's own stringify-then-parse round trip gives back exactly the same bits. Everyday values such as `0.5`, `1.0`, `100.25`, `0.1` and `1/3` use this form.
2. **Its IEEE-754 bits**, as exactly 16 lowercase hex digits (the 64-bit double, most significant byte first), for everything else. NaN, `INF`, `-INF` and `-0.0` always use this form. Examples: `1.0` would be `"3ff0000000000000"`, `-0.0` is `"8000000000000000"`, `INF` is `"7ff0000000000000"`, and `123456789.123456789` is `"419d6f34547e6b75"`.

**A decoder must accept both forms for any real.** A plain JSON number, whole or not, and a 16-hex-digit string are both valid wherever a real is expected. The writer picks the form; the reader never relies on which one it gets. Either way the value comes back bit for bit, and `pack` output is byte-identical for the same input.

### Integers

An `int` from −2^53 to 2^53 is a plain JSON number (Godot reads those back exactly). A larger one is tagged `int` with a signed lowercase hex string: `-8000000000000000` is the smallest int64, and `7fffffffffffffff` the largest. Untagged numbers in a body must be whole and at most 2^53; anything else is refused.

### Dictionaries and the escaping rule

A Dictionary is a plain JSON object only if **every key is a String and no key is `"$t"`**. Otherwise it is written in the **escaped form**: a `Dictionary` tag holding a list of `[key, value]` pairs.

- Keys keep their type: an int key is a plain number (tagged only beyond 2^53), and a StringName key is tagged.
- A dictionary that really has a `"$t"` key is always escaped, so user data can never be mistaken for a tag.
- Allowed key types are String, StringName and int. Any other key type is refused with `E_BAD_KEY`.

A JSON object that has a `"$t"` key must have **exactly** the keys `"$t"` (a string) and `"v"`. Anything else is refused.

### Refused types

Encoding refuses, with `E_UNSUPPORTED_TYPE` and the path to the value (for example `body.player.weapon` or `body.items[2]`):

- Object of any kind (Node, Resource, RefCounted)
- Callable, Signal, RID
- every type not in the table above, for example `Vector4i`, `Plane`, `Projection` and `PackedVector4Array`

## Limits

| Limit | Default | Where |
| --- | --- | --- |
| Nesting depth of arrays and dictionaries | 64 | `encode(value, root, max_depth)`, `decode(value, root, max_depth, max_string_bytes)`, `unpack(text, max_depth, max_string_bytes)` |
| Total size of all strings, in UTF-8 bytes | 32 MB | `decode(...)`, `unpack(...)` |

The depth limit also stops a self-containing array from overflowing the stack while encoding. Leaf tags (a vector's component list, for example) do not count as an extra level.

## Error codes

| Code | From | Meaning |
| --- | --- | --- |
| `E_UNSUPPORTED_TYPE` | codec | A value of a type that cannot be saved. |
| `E_BAD_KEY` | codec | A Dictionary key that is not String, StringName or int. |
| `E_TOO_DEEP` | codec, envelope | Nesting deeper than the limit. |
| `E_TOO_LARGE` | codec | Strings larger than the limit in total. |
| `E_UNKNOWN_TAG` | codec | A `"$t"` that names no known type. |
| `E_BAD_TAG` | codec | A tag with extra or missing keys, or a payload of the wrong shape: wrong component count, bad hex or base64, a 32-bit int out of range, or an int64 overflow. |
| `E_BAD_VALUE` | codec | A plain value that cannot be decoded, such as an untagged fractional number. |
| `E_JSON` | envelope | The file is not valid JSON. |
| `E_FORMAT` | envelope | Valid JSON, but not a Strongbox save: wrong layout, a missing or mistyped header field, or a body that is not an object. |
| `E_FORMAT_TOO_NEW` | envelope | `format_version` is newer than this version of Strongbox can read. |
| `E_CHECKSUM` | envelope | The body does not match the checksum: the file was changed or damaged. |

## Unsafe-call rule

The addon never deserializes save data with engine calls that can create objects or run code. A GUT test (`tests/core/test_no_unsafe_calls.gd`) scans every `.gd` file under `addons/strongbox/` and fails on any of the following:

- **Always refused:** `str_to_var`, `bytes_to_var`, `bytes_to_var_with_objects`, `var_to_str`, `ResourceLoader`.
- **Bare `load(` and `preload(` calls.**

The scan ignores:

- member calls such as `.load(` and `Image.load_png_from_buffer(`;
- the definition of a method named `load` (`func load(...)`);
- anything inside `#` comments, apart from the marker below. A `#` inside a string literal does not start a comment.

**One opt-out marker.** A single line may end with the comment

```gdscript
# strongbox: allow-load (res:// allow-list checked)
```

to allow a bare `load(` that only receives paths checked against the game's `res://` allow-list. The marker never allows the always-refused names. It is allowed **only** in `addons/strongbox/state/world_store.gd`, for re-creating spawned scenes. Anywhere else, the scan fails. A new exception must be agreed on its task first, then added to the test's allow-list.

## Choices that differ from the original task

These were agreed during review:

1. `encode` and `decode` return `StrongboxResult`, not a bare `Variant`, so errors carry a code and a message.
2. `encode` and `decode` take optional parameters: `root` (the first segment of error paths, `"value"` by default; the envelope passes `"body"` and `"header"`), `max_depth`, and for `decode`, `max_string_bytes`.
3. Tag names are Godot's own type names, for example `"Dictionary"` rather than `"dict"`.
4. The escaped Dictionary form is used for any non-String key, not only for int keys.
5. Real numbers use the two forms described above, because Godot's JSON is not exact for every float.
6. `StrongboxCodec.tag_for_type(type)` is a small public helper that returns a type's tag name.
7. `StrongboxEnvelope.pack(body, meta, schema_version, game_version, playtime_s, saved_unix)` takes the header values as optional parameters. `saved_unix` defaults to the current time.
8. The checksum covers the canonical form of the body (see above), so reformatting a file keeps it valid.
