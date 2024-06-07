@tool
class_name PTBVHAxisSort
extends PTBVHTree

## Basic implementation of BVHTree

var _index := 0 # Used to keep track of index when creating bvh_list


static func x_axis_sorted(objects : PTObjectContainer, _order : int) -> PTBVHAxisSort:
	var temp := PTBVHAxisSort.new(_order)
	temp.create_bvh(objects)
	temp.type = BVHType.X_SORTED
	return temp


static func y_axis_sorted(objects : PTObjectContainer, _order : int) -> PTBVHAxisSort:
	var temp := PTBVHAxisSort.new(_order)
	temp.create_bvh(objects, "y")
	temp.type = BVHType.Y_SORTED
	return temp


static func z_axis_sorted(objects : PTObjectContainer, _order : int) -> PTBVHAxisSort:
	var temp := PTBVHAxisSort.new(_order)
	temp.create_bvh(objects, "z")
	temp.type = BVHType.Z_SORTED
	return temp


func create_bvh(objects : PTObjectContainer, axis := "x") -> void:
	var start_time := Time.get_ticks_usec()

	object_container = objects
	var flat_object_list : Array[PTObject] = []

	for object_type : PTObject.ObjectType in PTObject.ObjectType.values(): # UNSTATIC
		if object_type in objects_to_exclude:
			continue
		flat_object_list.append_array(objects.get_object_array(object_type))

	object_count = flat_object_list.size()

	# Sort according to given axis
	var _axis : int = 0
	match axis:
		"y":
			_axis = 1
		"z":
			_axis = 2
	var axis_sort := func(a : PTObject, b : PTObject) -> bool:
		return a.get_global_aabb().position[_axis] > b.get_global_aabb().end[_axis]

	flat_object_list.sort_custom(axis_sort)

	# Creates tree recursively
	root_node.add_children(_recursive_split(flat_object_list, root_node))

	# Indexes tree recursively
	bvh_list.resize(size())
	_index_node(root_node)

	creation_time = Time.get_ticks_usec() - start_time

	if PTRendererAuto.is_debug:
		print(("Finished creating %s-axis sorted BVH tree with %s inner nodes, " +
				"%s leaf nodes and %s objects in %s ms.") % [
				axis, inner_count, leaf_count, object_count, creation_time / 1000.])


func _recursive_split(object_list : Array[PTObject], parent : BVHNode) -> Array[BVHNode]:
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


func _set_leaf(node : BVHNode, object_list : Array[PTObject]) -> BVHNode:
	node.is_leaf = true
	node.object_list = object_list
	leaf_nodes.append(node)

	for object in object_list:
		object_to_leaf[object] = node # UNSTATIC

	node.set_aabb()
	leaf_count += 1
	return node


func _index_node(parent : BVHNode) -> void:
	bvh_list[_index] = parent
	_node_to_index[parent] = _index # UNSTATIC

	_index += 1
	for child in parent.children:
		if child.is_leaf:
			bvh_list[_index] = child
			_node_to_index[child] = _index # UNSTATIC
			_index += 1
			continue

		_index_node(child)
