## 技能 - 定义角色的可触发技能
class_name Skill
extends Resource

const RhythmDetector = preload("res://scripts/rhythm/RhythmDetector.gd")

enum TriggerType {
	HOLD_RELEASE,  # 长按释放触发
	COMBO,         # 連擊觸發
	PASSIVE        # 被動技能
}

@export var skill_id: String = ""
@export var skill_name: String = ""
@export var description: String = ""

## 触发类型
@export var trigger_type: TriggerType = TriggerType.HOLD_RELEASE

## 触发需要的按键（A/B/X/Y）
@export var required_drum: RhythmDetector.DrumType = RhythmDetector.DrumType.UP

## 长按需要持续的拍数（2/3/4）
@export var required_beats: int = 4

## 伤害/治疗倍率
@export var power_multiplier: float = 1.5

## 防御倍率
@export var defense_multiplier: float = 1.0

## 冷却时间（秒）
@export var cooldown: float = 0.0

## 动画名称
@export var animation_name: String = ""

## 消耗的资源ID（可选）
@export var cost_resource_id: String = ""

## 消耗的资源数量
@export var cost_amount: int = 0

## 连击需要的序列（仅COMBO类型使用）
@export var required_combo: Array[RhythmDetector.DrumType] = []

var _current_cooldown: float = 0.0

func _ready() -> void:
	_current_cooldown = 0.0

func can_use() -> bool:
	return _current_cooldown <= 0.0

func use() -> void:
	if cooldown > 0.0:
		_current_cooldown = cooldown

func update_cooldown(delta: float) -> void:
	if _current_cooldown > 0.0:
		_current_cooldown -= delta

func get_required_duration() -> float:
	# 由外部 rhythm_detector 传入 beat_interval 计算
	return 0.0
