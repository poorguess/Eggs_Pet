extends SceneTree

const REGIONS := {
	"buttons": Rect2i(100, 855, 340, 55),
	"egg": Rect2i(180, 400, 190, 165),
	"shadow": Rect2i(220, 550, 110, 35),
}


func _initialize() -> void:
	for name: String in REGIONS:
		var region: Rect2i = REGIONS[name]
		for src in ["w3start_before", "w3start"]:
			var img := Image.load_from_file(ProjectSettings.globalize_path("res://build/%s/f00000005.png" % src))
			var crop := img.get_region(region)
			crop.resize(region.size.x * 3, region.size.y * 3, Image.INTERPOLATE_NEAREST)
			var out := "res://build/cmp_%s_%s.png" % [name, "a" if src == "w3start_before" else "b"]
			crop.save_png(ProjectSettings.globalize_path(out))
			print("wrote ", out)
	quit(0)
