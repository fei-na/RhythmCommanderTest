## 指令序列阶段配置 - 用于连击/连续攻击的不同阶段
class_name CommandSequenceStage
extends Resource

# 阶段名称（如 "第一击"、"强攻击"、"收尾"）
@export var stage_name: String = ""

# 在序列中的位置（0 = 第一下，1 = 第二下...）
@export var position: int = 0

# 伤害倍率
@export var power_multiplier: float = 1.0

# 动画名称
@export var animation_name: String = ""

# 音效
@export var sound_effect: String = ""

# 击退距离
@export var knockback_distance: float = 0.0

# 特效
@export var effect_scene: PackedScene
