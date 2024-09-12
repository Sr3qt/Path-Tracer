class_name PTTestHelperBVH
extends RefCounted

## Helper functions to verify bvh integrity when testing bvh modification and creation

var bvh : PTBVHTree

## Array of if checks between bvh and another bvh.
## Check is_similar_to for what the corresponding index in
## is_similar_diff is checking for.
var is_similar_diff : Array[bool]
## Array of if checks between bvh and another bvh.
## Check is_same_as for what the corresponding index in
## is_same_diff is checking for.
var is_same_diff : Array[bool]

func _init(p_bvh : PTBVHTree) -> void:
	bvh = p_bvh

	is_similar_diff.resize(7)
	is_similar_diff.fill(false)
	is_same_diff.resize(100)
	is_same_diff.fill(false)


#region memory_tests

## Verifies that all nodes in a tree adhere to the memory layout requirements.
func is_memory_contiguous() -> bool:
	if not is_node_contiguous(bvh.root_node):
		return false
	return _recursive_is_contiguous(bvh.root_node)


func _recursive_is_contiguous(node : PTBVHTree.BVHNode) -> bool:
	for child in node.children:
		if not is_node_contiguous(child):
			return false
		if child.is_inner:
			if not _recursive_is_contiguous(child):
				return false
	return true


## Verifys that the children/objects of a node adheres to the memory layout requirements.
func is_node_contiguous(node : PTBVHTree.BVHNode) -> bool:
	if node.is_leaf:
		return _is_leaf_node_contiguous(node)

	return _is_inner_node_contiguous(node)


## Requirements:
## 	- First child node has the lowest bvh_list index
##	- The other children need to contiguous indices but not neccessarily in order
func _is_inner_node_contiguous(node : PTBVHTree.BVHNode) -> bool:
	var start_index : int = bvh.get_node_index(node.children[0])
	var relevant_indices : Array[PTBVHTree.BVHNode] = bvh.bvh_list.slice(
			start_index, start_index + node.size())
	for child in node.children:
		if child not in relevant_indices:
			return false

	return true


## Requirements:
## 	- First object has the lowest object_ids index
##	- The other objects need to be contiguous indices but not neccessarily in order
func _is_leaf_node_contiguous(node : PTBVHTree.BVHNode) -> bool:
	var start_index : int = bvh.object_ids.find(node.object_list[0].get_object_id())
	var relevant_indices : PackedInt32Array = bvh.object_ids.slice(
			start_index, start_index + node.size())
	for object in node.object_list:
		if object.get_object_id() not in relevant_indices:
			return false

	return true

#endregion


func is_tree_valid() -> bool:
	# TODO 1: Make whole tree verification function and test
	return true


## Checks if bvh have the same objects, indices and tree structure.
## Objects have to be the same instance, but nodes can be different instances.
## Does not compare bvh owners or owner specific values, like object_ids.
func is_same_as(other : PTBVHTree) -> bool:
	is_same_diff.fill(true)

	# TODO 2: Finnish this function

	var object_count := bvh.object_count == other.object_count
	var mesh_object_count := bvh.mesh_object_count == other.mesh_object_count
	var leaf_count := bvh.leaf_count == other.leaf_count
	var inner_count := bvh.inner_count == other.inner_count
	var mesh_index_size := (
			bvh._mesh_to_mesh_socket.size() == other._mesh_to_mesh_socket.size())
	var mesh_index_keys := (
			other._mesh_to_mesh_socket.has_all(bvh._mesh_to_mesh_socket.keys()))
	var object_leaf_size := bvh.object_to_leaf.size() == other.object_to_leaf.size()
	var object_leaf_keys := other.object_to_leaf.has_all(bvh.object_to_leaf.keys())
	var root_node_aabb := bvh.root_node.aabb.is_equal_approx(other.root_node.aabb)
	var type := bvh.type == other.type
	var bvh_list_size := bvh.bvh_list.size() == other.bvh_list.size()

	is_same_diff[0] = object_count
	is_same_diff[1] = mesh_object_count
	is_same_diff[2] = leaf_count
	is_same_diff[3] = inner_count
	is_same_diff[4] = root_node_aabb
	is_same_diff[5] = mesh_index_size
	is_same_diff[6] = mesh_index_keys
	is_same_diff[7] = object_leaf_size
	is_same_diff[8] = object_leaf_keys
	is_same_diff[9] = type
	is_same_diff[10] = bvh_list_size

	return is_same_diff.all(func(a : bool) -> bool: return a)


## Checks if bvh has same objects and that indices have similar contours.
## However it does not check for the same tree structure.
## Basically it will check if two bvhs were created from the same PTObjectContainer.
func is_similar_to(other : PTBVHTree) -> bool:
	is_similar_diff.fill(true)

	var object_count := bvh.object_count == other.object_count
	var mesh_object_count := bvh.mesh_object_count == other.mesh_object_count
	# SHOuld this be included?
	# var object_id_index_size := (
	# 		bvh._node_to_object_id_index.size() ==
	# 		other._node_to_object_id_index.size())
	var mesh_index_size := (
			bvh._mesh_to_mesh_socket.size() == other._mesh_to_mesh_socket.size())
	var mesh_index_keys := (
			other._mesh_to_mesh_socket.has_all(bvh._mesh_to_mesh_socket.keys()))
	var object_leaf_size := bvh.object_to_leaf.size() == other.object_to_leaf.size()
	var object_leaf_keys := other.object_to_leaf.has_all(bvh.object_to_leaf.keys())
	var root_node_aabb := bvh.root_node.aabb.is_equal_approx(other.root_node.aabb)

	is_similar_diff[0] = object_count
	is_similar_diff[1] = mesh_object_count
	is_similar_diff[2] = root_node_aabb
	is_similar_diff[3] = mesh_index_size
	is_similar_diff[4] = mesh_index_keys
	is_similar_diff[5] = object_leaf_size
	is_similar_diff[6] = object_leaf_keys
	# is_similar_diff[7] = object_id_index_size

	return is_similar_diff.all(func(a : bool) -> bool: return a)

