## 角色指令配置 - 定义每个指令的效果
class_name CharacterCommand
extends Resource

const CommandSequenceStage = preload("res://resources/character/CommandSequenceStage.gd")
const DamageStage = preload("res://resources/character/DamageStage.gd")

# ========== 输入序列配置 ==========

# 可读输入序列字符串
# 示例: "AAAA", "DDDD", "DADA", "W~A~", "A~~~"
# ~ 代表长按1拍，A~~~ = A长按4拍
@export var input_string: String = ""

# 空档期序列字符串
# 示例: "_W", "_WD", "_WWWW"
# _ 表示空档期开始，后面的字符是空档期按键
@export var idle_string: String = ""

# 解析后的输入序列（按键列表）
# 例如 "AAAA" -> [A,A,A,A], "W~A~" -> [W,W,A,A]
var parsed_input_keys: Array[int] = []

# 解析后的每按键持续拍数
# 例如 "AAAA" -> [1,1,1,1], "W~A~" -> [2,2]
var parsed_beats_per_key: Array[int] = []

# 是否为长按指令
var is_long_press: bool = false

# 空档期按键序列
var parsed_idle_keys: Array[int] = []

# 指令名称
@export var command_name: String = ""

# 指令描述
@export var description: String = ""

# 动画名称
@export var animation_name: String = ""

# 效果倍率
@export var power_multiplier: float = 1.0  # 伤害/治疗倍率
@export var defense_multiplier: float = 0.0  # 防御减伤倍率（1.0 = 100%减伤）
@export var cooldown_multiplier: float = 1.0  # 冷却倍率

# 消耗
@export var mp_cost: int = 0  # MP消耗

# 是否可以在空中使用
@export var can_use_in_air: bool = false

# 是否可以在空档期使用
@export var can_use_in_idle: bool = false

# 是否支持序列阶段（连击）
@export var has_sequence: bool = false

# 序列阶段配置（用于连击/连续攻击的不同阶段）
@export var sequence_stages: Array[CommandSequenceStage]

# 特效
@export var effect_scene: PackedScene  # 特效场景
@export var sound_effect: String = ""  # 音效资源路径

# ========== 多段伤害配置 ==========
@export var damage_stages: Array[DamageStage] = []

# ========== 资源消耗/获得 ==========
# 格式: {resource_id: amount}
# 例如: {"sword_shield": 1}
@export var resource_cost: Dictionary = {}

# 资源获得（指令执行成功后获得）
# 格式: {resource_id: {sub_type: amount}}
# 例如: {"sword_shield": {"sword": 1}, "arrow_mark": {"arrow": 1}}
@export var resource_gain: Dictionary = {}

# ========== 特殊效果 ==========
# 是否为弹反指令
@export var is_parry: bool = false

# 完美弹反窗口（秒）
@export var perfect_parry_window: float = 0.0

# 完美弹反额外资源获得
@export var resource_gain_on_perfect_parry: Dictionary = {}


# ========== 初始化与解析 ==========
func _init() -> void:
	pass  # 延迟解析，在 _ready 或手动调用时解析

func _ready() -> void:
	parse()

## 手动解析（编辑器修改属性后调用）
func parse() -> void:
	_parse_input_string()
	_parse_idle_string()

## 获取资源消耗数量
func get_resource_cost(resource_id: String) -> int:
	return resource_cost.get(resource_id, 0)

## 获取资源获得数量（通用）
func get_resource_gain(resource_id: String) -> Dictionary:
	return resource_gain.get(resource_id, {})

## 获取指定子类型的获得数量
func get_sub_type_gain(resource_id: String, sub_type: String) -> int:
	var gains = get_resource_gain(resource_id)
	return gains.get(sub_type, 0)

## 解析输入序列字符串
## "D~~~" 解析为 [D, D, D, D]（4个D表示4拍）
## "W~A~" 解析为 [W, W, A, A]（W长按2拍 + A长按2拍）
func _parse_input_string() -> void:
	if input_string == "":
		return

	parsed_input_keys.clear()
	parsed_beats_per_key.clear()
	is_long_press = false

	var i = 0
	while i < input_string.length():
		var char = input_string[i]

		# 跳过空档期前缀
		if char == "_":
			break

		# 跳过空格
		if char == " ":
			i += 1
			continue

		# 获取按键类型
		var key = _char_to_drum_type(char)
		if key == -1:
			i += 1
			continue

		# 检查后续的 ~ 数量（长按拍数）
		var beats = 1
		var j = i + 1
		while j < input_string.length() and input_string[j] == "~":
			beats += 1
			j += 1

		# 添加 beats 个重复的 key（长按用重复按键表示）
		for _k in range(beats):
			parsed_input_keys.append(key)
		parsed_beats_per_key.append(beats)

		if beats > 1:
			is_long_press = true

		i = j

## 解析空档期序列（不需要下划线前缀，直接写 "WW" 即可）
func _parse_idle_string() -> void:
	parsed_idle_keys.clear()

	if idle_string == "":
		return

	var i = 0
	# 兼容处理：跳过前导 _（如果用户误加了）
	while i < idle_string.length() and (idle_string[i] == "_" or idle_string[i] == " "):
		i += 1

	while i < idle_string.length():
		var char = idle_string[i]
		var key = _char_to_drum_type(char)
		if key != -1:
			parsed_idle_keys.append(key)
		i += 1

## 字符转 DrumType
func _char_to_drum_type(char: String) -> int:
	match char.to_upper():
		"W": return 0  # UP
		"A": return 1  # LEFT
		"S": return 2  # DOWN
		"D": return 3  # RIGHT
		_: return -1

## 获取总拍数
func get_total_beats() -> int:
	var total = 0
	for beats in parsed_beats_per_key:
		total += beats
	return total

## 获取空档期总按键数
func get_idle_key_count() -> int:
	return parsed_idle_keys.size()

# 获取最终的伤害值
func get_final_power(base_power: float) -> float:
	return base_power * power_multiplier

## 获取序列阶段配置
func get_stage_info(stage_index: int) -> CommandSequenceStage:
	if has_sequence and stage_index < sequence_stages.size():
		return sequence_stages[stage_index]
	return null
