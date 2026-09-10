class_name FaceServiceConfig
extends RefCounted

const DEFAULT_URL := "https://huniuai.token6688.com/v1"
const USER_PATH := "user://face_api.cfg"

static func normalize_url(value: String) -> String:
	return value.strip_edges().trim_suffix("/").trim_suffix("/images/edits").trim_suffix("/")

static func validate(address: String, key: String, model: String, require_model: bool = true) -> String:
	if not address.begins_with("https://") or address.contains(" ") or address.contains("?") or address.contains("#") or address.contains("@"):
		return "请输入完整的 HTTPS 服务地址，例如 https://huniuai.token6688.com/v1。"
	if key.strip_edges().is_empty():
		return "请填写 API Key。"
	if address.trim_prefix("https://").get_slice("/", 0).is_empty():
		return "服务地址缺少域名。"
	if key.contains("\n") or key.contains("\r"):
		return "API Key 不能包含换行，请检查粘贴内容。"
	if require_model and model.strip_edges().is_empty():
		return "请填写图生图模型名称，或先获取模型列表。"
	return ""

static func read_config() -> ConfigFile:
	var config := ConfigFile.new()
	if config.load(USER_PATH) != OK:
		config.load("res://face_api.cfg")
	return config

static func save_config(address: String, key: String, model: String, path: String = USER_PATH) -> String:
	var base := normalize_url(address)
	var error := validate(base, key, model)
	if not error.is_empty():
		return error
	var config := read_config()
	config.set_value("api", "base_url", base)
	config.set_value("api", "endpoint", base + "/images/edits")
	config.set_value("api", "api_key", key.strip_edges())
	config.set_value("api", "model", model.strip_edges())
	var result := config.save(path + ".tmp")
	if result == OK:
		result = DirAccess.rename_absolute(path + ".tmp", path)
	return "" if result == OK else "配置保存失败（%d），请检查本机存储权限。" % result
