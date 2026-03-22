extends Node
class_name InputManager

const RhythmDetector = preload("res://scripts/rhythm/RhythmDetector.gd")

## 输入管理器 - 处理鼓点输入
## 将键盘/手柄输入转换为鼓点信号

signal drum_input(drum: RhythmDetector.DrumType)  # 鼓点输入信号
signal key_pressed(drum: RhythmDetector.DrumType, time: float)  # 按键按下
signal key_released(drum: RhythmDetector.DrumType, duration: float)  # 按键释放（长按）

@export var rhythm_detector: RhythmDetector
@export var command_recognizer: CommandRecognizer
@export var cycle_manager: RhythmCycleManager

# 键盘按键映射
var key_to_drum: Dictionary = {
	KEY_W: RhythmDetector.DrumType.UP,
	KEY_S: RhythmDetector.DrumType.DOWN,
	KEY_A: RhythmDetector.DrumType.LEFT,
	KEY_D: RhythmDetector.DrumType.RIGHT,
	KEY_UP: RhythmDetector.DrumType.UP,
	KEY_DOWN: RhythmDetector.DrumType.DOWN,
	KEY_LEFT: RhythmDetector.DrumType.LEFT,
	KEY_RIGHT: RhythmDetector.DrumType.RIGHT,
}

# 长按检测
var pressed_keys: Dictionary = {}  # {keycode: press_time}

func _ready() -> void:
	print("⌨️ 输入管理器已就绪 - 使用 W/A/S/D 或 方向键")
	# 添加到组
	add_to_group("input_manager")
	# 获取节奏循环管理器
	cycle_manager = get_tree().get_first_node_in_group("rhythm_cycle_manager")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if key_to_drum.has(event.keycode):
			var drum: RhythmDetector.DrumType = key_to_drum[event.keycode]

			if event.pressed:
				# 按下：记录时间
				pressed_keys[event.keycode] = Time.get_ticks_msec() / 1000.0
				key_pressed.emit(drum, pressed_keys[event.keycode])
				_handle_drum_input(drum)
			else:
				# 释放：检测长按
				if pressed_keys.has(event.keycode):
					var press_time = pressed_keys[event.keycode]
					var release_time = Time.get_ticks_msec() / 1000.0
					var duration = release_time - press_time
					pressed_keys.erase(event.keycode)
					key_released.emit(drum, duration)
					print("🔓 释放按键: %s, 时长: %.2fs" % [_get_drum_str(drum), duration])

func _get_drum_from_key(keycode: int) -> RhythmDetector.DrumType:
	if key_to_drum.has(keycode):
		return key_to_drum[keycode]
	return RhythmDetector.DrumType.UP  # 默认返回 UP，实际上不会被使用

func _handle_drum_input(drum: RhythmDetector.DrumType) -> void:
	# 检查是否在Miss冷却期
	if cycle_manager and not cycle_manager.is_input_allowed():
		print("🚫 输入被拦截（冷却期）")
		return

	# 发送输入信号
	drum_input.emit(drum)

	# 发送到节奏检测器进行判定
	if rhythm_detector:
		rhythm_detector.input_drum(drum)

	# 发送到命令识别器
	if command_recognizer:
		command_recognizer.add_drum(drum)

	# 显示输入反馈
	_print_drum_input(drum)

func _print_drum_input(drum: RhythmDetector.DrumType) -> void:
	print("👆 按下: %s" % _get_drum_str(drum))

func _get_drum_str(drum: RhythmDetector.DrumType) -> String:
	if drum == RhythmDetector.DrumType.UP:
		return "↑ (W/↑)"
	elif drum == RhythmDetector.DrumType.DOWN:
		return "↓ (S/↓)"
	elif drum == RhythmDetector.DrumType.LEFT:
		return "← (A/←)"
	elif drum == RhythmDetector.DrumType.RIGHT:
		return "→ (D/→)"
	return "?"
