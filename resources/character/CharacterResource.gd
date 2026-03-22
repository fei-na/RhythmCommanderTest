## 角色资源系统 - 用于剑盾势等资源管理
class_name CharacterResource
extends Resource

# 资源类型枚举
enum ResourceType {
	SWORD,   # 剑势（红色）
	SHIELD,  # 盾势（蓝色）
}

# 资源名称
@export var name: String = ""

# 资源ID
@export var resource_id: String = ""

# 子类型定义（如 ["sword", "shield"] 或 ["arrow"]）
@export var sub_types: Array[String] = []

# 当前各类型数量（兼容旧版 sword_count/shield_count）
@export var sword_count: int = 0  # 剑势数量
@export var shield_count: int = 0  # 盾势数量

# 通用的子类型数量存储（如果定义了 sub_types 则优先使用）
var sub_type_counts: Dictionary = {}

# 最大总数（剑+盾不能超过此值）
@export var max_total: int = 4

# 最小数量
@export var min_amount: int = 0

# 是否可以溢出（超过上限）
@export var can_overflow: bool = false

## 获取总资源数
func get_total() -> int:
	if sub_types.size() > 0:
		var total = 0
		for sub_type in sub_types:
			total += sub_type_counts.get(sub_type, 0)
		return total
	return sword_count + shield_count

## 检查是否有足够资源
func has(amount: int) -> bool:
	return get_total() >= amount

## 增加资源（指定类型）
func add_resource(type: ResourceType, amount: int = 1) -> int:
	var old = get_total()
	if can_overflow:
		# 可以溢出，优先填满空位
		var space = max_total - get_total()
		var to_add = min(amount, space)
		if type == ResourceType.SWORD:
			sword_count += to_add
		else:
			shield_count += to_add
	else:
		# 不可溢出，最多加到max_total
		if type == ResourceType.SWORD:
			sword_count = clampi(sword_count + amount, min_amount, max_total - shield_count)
		else:
			shield_count = clampi(shield_count + amount, min_amount, max_total - sword_count)
	return get_total() - old

## 添加剑资源
func add_sword(amount: int = 1) -> int:
	return add_resource(ResourceType.SWORD, amount)

## 添加盾资源
func add_shield(amount: int = 1) -> int:
	return add_resource(ResourceType.SHIELD, amount)

## 检查是否有足够剑资源
func has_sword(amount: int) -> bool:
	return sword_count >= amount

## 检查是否有足够盾资源
func has_shield(amount: int) -> bool:
	return shield_count >= amount

## 添加通用子类型资源
func add_sub_type(sub_type: String, amount: int = 1) -> int:
	var old = get_total()
	if sub_types.has(sub_type):
		var current = sub_type_counts.get(sub_type, 0)
		var new_val = current + amount
		if not can_overflow:
			new_val = clampi(new_val, min_amount, max_total)
		sub_type_counts[sub_type] = new_val
	return get_total() - old

## 检查是否有足够子类型资源
func has_sub_type(sub_type: String, amount: int) -> bool:
	if sub_types.has(sub_type):
		return sub_type_counts.get(sub_type, 0) >= amount
	return false

## 获取子类型数量
func get_sub_type_count(sub_type: String) -> int:
	return sub_type_counts.get(sub_type, 0)

## 减少资源（优先减少多的类型）
func remove(amount: int) -> int:
	var old = get_total()
	var remaining = amount

	# 如果使用子类型系统，优先减少数量多的子类型
	if sub_types.size() > 0:
		# 收集各子类型数量并排序
		var type_amounts: Array = []
		for sub_type in sub_types:
			type_amounts.append({"type": sub_type, "count": sub_type_counts.get(sub_type, 0)})
		type_amounts.sort_custom(func(a, b): return a["count"] > b["count"])

		for item in type_amounts:
			if remaining <= 0:
				break
			var remove_amt = min(item["count"], remaining)
			sub_type_counts[item["type"]] = item["count"] - remove_amt
			remaining -= remove_amt
	else:
		# 旧版 sword/shield 系统
		if sword_count >= shield_count:
			var remove_from_sword = min(sword_count, remaining)
			sword_count -= remove_from_sword
			remaining -= remove_from_sword
			if remaining > 0:
				var remove_from_shield = min(shield_count, remaining)
				shield_count -= remove_from_shield
				remaining -= remove_from_shield
		else:
			var remove_from_shield = min(shield_count, remaining)
			shield_count -= remove_from_shield
			remaining -= remove_from_shield
			if remaining > 0:
				var remove_from_sword = min(sword_count, remaining)
				sword_count -= remove_from_sword
				remaining -= remove_from_sword

	# 确保不低于最小值
	sword_count = clampi(sword_count, min_amount, max_total)
	shield_count = clampi(shield_count, min_amount, max_total)

	return old - get_total()

## 减少指定类型的资源
func remove_type(type: ResourceType, amount: int = 1) -> int:
	var old_total = get_total()
	if type == ResourceType.SWORD:
		sword_count = clampi(sword_count - amount, min_amount, max_total)
	else:
		shield_count = clampi(shield_count - amount, min_amount, max_total)
	return old_total - get_total()

## 获取某类型数量
func get_count(type: ResourceType) -> int:
	if type == ResourceType.SWORD:
		return sword_count
	return shield_count

## 重置
func reset() -> void:
	sword_count = 0
	shield_count = 0
	sub_type_counts.clear()
	# 初始化子类型计数为0
	for sub_type in sub_types:
		sub_type_counts[sub_type] = 0

## 设置值
func set_value(sword: int, shield: int) -> void:
	sword_count = clampi(sword, min_amount, max_total)
	shield_count = clampi(shield, min_amount, max_total - sword_count)

## 设置子类型值
func set_sub_type_value(sub_type: String, value: int) -> void:
	if sub_types.has(sub_type):
		sub_type_counts[sub_type] = clampi(value, min_amount, max_total)
