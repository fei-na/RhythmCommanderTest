extends Node
class_name CommandRecognizer

const RhythmDetector = preload("res://scripts/rhythm/RhythmDetector.gd")
const CharacterCommand = preload("res://resources/character/CharacterCommand.gd")

## 命令识别器 - 识别玩家输入的鼓点序列
## 支持固定4拍命令识别

# 信号：命令识别成功（返回 CharacterCommand, sequence, 第4拍输入的time_since_beat）
signal command_recognized(command: CharacterCommand, sequence: Array, time_since_beat: float)
signal queue_updated(drum: RhythmDetector.DrumType)  # 队列更新

# 兼容旧代码：保留枚举但不推荐使用
enum CommandType {
	NONE,
	ATTACK, MOVE_FORWARD, MOVE_BACKWARD, DEFEND, CHARGE, DODGE, SPECIAL, RECALL, JUMP, PURIFY, ULTIMATE,
	LONG_PRESS_ATTACK, LONG_PRESS_DEFEND, LONG_PRESS_SPECIAL,
}

class CommandDefinition:
	var name: String
	var type: CommandType  # 兼容用
	var sequence: Array  # Array of DrumType
	var beats_per_key: Array[int]  # 每按键持续拍数 [1,1,1,1] vs [4] 区分 AAAA 和 A~~~
	var cooldown: float = 0.0
	var can_use_in_window: bool = false
	var source_command: CharacterCommand = null  # 关联的资源

# 存储 CharacterCommand 资源的列表
var command_resources: Array[CharacterCommand] = []

var input_queue: Array = []  # 当前输入队列 (存储 {drum: DrumType, beats: int})
var last_add_times: Dictionary = {}  # {drum: last_add_time} 每个鼓点的最后添加时间
var max_queue_length: int = 8
var command_timeout: float = 2.0  # 命令超时时间(秒)
var last_input_time: float = 0.0

var registered_commands: Array = []  # 注册的命令列表
var active_commands: Array = []  # 当前角色激活的命令列表
var cycle_manager: Node  # 引用节奏循环管理器

func _ready() -> void:
	# 获取节奏循环管理器
	cycle_manager = get_tree().get_first_node_in_group("rhythm_cycle_manager")

	print("🎯 命令识别器已就绪")

## 从 CharacterCommand 资源数组注册命令
func register_commands_from_resources(resources: Array[CharacterCommand]) -> void:
	command_resources = resources

	for cmd_res in resources:
		# 解析资源
		cmd_res.parse()

		# 创建命令定义
		var cmd_def := CommandDefinition.new()
		cmd_def.name = cmd_res.command_name if cmd_res.command_name != "" else cmd_res.input_string
		cmd_def.type = CommandType.NONE  # 不再使用
		cmd_def.sequence = cmd_res.parsed_input_keys.duplicate()
		cmd_def.beats_per_key = cmd_res.parsed_beats_per_key.duplicate()  # 保存节拍持续信息
		cmd_def.source_command = cmd_res

		# 添加到注册列表
		registered_commands.append(cmd_def)

		print("📋 已注册命令: %s - %s (序列: %s)" % [cmd_def.name, cmd_res.input_string, cmd_res.parsed_input_keys])

	# 更新激活命令
	active_commands = registered_commands.duplicate()

## 设置激活的命令列表（由角色调用）- 基于 input_string 匹配
func set_active_commands(input_strings: Array[String]) -> void:
	active_commands.clear()

	for input_str in input_strings:
		for reg_cmd in registered_commands:
			if reg_cmd.source_command and reg_cmd.source_command.input_string == input_str:
				active_commands.append(reg_cmd)
				break

	print("📋 激活命令数: %d" % active_commands.size())

func _process(delta: float) -> void:
	# 清理超时的输入
	if input_queue.size() > 0:
		if Time.get_ticks_msec() / 1000.0 - last_input_time > command_timeout:
			clear_queue()

## 添加鼓点到队列
## beats: 该按键持续的拍数（用于区分 AAAA 和 A~~~）
## current_time: 调用时的时间戳
func add_drum(drum: RhythmDetector.DrumType, beats: int = 1, current_time: float = -1.0) -> void:
	if current_time < 0:
		current_time = Time.get_ticks_msec() / 1000.0

	last_input_time = current_time

	# 如果队列已满，移除最旧的输入
	if input_queue.size() >= max_queue_length:
		input_queue.pop_front()

	# 检查是否是同一鼓点的累加（长按）
	# 条件：队列末尾是同一个鼓点、beats 在增加（说明是 _on_beat 在累加）
	var should_update = false
	if input_queue.size() > 0:
		var last_item = input_queue[input_queue.size() - 1]
		if last_item is Dictionary and last_item["drum"] == drum:
			var last_beats = last_item["beats"]
			# 如果 beats > last_beats，说明是累加（长按），更新而不是添加
			if beats > last_beats:
				should_update = true

	if should_update:
		# 长按累加：更新最后一个元素的 beats
		var last_idx = input_queue.size() - 1
		input_queue[last_idx]["beats"] = beats
		print("🔍 add_drum(累加): drum=%d, beats=%d, queue=%s" % [drum, beats, input_queue])
	else:
		# 短按：添加新元素
		input_queue.append({ "drum": drum, "beats": beats })
		print("🔍 add_drum(新元素): drum=%d, beats=%d, queue=%s" % [drum, beats, input_queue])

	# 更新时间戳
	last_add_times[drum] = current_time

	queue_updated.emit(drum)

	# 空档期不识别命令（只允许翻滚等特殊操作）
	if _is_in_idle_phase():
		print("💤 空档期，不识别命令")
		return

	# 尝试识别命令
	_try_recognize_command()

