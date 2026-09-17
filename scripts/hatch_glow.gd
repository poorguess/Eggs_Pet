class_name HatchGlow
extends Node2D

# 破壳光晕：蛋壳碎裂后从蛋的位置扩散开的一圈柠檬色柔光（原 main_island._draw_pet）。
# 半径 106 随闪光衰减从 108 涨到 127，透明度 0.26 → 0；数值沿用原实现。
const RADIUS := 106.0
const FLASH_DURATION := 1.2
const SWAY_AMPLITUDE := 4.0

var _flash := 0.0
var _elapsed := 0.0

func _process(delta: float) -> void:
	_elapsed += delta
	if _flash <= 0.0:
		return
	_flash = maxf(0.0, _flash - delta)
	position.y = sin(_elapsed * 2.0) * SWAY_AMPLITUDE
	queue_redraw()

# 触发一次满强度闪光；由蛋场景在破壳动画播完时调用。
func play_burst() -> void:
	_flash = FLASH_DURATION
	queue_redraw()

func _draw() -> void:
	if _flash <= 0.0:
		return
	draw_circle(
		Vector2.ZERO,
		RADIUS * (1.2 - _flash * 0.15),
		UiTheme.fade(UiTheme.LEMON, _flash * 0.22)
	)
