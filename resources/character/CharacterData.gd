## 角色数据 - 可作为 Resource 文件保存
class_name CharacterData
extends Resource

const CharacterCommand = preload("res://resources/character/CharacterCommand.gd")
const CharacterCommandOverride = preload("res://resources/character/CharacterCommandOverride.gd")
const CharacterResource = preload("res://resources/character/CharacterResource.gd")
const Skill = preload("res://resources/character/Skill.gd")
const RhythmDetector = preload("res://scripts/rhythm/RhythmDetector.gd")

# ═══════════════════════════════════════════════════════════════════
# 基础信息
# ═══════════════════════════════════════════════════════════════════

# 角色名称
@export var character_name: String = "Unknown"
@export var character_id: String = ""

# ═══════════════════════════════════════════════════════════════════
# 基础属性
# ═══════════════════════════════════════════════════════════════════

# 生命
@export var max_health: int = 100
@export var current_health: int = 100

# 移动
@export var move_speed: float = 200.0
@export var jump_height: float = 400.0

# 闪避
@export var dodge_rate: float = 0.0  # 闪避率 0%

# ═══════════════════════════════════════════════════════════════════
# 伤害类型定义
# ═══════════════════════════════════════════════════════════════════

## 伤害类型枚举
enum DamageType {
	SLASHING,    # 锋刃 - 切割/流血（每拍掉血）
	BLUNT,       # 钝击 - 震荡（额外高额伤害）
	FIRE,        # 火焰 - 灼烧（每拍掉血）
	ICE,         # 寒冰 - 冻结8拍，结束/死亡时AOE冰爆
	LIGHTNING,   # 雷电 - 每2拍传递给附近敌人
	POISON,      # 毒 - 每4拍触发毒伤害
	HOLY         # 圣灵 - 减弱敌人攻击
}

# ═══════════════════════════════════════════════════════════════════
# 各伤害类型属性（每种类型包含：加成%、减免%、触发率%）
# ═══════════════════════════════════════════════════════════════════

# 锋刃（切割/流血 - 每拍掉血）
@export_group("锋刃 Slashing", "slash_")
@export var slash_damage_percent: float = 100.0      # 伤害加成 100%
@export var slash_defense_percent: float = 0.0        # 伤害减免 0%
@export var slash_trigger_rate: float = 0.0           # 触发率 0%

# 钝击（额外高额伤害）
@export_group("钝击 Blunt", "blunt_")
@export var blunt_damage_percent: float = 100.0
@export var blunt_defense_percent: float = 0.0
@export var blunt_trigger_rate: float = 0.0

# 火焰（灼烧 - 每拍掉血）
@export_group("火焰 Fire", "fire_")
@export var fire_damage_percent: float = 100.0
@export var fire_defense_percent: float = 0.0
@export var fire_trigger_rate: float = 0.0

# 寒冰（冻结8拍，冰爆）
@export_group("寒冰 Ice", "ice_")
@export var ice_damage_percent: float = 100.0
@export var ice_defense_percent: float = 0.0
@export var ice_trigger_rate: float = 0.0

# 雷电（每2拍传递）
@export_group("雷电 Lightning", "lightning_")
@export var lightning_damage_percent: float = 100.0
@export var lightning_defense_percent: float = 0.0
@export var lightning_trigger_rate: float = 0.0

# 毒（每4拍触发）
@export_group("毒 Poison", "poison_")
@export var poison_damage_percent: float = 100.0
@export var poison_defense_percent: float = 0.0
@export var poison_trigger_rate: float = 0.0

# 圣灵（减弱敌人攻击）
@export_group("圣灵 Holy", "holy_")
@export var holy_damage_percent: float = 100.0
@export var holy_defense_percent: float = 0.0
@export var holy_trigger_rate: float = 0.0

# ═══════════════════════════════════════════════════════════════════
# 暴击与战斗属性
# ═══════════════════════════════════════════════════════════════════

