class_name DamageStage
extends Resource

## 单段伤害配置

@export var damage_multiplier: float = 1.0
@export var damage_type: int = 0  # DamageType enum
@export var trigger_rate: float = 0.05  # 触发几率（受装备影响）
@export var timing_percent: float = 0.0  # 0%=动作开始, 100%=动作结束

# 伤害数量（如箭支数）
@export var damage_count: int = 1

# 动画触发（可选）
@export var animation_event: String = ""

# ═══════════════════════════════════════════════════════════════════
# 触发条件
# ═══════════════════════════════════════════════════════════════════

# 弹反相关条件
@export var requires_perfect_parry: bool = false  # 需要完美弹反
@export var requires_normal_parry: bool = false   # 需要普通弹反
@export var requires_no_parry: bool = false       # 需要未弹反

# 目标距离条件
@export var requires_target_in_range: bool = false     # 需要目标在范围内
@export var requires_target_out_of_range: bool = false # 需要目标在范围外

# 资源条件
@export var requires_resource_id: String = ""      # 需要的资源ID
@export var requires_resource_min: int = 0          # 资源最少数量

func _init(
	p_multiplier: float = 1.0,
	p_damage_type: int = 0,
	p_trigger_rate: float = 1.0,
	p_timing: float = 0.0,
	p_count: int = 1
) -> void:
	damage_multiplier = p_multiplier
	damage_type = p_damage_type
	trigger_rate = p_trigger_rate
	timing_percent = p_timing
	damage_count = p_count

## 检查所有条件是否满足
func check_conditions(context: Dictionary) -> bool:
	# 弹反条件
	if requires_perfect_parry and context.get("parry_result") != "perfect":
		return false
	if requires_normal_parry and context.get("parry_result") != "normal":
		return false
	if requires_no_parry and context.get("parry_result") == "perfect":
		return false  # no_parry 意味着不是完美

	# 目标距离条件
	if requires_target_in_range and not context.get("target_in_range", false):
		return false
	if requires_target_out_of_range and context.get("target_in_range", false):
		return false

	# 资源条件
	if requires_resource_id != "":
		var resource = context.get("resource_" + requires_resource_id, null)
		if resource == null:
			return false
		if resource.get_total() < requires_resource_min:
			return false

	return true
