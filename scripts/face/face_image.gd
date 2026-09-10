class_name PetFaceImage
extends RefCounted

static func prepare(source: Image) -> Dictionary:
	if source == null or source.is_empty():
		return {"error": "生成图为空，请重新生成。"}
	if source.get_width() < 32 or source.get_height() < 32:
		return {"error": "生成图分辨率过低。"}
	var image := source.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var longest := maxi(image.get_width(), image.get_height())
	if longest > 512:
		image.resize(maxi(1, image.get_width() * 512 / longest), maxi(1, image.get_height() * 512 / longest), Image.INTERPOLATE_LANCZOS)
	var opaque: int = 0
	var clear: int = 0
	var border: int = 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			var color := image.get_pixel(x, y)
			# Key only the specified chroma; never guess skin/white/black backgrounds.
			if color.r > 0.72 and color.b > 0.72 and color.g < 0.30 and absf(color.r - color.b) < 0.2:
				color = Color.TRANSPARENT
				image.set_pixel(x, y, color)
			if color.a > 0.1:
				opaque += 1
				if x == 0 or y == 0 or x == image.get_width() - 1 or y == image.get_height() - 1:
					border += 1
			else:
				clear += 1
	var total := image.get_width() * image.get_height()
	if opaque < 16 or float(opaque) / total < 0.001:
		return {"error": "未检测到可用五官，生成图几乎全透明。"}
	if float(clear) / total < 0.55 or border > 0:
		return {"error": "生成图不符合透明五官规范（底色、面片或边缘未清除），请重新生成。"}
	# Normalize to square without stretching the person's proportions.
	var side := maxi(image.get_width(), image.get_height())
	var square := Image.create(side, side, false, Image.FORMAT_RGBA8)
	square.fill(Color.TRANSPARENT)
	square.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), (Vector2i(side, side) - image.get_size()) / 2)
	return {"error": "", "image": square}
