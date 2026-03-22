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
	var cooldown: float = 0.0
	var can_use_in_window: bool = false
	var source_command: CharacterCommand = null  # 关联的资源

# 存储 CharacterCommand 资源的列表
var command_resources: Array[CharacterCommand] = []

var input_queue: Array = []  # 当前输入队列
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
func add_drum(drum: RhythmDetector.DrumType) -> void:
	last_input_time = Time.get_ticks_msec() / 1000.0

	# 如果队列已满，移除最旧的输入
	if input_queue.size() >= max_queue_length:
		input_queue.pop_front()

	input_queue.append(drum)
	queue_updated.emit(drum)

	# 空档期不识别命令（只允许翻滚等特殊操作）
	if _is_in_idle_phase():
		print("💤 空档期，不识别命令")
		return

	# 尝试识别命令
	_try_recognize_command()

## 判断当前是否在空档期
func _is_in_idle_phase() -> bool:
	if cycle_manager and cycle_manager.has_method("is_in_idle_phase"):
		return cycle_manager.is_in_idle_phase()
	return false

## 清空队列
func clear_queue() -> void:
	input_queue.clear()
	queue_updated.emit(RhythmDetector.DrumType.RIGHT)  # 发送虚拟事件更新UI

## 尝试识别命令
func _try_recognize_command() -> void:
	# 使用 active_commands
	for command in active_commands:
		if _is_sequence_match(input_queue, command.sequence):
			# 获取最近一次输入的time_since_beat（用于判断早晚按）
			var time_since_beat: float = 0.0
			var rhythm_detector = get_tree().get_first_node_in_group("rhythm_detector")
			if rhythm_detector and rhythm_detector.has_method("get_last_input_time_since_beat"):
				time_since_beat = rhythm_detector.get_last_input_time_since_beat()

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

func _is_sequence_match(input: Array, pattern: Array) -> bool:
	# 必须完整匹配（长度相等），避免 D~~~ 被误认为 D
	if input.size() != pattern.size():
		return false

	for i in range(pattern.size()):
		if input[i] != pattern[i]:
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
