@tool
class_name PTBVHAxisSort
extends PTBVHTree

## Basic implementation of BVHTree

var _index := 0 # Used to keep track of index when creating bvh_list
var _axis : int = 0
var _axis_sorts : Array[Callable] = []
const MAX_DEPTH_LIMIT = 32

# Leave new method a little unfinished, work on SAH method next
# New method is slightly faster on dragon test, slower on import_test and spheres
const use_old_method = !true

## TODO sort_custom does not keep order. Try using stable sorting algorithm.


## TODO FIX This should not be neccessary but godot thinks that for some reason
## the inherited _init called on PTBVHAxisSort should need 2 arguments instead of one.
func _init(_order : int = 2) -> void:
	super._init(_order)


static func x_axis_sorted(objects : PTObjectContainer, _order : int) -> PTBVHAxisSort:
	var temp := PTBVHAxisSort.new(_order)
	if use_old_method:
		temp.create_bvh_tree(objects, BVHType.X_SORTED)
	else:
		temp.create_bvh_node_list(objects, BVHType.X_SORTED)
	return temp


static func y_axis_sorted(objects : PTObjectContainer, _order : int) -> PTBVHAxisSort:
	var temp := PTBVHAxisSort.new(_order)
	if use_old_method:
		temp.create_bvh_tree(objects, BVHType.Y_SORTED)
	else:
		temp.create_bvh_node_list(objects, BVHType.Y_SORTED)
	return temp


static func z_axis_sorted(objects : PTObjectContainer, _order : int) -> PTBVHAxisSort:
	var temp := PTBVHAxisSort.new(_order)
	if use_old_method:
		temp.create_bvh_tree(objects, BVHType.Z_SORTED)
	else:
		temp.create_bvh_node_list(objects, BVHType.Z_SORTED)
	return temp


static func longest_axis_sort(objects : PTObjectContainer, _order : int) -> PTBVHAxisSort:
	var temp := PTBVHAxisSort.new(_order)
	if use_old_method:
		temp.create_bvh_tree(objects, BVHType.XYZ_SORTED)
	else:
		temp.create_bvh_node_list(objects, BVHType.XYZ_SORTED)
	return temp


func create_disconnected_node_list(objects : PTObjectContainer) -> Array[BVHNode]:
	var flat_node_list : Array[BVHNode] = []

	# Wait to set indices until tree has been finalized
	for object_type : PTObject.ObjectType in PTObject.ObjectType.values(): # UNSTATIC
		if object_type in objects_to_exclude:
			continue
		for object : PTObject in objects.get_object_array(object_type):
			var new_node := BVHNode.new(null, self)
			new_node.is_leaf = true
			new_node.add_object(object, true)
			flat_node_list.append(new_node)

	for mesh in objects.meshes:
		var new_node := BVHNode.new(null, self)
		new_node.is_mesh_socket = true
		new_node.is_inner = true
		_mesh_to_mesh_socket[mesh] = new_node
		mesh.bvh.root_node.parent = new_node
		new_node.add_child(mesh.bvh.root_node, true)
		flat_node_list.append(new_node)

	return flat_node_list


func create_bvh_tree(objects : PTObjectContainer, f_type := BVHType.XYZ_SORTED) -> void:
	# benchmark before:
		# Spheres - 487 objects in 7.829 ms.
		# Import mesh - 3168 objects in 132.713 ms -- 3171 objects in 1.616 ms.
	var start_time := Time.get_ticks_usec()

	assert(not objects.is_empty(), "Cannot create bvh without objects or meshes")

	assert(f_type in [BVHType.XYZ_SORTED, BVHType.X_SORTED, BVHType.Y_SORTED, BVHType.Z_SORTED],
			"PT: PTBVHAxisSort cannot create bvh of type: " + str(BVHType.find_key(f_type)))

	assert(order >= 2, "BVH cannot be created with less than 2 in order.")

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

	if not flat_object_list.is_empty():
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
		root_node.add_children(_recursive_split(flat_object_list, root_node), true)

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



func create_bvh_node_list(objects : PTObjectContainer, f_type := BVHType.XYZ_SORTED) -> void:
	# benchmark before:
		# Spheres - 487 objects in 7.829 ms.
		# Import mesh - 3168 objects in 132.713 ms -- 3171 objects in 1.616 ms.

	var start_time := Time.get_ticks_usec()

	print("NEW METHOD")

	assert(not is_sub_tree(), "PT: Only merge a tree AFTER creating the sub tree.")

	assert(not objects.is_empty(), "Cannot create bvh without objects or meshes.")

	assert(f_type in [BVHType.XYZ_SORTED, BVHType.X_SORTED, BVHType.Y_SORTED, BVHType.Z_SORTED],
			"PT: PTBVHAxisSort cannot create bvh of type: " + str(BVHType.find_key(f_type)))

	assert(order >= 2, "BVH cannot be created with less than 2 in order.")

	type = f_type

	var node_list := create_disconnected_node_list(objects)

	for i in range(3):
		_axis_sorts.append(
				func(a : BVHNode, b : BVHNode) -> bool:
					return a.aabb.get_center()[i] > b.aabb.get_center()[i])

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
		node_list.sort_custom(_axis_sorts[_axis])

	# This is also set in _init
	bvh_list = [root_node]
	_node_to_index[root_node] = 0
	inner_count = 1

	# Creates tree recursively
	root_node.add_children(_recursive_split_nodes(node_list, root_node), true)

	## TODO index mesh_sockets
	# TODO Merge object ids
	for mesh in objects.meshes:
		var index_offset := bvh_list.size()

		object_to_leaf.merge(mesh.bvh.object_to_leaf)
		leaf_nodes.append_array(mesh.bvh.leaf_nodes)

		# Merge bvh list and index dict, and add offset to index dict
		bvh_list.append_array(mesh.bvh.bvh_list)
		_node_to_index.merge(mesh.bvh._node_to_index)
		for node in mesh.bvh.bvh_list:
			_node_to_index[node] += index_offset

		leaf_count += mesh.bvh.leaf_count
		inner_count += mesh.bvh.inner_count
		mesh_object_count += mesh.bvh.object_count

		mesh.bvh.parent_tree = self

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

		new_node.add_children(_recursive_split(split_objects, new_node), true)
		inner_count += 1
		new_children.append(new_node)

	return new_children