@export_group("暴击与战斗", "combat_")
@export var crit_rate: float = 0.0          # 暴击率 0%
@export var crit_damage: float = 1.5        # 暴击伤害 150%
@export var lifesteal_percent: float = 0.0 # 吸血 0%

# ═══════════════════════════════════════════════════════════════════
# 必杀技能量系统
# ═══════════════════════════════════════════════════════════════════

@export_group("必杀技能量", "ult_")
@export var ult_energy_max: int = 100       # 必杀所需能量上限
@export var current_ult_energy: int = 0      # 当前能量
@export var cooldown_reduction: float = 0.0  # 技能冷却缩减 0%（减少所需能量）

# ═══════════════════════════════════════════════════════════════════
# 防御弹反系统
# ═══════════════════════════════════════════════════════════════════

@export_group("防御弹反", "parry_")
@export var parry_base_window: float = 0.2      # 基础完美弹反窗口（秒）
@export var parry_degraded_window: float = 0.1  # 降级后的弹反窗口（秒）
@export var parry_window_bonus: float = 0.0     # 装备提供的弹反窗口加成（加法）
@export var parry_normal_resource_gain: Dictionary = {}  # 普通弹反资源获取
@export var parry_perfect_resource_gain: Dictionary = {}  # 完美弹反资源获取

## 获取当前弹反窗口（基于是否连续完美弹反 + 装备加成）
func get_parry_window(is_consecutive_perfect: bool) -> float:
	var base = parry_base_window if is_consecutive_perfect else parry_degraded_window
	return base + parry_window_bonus

## 获取弹反资源获取配置
func get_parry_resource_gain(is_perfect: bool) -> Dictionary:
	if is_perfect:
		return parry_perfect_resource_gain
	return parry_normal_resource_gain

# ═══════════════════════════════════════════════════════════════════
# 装备数值系统（未来扩展用）
# ═══════════════════════════════════════════════════════════════════

@export_group("装备加成", "equip_")
@export var equip_damage_multiplier: float = 0.0  # 装备伤害加成%（加法公式用）
@export var equip_defense_multiplier: float = 0.0  # 装备防御加成%
@export var equip_parry_window_bonus: float = 0.0  # 装备弹反窗口加成

## 计算最终伤害（乘法公式）
## final = base * (1 + equip%) * (1 + weapon%)
func calc_damage(base_damage: float, weapon_multiplier: float = 1.0) -> float:
	return base_damage * (1.0 + equip_damage_multiplier) * weapon_multiplier

## 计算最终防御（乘法公式）
func calc_defense(base_defense: float) -> float:
	return base_defense * (1.0 + equip_defense_multiplier)

# ═══════════════════════════════════════════════════════════════════
# 指令配置
# ═══════════════════════════════════════════════════════════════════

@export var available_commands: Array[CharacterCommand]

# 指令属性覆盖（让同一指令在不同角色有不同效果）
@export var command_overrides: Array[CharacterCommandOverride]

# 资源系统（用于剑盾势等资源）
@export var resources: Array[CharacterResource]

# 技能系统
@export var skills: Array[Skill]

# ═══════════════════════════════════════════════════════════════════
# 运行时状态
# ═══════════════════════════════════════════════════════════════════

var is_alive: bool = true
var can_move: bool = true

# ═══════════════════════════════════════════════════════════════════
# 辅助函数
# ═══════════════════════════════════════════════════════════════════

## 获取指定伤害类型的属性
func get_damage_info(type: DamageType) -> Dictionary:
	match type:
		DamageType.SLASHING:
			return {"percent": slash_damage_percent, "defense": slash_defense_percent, "trigger": slash_trigger_rate}
		DamageType.BLUNT:
			return {"percent": blunt_damage_percent, "defense": blunt_defense_percent, "trigger": blunt_trigger_rate}
		DamageType.FIRE:
			return {"percent": fire_damage_percent, "defense": fire_defense_percent, "trigger": fire_trigger_rate}
		DamageType.ICE:
			return {"percent": ice_damage_percent, "defense": ice_defense_percent, "trigger": ice_trigger_rate}
		DamageType.LIGHTNING:
			return {"percent": lightning_damage_percent, "defense": lightning_defense_percent, "trigger": lightning_trigger_rate}
		DamageType.POISON:
			return {"percent": poison_damage_percent, "defense": poison_defense_percent, "trigger": poison_trigger_rate}
		DamageType.HOLY:
			return {"percent": holy_damage_percent, "defense": holy_defense_percent, "trigger": holy_trigger_rate}
	return {"percent": 100.0, "defense": 0.0, "trigger": 0.0}

