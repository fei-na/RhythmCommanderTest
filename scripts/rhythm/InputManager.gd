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
var held_keys_beat_count: Dictionary = {}  # {keycode: current_beats_held}
var beat_interval: float = 0.5  # 节拍间隔（秒）

func _ready() -> void:
	print("⌨️ 输入管理器已就绪 - 使用 W/A/S/D 或 方向键")
	add_to_group("input_manager")
	cycle_manager = get_tree().get_first_node_in_group("rhythm_cycle_manager")
	var rd = get_tree().get_first_node_in_group("rhythm_detector")
	if rd:
		rd.beat_triggered.connect(_on_beat)
		beat_interval = rd.beat_interval

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if key_to_drum.has(event.keycode):
			var drum: RhythmDetector.DrumType = key_to_drum[event.keycode]

			if event.pressed:
				# 如果该键已经在 held_keys_beat_count 中（长按中），跳过
				if held_keys_beat_count.has(event.keycode):
					print("🔒 跳过重复按下（长按中）: %s" % [_get_drum_str(drum)])
					return
				# 按下：记录时间，初始化持续拍数为1
				var current_time = Time.get_ticks_msec() / 1000.0
				pressed_keys[event.keycode] = current_time
				held_keys_beat_count[event.keycode] = 1
				key_pressed.emit(drum, current_time)
				_handle_drum_input(drum, current_time)
			else:
				# 释放
				if pressed_keys.has(event.keycode):
					var press_time = pressed_keys[event.keycode]
					var release_time = Time.get_ticks_msec() / 1000.0
					var duration = release_time - press_time
					pressed_keys.erase(event.keycode)
					held_keys_beat_count.erase(event.keycode)

					# 判断是单击还是长按：
					# 条件1: duration <= beat_interval（按下和抬在同一拍内）
					# 条件2: duration < 0.2s（按下和抬在0.2秒内）
					var is_short_press = duration <= beat_interval or duration < 0.3

					# 释放时更新队列中最后一个该鼓点的 beats
					if command_recognizer:
						if is_short_press:
							# 单击：更新为 beats=1
							command_recognizer.update_last_drum_beats(drum, 1)
							print("🔓 释放按键(单击): %s, 时长: %.2fs" % [_get_drum_str(drum), duration])
						else:
							# 长按：更新为实际按住跨过的拍数
							var beats_held = ceili(duration / beat_interval)
							beats_held = clamp(beats_held, 1, 8)
							command_recognizer.update_last_drum_beats(drum, beats_held)
							print("🔓 释放按键(长按): %s, 时长: %.2fs, %d 拍" % [_get_drum_str(drum), duration, beats_held])
					key_released.emit(drum, duration)

func _get_drum_from_key(keycode: int) -> RhythmDetector.DrumType:
	if key_to_drum.has(keycode):
		return key_to_drum[keycode]
	return RhythmDetector.DrumType.UP

func _handle_drum_input(drum: RhythmDetector.DrumType, press_time: float) -> void:
	if cycle_manager and not cycle_manager.is_input_allowed():
		print("🚫 输入被拦截（冷却期）")
		return

	drum_input.emit(drum)

	if rhythm_detector:
		rhythm_detector.input_drum(drum)

	if command_recognizer:
		command_recognizer.add_drum(drum, 1, press_time)

	print("👆 按下: %s" % [_get_drum_str(drum)])

## 节拍到来时（长按时累加到队列）
func _on_beat(beat: int) -> void:
	# 只处理在 held_keys_beat_count 中的键（表示还在按住的）
	for keycode in held_keys_beat_count.keys():
		var drum = _get_drum_from_key(keycode)
		var beats = held_keys_beat_count[keycode]

		# 增加持续拍数
		beats += 1
		held_keys_beat_count[keycode] = beats

		# 只有 beats > 1 时才添加到队列进行累加（即真正的长按）
		# beats == 1 表示这可能是单击，不添加
		if beats > 1 and command_recognizer:
			command_recognizer.add_drum(drum, beats)
			print("🔍 节拍 %d: %s 长按持续，已持续 %d 拍" % [beat, _get_drum_str(drum), beats])
		else:
			print("🔍 节拍 %d: %s 跳过累加（beats=%d）" % [beat, _get_drum_str(drum), beats])

## 检查指定按键是否仍在被按住
func _is_key_held(keycode: int) -> bool:
	return Input.is_key_pressed(keycode)

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