# TODO Make tree_pruner that finds and removes empty nodes and removes chains of one child (except mesh_socket ofc)

func _recursive_split_nodes(node_list : Array[BVHNode], parent : BVHNode, depth : int = 0) -> Array[BVHNode]:
	# SPlitting objects by the middle of the list is very bad i just forgot to improve it
	# TODO Maybe make node container object similar to object_container

	var new_nodes_children : Array[Array] = []
	var new_nodes : Array[BVHNode] = []

	var segment_count := order
	var node_list_aabb := get_array_aabb(node_list).abs().grow(0.000001)

	if type == BVHType.XYZ_SORTED:
		_axis = node_list_aabb.get_longest_axis_index()
		node_list.sort_custom(_axis_sorts[_axis])

	var mesh_count := 0
	for node in node_list:
		if node.is_mesh_socket:
			mesh_count += 1

	if depth >= MAX_DEPTH_LIMIT:
		if  mesh_count >= order:
			# TODO Make sure this terminates
			push_warning("PT: BVH node depth limit reached with %s unfitted meshes. \n" +
				"Will extend limit to fit remaining meshes." % [mesh_count])

		elif mesh_count > 0:
			# TODO Make sure this terminates
			segment_count = order - mesh_count

	if depth >= MAX_DEPTH_LIMIT + 5:
		assert(false, "too much depth")

	for i in range(segment_count):
		new_nodes_children.append([])

	var segment : float = (node_list_aabb.size / segment_count)[_axis]
	for node in node_list:
		var center := node.aabb.get_center()
		var index := floori((center - node_list_aabb.position)[_axis] / segment)
		assert(0 <= index and index < segment_count)
		new_nodes_children[index].append(node)

	# If too many objects have the similar enough positions on the sorted axis,
	# they will all be put into a single segment. This mostly happens on single axis
	# sorts, but can also happen if many objects are stacked on top of eachother.
	var empty_sections := 0
	var first_non_empty : Array
	for nodes : Array[BVHNode] in new_nodes_children:
		if nodes.is_empty():
			empty_sections += 1
		else:
			first_non_empty = nodes
	if empty_sections == segment_count - 1:
		@warning_ignore("integer_division")
		var left : Array = first_non_empty.slice(0, first_non_empty.size() / 2)
		@warning_ignore("integer_division")
		var right : Array = first_non_empty.slice(first_non_empty.size() / 2)

		new_nodes_children = [left, right]

	for _nodes : Array[BVHNode] in new_nodes_children:
		var nodes : Array[BVHNode] = []
		nodes.assign(_nodes)
		if nodes.is_empty():
			continue

		var new_node := BVHNode.new(parent, self)
		new_node.is_inner = true
		# Remaining nodes are still to many, split them into new nodes.
		if nodes.size() > order and depth < MAX_DEPTH_LIMIT:
			new_node.add_children(_recursive_split_nodes(nodes, new_node, depth + 1), true)
			new_nodes.append(new_node)
			continue

		# order or less objects, will fit in single leaf node
		if mesh_count == 0:
			new_node.is_leaf = true
			for leaf_node in nodes:
				assert(leaf_node.is_leaf)
				assert(leaf_node.size() == 1)
				new_node.add_object(leaf_node.object_list[0])
		# order or less objects or meshes, put objects in child leaf
		else:
			var new_leaf := BVHNode.new(new_node, self)
			new_leaf.is_leaf = true

			for node in nodes:
				if node.is_leaf:
					# Append object to child leaf
					assert(node.size() == 1)
					new_leaf.add_object(node.object_list[0])
				else:
					# Append mesh socket
					assert(node.is_mesh_socket)
					node.parent = new_node
					new_node.add_child(node)
					# Mesh tree will be fully indexed later
					index_node(node)

			# Children of new_node will be fully indexed
			if new_leaf.size() > 0:
				index_node(new_leaf, true)
				new_node.add_child(new_leaf)

		new_nodes.append(new_node)

	for node in new_nodes:
		index_node(node, true)

	return new_nodes


func _recursive_split2(object_list : Array[PTObject], parent : BVHNode, depth : int = 0) -> Array[BVHNode]:
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

	var temp := object_list[0].get_bvh_aabb()

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
		new_node_right.add_children(_recursive_split2(right, new_node_right, depth + 1), true)
		inner_count += 1


	if left.size() <= order:
		new_children.append(_set_leaf(new_node_left, left))
	else:
		new_node_left.add_children(_recursive_split2(left, new_node_left, depth + 1), true)
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
	var temp := object_list[0].get_bvh_aabb()

	for object in object_list:
		temp = temp.merge(object.get_bvh_aabb())

	return temp.get_longest_axis_index()


func create_array_aabb(object_list : Array[PTObject]) -> AABB:
	var temp := object_list[0].get_bvh_aabb()

	for object in object_list:
		temp = temp.merge(object.get_bvh_aabb())

	return temp


func get_array_aabb(nodes : Array[BVHNode]) -> AABB:
	var aabb := nodes[0].aabb
	for node in nodes:
		aabb = aabb.merge(node.aabb)
	return aabb