## 获取最终必杀能量上限（考虑冷却缩减）
func get_ult_energy_required() -> int:
	return int(ult_energy_max * (1.0 - cooldown_reduction))

## 增加必杀能量
func add_ult_energy(amount: int) -> void:
	current_ult_energy = min(get_ult_energy_required(), current_ult_energy + amount)

## 检查是否可以释放必杀
func can_use_ult() -> bool:
	return current_ult_energy >= get_ult_energy_required()

## 使用必杀
func use_ult() -> void:
	current_ult_energy = 0

## 受到伤害
func take_damage(damage: int) -> void:
	# 先检查闪避
	if dodge_rate > 0.0 and randf() < dodge_rate:
		print("💨 闪避成功！")
		return

	var actual_damage = max(1, damage)
	current_health -= actual_damage
	if current_health <= 0:
		current_health = 0
		is_alive = false
		print("💀 %s 已阵亡" % character_name)

## 恢复生命
func heal(amount: int) -> void:
	current_health = min(max_health, current_health + amount)

## 吸血恢复
func apply_lifesteal(amount: int) -> void:
	if lifesteal_percent > 0:
		var heal_amount = int(amount * lifesteal_percent)
		heal(heal_amount)

## 检查是否有指定指令（基于 input_string）
func has_command(input_string: String) -> bool:
	for cmd in available_commands:
		if cmd and cmd.input_string == input_string:
			return true
	return false

## 获取指定指令的配置（应用角色覆盖，基于 input_string）
func get_command(input_string: String) -> CharacterCommand:
	for cmd in available_commands:
		if cmd and cmd.input_string == input_string:
			# 应用角色特定的覆盖
			return _apply_override(cmd)
	return null

## 获取所有指令的 input_string 列表
func get_all_input_strings() -> Array[String]:
	var result: Array[String] = []
	for cmd in available_commands:
		if cmd and cmd.input_string != "":
			result.append(cmd.input_string)
	return result

## 应用指令覆盖（基于 input_string）
func _apply_override(cmd: CharacterCommand) -> CharacterCommand:
	for override in command_overrides:
		if override.input_string == cmd.input_string:
			# 复制指令并应用覆盖
			var overridden = cmd.duplicate()
			if override.power_multiplier != 1.0:
				overridden.power_multiplier = override.power_multiplier
			if override.defense_multiplier != 1.0:
				overridden.defense_multiplier = override.defense_multiplier
			if override.cooldown_multiplier != 1.0:
				overridden.cooldown_multiplier = override.cooldown_multiplier
			if override.animation_name != "":
				overridden.animation_name = override.animation_name
			return overridden
	return cmd

## 重置状态
func reset() -> void:
	current_health = max_health
	current_ult_energy = 0
	is_alive = true
	can_move = true
	# 重置所有资源
	for res in resources:
		if res:
			res.reset()

## 获取指定资源
func get_resource(resource_id: String) -> CharacterResource:
	for res in resources:
		if res and res.resource_id == resource_id:
			return res
	return null

## 根据技能ID获取技能
func get_skill(skill_id: String) -> Skill:
	for skill in skills:
		if skill and skill.skill_id == skill_id:
			return skill
	return null

## 根据按键和拍数获取可用的技能
func get_skill_by_input(drum: RhythmDetector.DrumType, held_beats: int) -> Skill:
	for skill in skills:
		if skill and skill.required_drum == drum and skill.required_beats == held_beats:
			if skill.can_use():
				return skill
	return null
