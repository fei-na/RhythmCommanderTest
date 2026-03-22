## 角色指令属性覆盖 - 让同一指令在不同角色有不同效果
class_name CharacterCommandOverride
extends Resource

# 要覆盖的指令（基于 input_string 匹配）
@export var input_string: String = ""

# 覆盖属性（只有填写的才会覆盖）
@export var power_multiplier: float = 1.0           # 伤害倍率覆盖
@export var defense_multiplier: float = 1.0         # 防御减伤倍率覆盖
@export var cooldown_multiplier: float = 1.0        # 冷却缩减覆盖
@export var animation_name: String = ""              # 动画名称覆盖
