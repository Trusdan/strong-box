extends GutTest

## Smoke test: the addon is present and its version is well formed.

const PLUGIN_CFG_PATH: String = "res://addons/strongbox/plugin.cfg"
const VERSION_PATH: String = "res://addons/strongbox/VERSION"
const SEMVER_PATTERN: String = "^\\d+\\.\\d+\\.\\d+$"


func _read_version() -> String:
	return FileAccess.get_file_as_string(VERSION_PATH).strip_edges()


func test_plugin_config_exists_and_loads() -> void:
	assert_true(FileAccess.file_exists(PLUGIN_CFG_PATH), "plugin.cfg should exist")
	var cfg: ConfigFile = ConfigFile.new()
	var err: Error = cfg.load(PLUGIN_CFG_PATH)
	assert_eq(err, OK, "plugin.cfg should parse")
	assert_eq(str(cfg.get_value("plugin", "name", "")), "Strongbox")
	assert_eq(str(cfg.get_value("plugin", "script", "")), "plugin.gd")


func test_version_is_semver() -> void:
	assert_true(FileAccess.file_exists(VERSION_PATH), "VERSION should exist")
	var version: String = _read_version()
	var regex: RegEx = RegEx.create_from_string(SEMVER_PATTERN)
	assert_not_null(regex.search(version), "VERSION '%s' should match %s" % [version, SEMVER_PATTERN])


func test_plugin_config_version_matches_version_file() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	assert_eq(cfg.load(PLUGIN_CFG_PATH), OK)
	assert_eq(str(cfg.get_value("plugin", "version", "")), _read_version(), "plugin.cfg version should equal VERSION")
