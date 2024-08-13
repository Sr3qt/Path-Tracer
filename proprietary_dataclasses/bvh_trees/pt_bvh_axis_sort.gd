@tool
class_name PTBVHAxisSort
extends PTBVHTree

## Basic implementation of BVHTree

var _index := 0 # Used to keep track of index when creating bvh_list
var _axis : int = 0
var _axis_sorts : Array[Callable] = []
const MAX_DEPTH_LIMIT = 64


static func x_axis_sorted(objects : PTObjectContainer, _order : int) -> PTBVHAxisSort:
	var temp := PTBVHAxisSort.new(_order)
	temp.create_bvh(objects, BVHType.X_SORTED)
	return temp


static func y_axis_sorted(objects : PTObjectContainer, _order : int) -> PTBVHAxisSort:
	var temp := PTBVHAxisSort.new(_order)
	temp.create_bvh(objects, BVHType.Y_SORTED)
	return temp


static func z_axis_sorted(objects : PTObjectContainer, _order : int) -> PTBVHAxisSort:
	var temp := PTBVHAxisSort.new(_order)
	temp.create_bvh(objects, BVHType.Z_SORTED)
	return temp


static func longest_axis_sort(objects : PTObjectContainer, _order : int) -> PTBVHAxisSort:
	var temp := PTBVHAxisSort.new(_order)
	temp.create_bvh(objects, BVHType.XYZ_SORTED)
	return temp


func create_bvh(objects : PTObjectContainer, f_type := BVHType.XYZ_SORTED) -> void:
	var start_time := Time.get_ticks_usec()

	assert(f_type in [BVHType.XYZ_SORTED, BVHType.X_SORTED, BVHType.Y_SORTED, BVHType.Z_SORTED],
			"PT: PTBVHAxisSort cannot create bvh of type: " + str(BVHType.find_key(f_type)))

	type = f_type

	var flat_object_list : Array[PTObject] = []

	for object_type : PTObject.ObjectType in PTObject.ObjectType.values(): # UNSTATIC
		if object_type in objects_to_exclude:
			continue
		flat_object_list.append_array(objects.get_object_array(object_type))

	object_count = flat_object_list.size()

	for i in range(3):
		_axis_sorts.append(
				func(a : PTObject, b : PTObject) -> bool:
					return a.get_bvh_aabb().get_center()[i] > b.get_bvh_aabb().get_center()[i])

	# Sort according to given axis
	match type:
		BVHType.X_SORTED:
			_axis = 0
		BVHType.Y_SORTED:
			_axis = 1
		BVHType.Z_SORTED:
			_axis = 2

	# MAKE XYZ
	if type != BVHType.XYZ_SORTED:
		flat_object_list.sort_custom(_axis_sorts[_axis])

	# Creates tree recursively
	root_node.add_children(_recursive_split(flat_object_list, root_node))

	# Indexes tree recursively
	bvh_list.resize(size())
	bvh_list[0] = root_node
	_node_to_index[root_node] = 0
	_index = 1
	_index_node2(root_node)

	if objects.meshes.size() > 0:
		for _mesh in objects.meshes:
			if _mesh.bvh:
				merge_with(_mesh.bvh)

	index_tree()

	creation_time = Time.get_ticks_usec() - start_time

	if PTRendererAuto.is_debug:
		print(("Finished creating %s BVH tree with %s inner nodes, " +
				"%s leaf nodes and %s objects in %s ms.") % [
				BVHType.find_key(type), inner_count, leaf_count, object_count, creation_time / 1000.])


func _recursive_split(object_list : Array[PTObject], parent : BVHNode) -> Array[BVHNode]:
	# SPlitting objects by the middle of the list is very bad i just forgot to improve it

	if type == BVHType.XYZ_SORTED:
		var longest_axis := find_longest_axis(object_list)
		object_list.sort_custom(_axis_sorts[longest_axis])

	# Will distriute objects evenly with first indices having slightly more
	@warning_ignore("integer_division")
	var even_division : int = object_list.size() / order
	var leftover : int = object_list.size() % order

	var new_children : Array[BVHNode] = []
	var start : int = 0
	var end : int = 0
	for i in range(order):
		start = end
		end += even_division + int(i < leftover)
		if not (start - end):
			break # Break if no nodes are left
		var new_node := BVHNode.new(parent, self)
		# NOTE: slice returns a new Array and loses the previous arrays type
		var split_objects := object_list.slice(start, end)

		# If all objects can fit in a single node, do it
		if split_objects.size() <= order:
			new_children.append(_set_leaf(new_node, split_objects))
			continue

		new_node.add_children(_recursive_split(split_objects, new_node))
		inner_count += 1
		new_children.append(new_node)

	return new_children