## 更新队列中最后一个指定鼓点的持续拍数（释放时调用）
func update_last_drum_beats(drum: RhythmDetector.DrumType, beats: int) -> void:
	# 从后往前找最后一个匹配的鼓点
	for i in range(input_queue.size() - 1, -1, -1):
		var item = input_queue[i]
		if item is Dictionary and item["drum"] == drum:
			input_queue[i]["beats"] = beats
			print("🔍 update_last_drum_beats: drum=%d, beats=%d, queue=%s" % [drum, beats, input_queue])
			return

## 判断当前是否在空档期
func _is_in_idle_phase() -> bool:
	if cycle_manager and cycle_manager.has_method("is_in_idle_phase"):
		return cycle_manager.is_in_idle_phase()
	return false

## 清空队列
func clear_queue() -> void:
	input_queue.clear()
	last_add_times.clear()
	queue_updated.emit(RhythmDetector.DrumType.RIGHT)  # 发送虚拟事件更新UI

## 尝试识别命令
func _try_recognize_command() -> void:
	# 使用 active_commands
	for command in active_commands:
		if _is_sequence_match(input_queue, command.sequence, command.beats_per_key):
			# 获取最近一次输入的time_since_beat（用于判断早晚按）
			var time_since_beat: float = 0.0
			var rhythm_detector = get_tree().get_first_node_in_group("rhythm_detector")
			if rhythm_detector and rhythm_detector.has_method("get_last_input_time_since_beat"):
				time_since_beat = rhythm_detector.get_last_input_time_since_beat()

			# 调试：打印source_command的input_string
			var src_input_str = "N/A"
			if command.source_command:
				src_input_str = command.source_command.input_string
			print("🔍 匹配成功: name=%s, source_command.input_string=%s, command.sequence=%s, input_queue=%s" % [command.name, src_input_str, command.sequence, input_queue])

			# 找到匹配，触发命令 - 直接返回 CharacterCommand
			command_recognized.emit(command.source_command, command.sequence, time_since_beat)
			print("✅ 命令识别: %s - %s (time_since_beat=%.2fs)" % [command.name, _sequence_to_string(command.sequence), time_since_beat])

			# 清空队列
			clear_queue()
			return

## 检查序列是否匹配
func is_queue_empty() -> bool:
	return input_queue.size() == 0

func get_queue_size() -> int:
	return input_queue.size()

func _is_sequence_match(input: Array, pattern: Array, beats_per_key: Array[int]) -> bool:
	# 长按命令匹配：pattern 只有1个元素，且队列也必须只有1个元素
	# 例如 A~~~: pattern=[A], beats_per_key=[4], queue=[{A,4}] (1个元素)
	# 如果队列有多个元素，说明是多次短按，不是长按
	if pattern.size() == 1:
		# 长按命令必须队列只有1个元素
		if input.size() != 1:
			return false
		var expected_drum = pattern[0]
		var expected_beats = beats_per_key[0]
		var item = input[0]
		var drum = item["drum"] if item is Dictionary else item
		var beats = item["beats"] if item is Dictionary else 1
		return drum == expected_drum and beats == expected_beats

	# 普通匹配：必须长度相等
	if input.size() != pattern.size():
		return false

	for i in range(pattern.size()):
		# 检查按键类型
		var input_drum = input[i]["drum"] if input[i] is Dictionary else input[i]
		if input_drum != pattern[i]:
			return false
		# 检查每按键持续拍数
		var input_beats = input[i]["beats"] if input[i] is Dictionary else 1
		if input_beats != beats_per_key[i]:
			return false

	return true

func _sequence_to_string(seq: Array) -> String:
	var result := ""
	for drum in seq:
		if drum == RhythmDetector.DrumType.UP:
			result += "↑"
		elif drum == RhythmDetector.DrumType.DOWN:
			result += "↓"
		elif drum == RhythmDetector.DrumType.LEFT:
			result += "←"
		elif drum == RhythmDetector.DrumType.RIGHT:
			result += "→"
	return result
