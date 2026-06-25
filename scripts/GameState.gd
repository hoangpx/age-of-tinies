extends Node
## GameState — bộ lưu trữ tối giản cho Age of Tinies.
## Autoload "GameState". Chỉ cung cấp `save_data` (Dictionary) + `save()`
## để AdsManager / BillingManager nhớ cờ ads_enabled và các IAP đã mua.
## Lưu bằng ConfigFile ở user://aot_state.cfg.

var save_data: Dictionary = {}

const SAVE_PATH := "user://aot_state.cfg"


func _ready() -> void:
	_load()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	if cfg.has_section("data"):
		for k in cfg.get_section_keys("data"):
			save_data[k] = cfg.get_value("data", k)


func save() -> void:
	var cfg := ConfigFile.new()
	for k in save_data:
		cfg.set_value("data", k, save_data[k])
	cfg.save(SAVE_PATH)
