extends Node
## BGM / SE の音量を一元管理するオートロード。
## オーディオバスを用意し、設定を user://settings.cfg に保存・復元する。

const BUS_BGM := "BGM"
const BUS_SE := "SE"
const MIN_DB := -30.0
const SETTINGS_PATH := "user://settings.cfg"

func _enter_tree() -> void:
	_ensure_bus(BUS_BGM)
	_ensure_bus(BUS_SE)
	_load()

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)

func get_bgm_volume_db() -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(BUS_BGM))

func get_se_volume_db() -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(BUS_SE))

func set_bgm_volume_db(db: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(BUS_BGM), db)

func set_se_volume_db(db: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(BUS_SE), db)

func save_settings() -> void:
	_save()

func percent_to_db(p01: float) -> float:
	# スライダー値(0〜1)を dB(-30〜0) に変換
	return lerpf(MIN_DB, 0.0, clampf(p01, 0.0, 1.0))

func db_to_percent(db: float) -> float:
	return (clampf(db, MIN_DB, 0.0) - MIN_DB) / (-MIN_DB)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(BUS_BGM), float(cfg.get_value("audio", "bgm_db", 0.0)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(BUS_SE), float(cfg.get_value("audio", "se_db", 0.0)))

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "bgm_db", get_bgm_volume_db())
	cfg.set_value("audio", "se_db", get_se_volume_db())
	cfg.save(SETTINGS_PATH)