func _recursive_split2(object_list : Array[PTObject], parent : BVHNode, depth : int = 0) -> Array[BVHNode]:
	# SPlitting objects by the middle of the list is very bad i just forgot to improve it
	# TODO Add support for all orders

	var left : Array[PTObject] = []
	var right : Array[PTObject] = []

	var new_children : Array[BVHNode] = []
	var new_node_right := BVHNode.new(parent, self)
	var new_node_left := BVHNode.new(parent, self)

	if depth > MAX_DEPTH_LIMIT:
		#Will distriute objects evenly with first indices having slightly more
		@warning_ignore("integer_division")
		var even_division : int = object_list.size() / order
		var leftover : int = object_list.size() % order

		var start : int = 0
		var end : int = 0
		for i in range(order):
			start = end
			end += even_division + int(i < leftover)
			if not (start - end):
				break # Break if no nodes are left
			var new_node := BVHNode.new(parent, self)
			# NOTE: slice returns a new Array and loses the previous arrays type
			var split_objects := object_list.slice(start, end)

			# If all objects can fit in a single node, do it
			# if split_objects.size() <= order:
			_set_leaf(new_node, split_objects)
			if new_node.size() > 0:
				new_children.append(new_node)
			# else:

		return new_children

	var temp := AABB()

	for object in object_list:
		temp = temp.merge(object.get_bvh_aabb())
		# temp = temp.expand(object.get_bvh_aabb().get_center())

	if type == BVHType.XYZ_SORTED:
		_axis = temp.get_longest_axis_index()
	# 	var longest_axis := temp.get_longest_axis_index()
	# 	object_list.sort_custom(_axis_sorts[longest_axis])


	for object in object_list:
		if object.get_bvh_aabb().get_center()[_axis] > temp.get_center()[_axis]:
			left.append(object)
		else:
			right.append(object)

	if right.size() <= order:
		new_children.append(_set_leaf(new_node_right, right))
	else:
		new_node_right.add_children(_recursive_split2(right, new_node_right, depth + 1))
		inner_count += 1


	if left.size() <= order:
		new_children.append(_set_leaf(new_node_left, left))
	else:
		new_node_left.add_children(_recursive_split2(left, new_node_left, depth + 1))
		inner_count += 1

	return [new_node_right, new_node_left]

	# Will distriute objects evenly with first indices having slightly more
	# @warning_ignore("integer_division")
	# var even_division : int = object_list.size() / order
	# var leftover : int = object_list.size() % order

	# var start : int = 0
	# var end : int = 0
	# for i in range(order):
	# 	start = end
	# 	end += even_division + int(i < leftover)
	# 	if not (start - end):
	# 		break # Break if no nodes are left
	# 	var new_node := BVHNode.new(parent, self)
	# 	# NOTE: slice returns a new Array and loses the previous arrays type
	# 	var split_objects := object_list.slice(start, end)

	# 	# If all objects can fit in a single node, do it
	# 	if split_objects.size() <= order:
	# 		new_children.append(_set_leaf(new_node, split_objects))
	# 		continue

	# 	new_node.add_children(_recursive_split(split_objects, new_node))
	# 	inner_count += 1
	# 	new_children.append(new_node)

	# return new_children


func _set_leaf(node : BVHNode, object_list : Array[PTObject]) -> BVHNode:
	node.is_leaf = true
	node.object_list = object_list
	leaf_nodes.append(node)

	for object in object_list:
		object_to_leaf[object] = node # UNSTATIC

	node.set_aabb()
	leaf_count += 1
	return node


func _index_node2(parent : BVHNode) -> void:
	for child in parent.children:
		bvh_list[_index] = child
		_node_to_index[child] = _index # UNSTATIC
		_index += 1

	for child in parent.children:
		if child.is_inner:
			_index_node2(child)


func find_longest_axis(object_list : Array[PTObject]) -> int:
	var temp := AABB()

	for object in object_list:
		temp = temp.merge(object.get_bvh_aabb())

	return temp.get_longest_axis_index()
