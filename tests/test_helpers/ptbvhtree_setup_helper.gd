class_name _PTBVHTreeSetupHelper
extends GutTest

## Simple class to hold setup code for different PTBVHTree test scripts

var SceneA := preload("res://tests/test_scenes/test_scene_bvh_a.tscn")
var scene_a : PTScene
var bvh_a : PTBVHTree
var bvh_a2 : PTBVHTree
var tester_a : PTBVHTreeHelper


func before_all() -> void:
	bvh_a = create_test_bvh_a1()
	bvh_a2 = create_test_bvh_a2()

	tester_a = PTBVHTreeHelper.new(bvh_a)


func after_all() -> void:
	scene_a.free()


## Create a valid small tree
func create_test_bvh_a1() -> PTBVHTree:
	if not scene_a:
		scene_a = SceneA.instantiate()
		add_child(scene_a)

	var bvh := PTBVHTree.new(2)
	bvh.set_scene_as_owner(scene_a)

	var node_l := PTBVHTree.BVHNode.new(bvh.root_node, bvh)
	var node_r := PTBVHTree.BVHNode.new(bvh.root_node, bvh)
	var node_rl := PTBVHTree.BVHNode.new(node_r, bvh)
	var node_rr := PTBVHTree.BVHNode.new(node_r, bvh)

	node_l.is_leaf = true
	node_r.is_inner = true
	node_rl.is_leaf = true
	node_rr.is_leaf = true

	node_l.add_objects([scene_a.scene_objects.spheres[0],
			scene_a.scene_objects.triangles[0], scene_a.scene_objects.spheres[1]], true)
	node_rl.add_objects([scene_a.scene_objects.spheres[2],
			scene_a.scene_objects.spheres[3]], true)
	node_rr.add_object(scene_a.scene_objects.triangles[1], true)

	node_r.add_children([node_rl, node_rr], true)
	bvh.root_node.add_children([node_l, node_r], true)

	# Indices
	bvh.leaf_nodes = [node_l, node_rl, node_rr]
	bvh.bvh_list = [bvh.root_node, node_l, node_r, node_rl, node_rr]
	var i := 0
	for node in bvh.bvh_list:
		bvh._node_to_index[node] = i
		if node.is_leaf:
			bvh._node_to_object_id_index[node] = bvh.object_ids.size()
			for object in node.object_list:
				bvh.object_to_leaf[object] = node
				bvh.object_ids.append(object.get_object_id())

		i += 1

	bvh.inner_count = 2
	bvh.leaf_count = 3
	bvh.object_count = 6
	bvh.mesh_object_count = 0

	return bvh


## Create a sligthly smaller valid tree
func create_test_bvh_a2() -> PTBVHTree:
	if not scene_a:
		scene_a = SceneA.instantiate()
		add_child(scene_a)

	var bvh := PTBVHTree.new(2)
	bvh.set_scene_as_owner(scene_a)

	var node_l := PTBVHTree.BVHNode.new(bvh.root_node, bvh)
	var node_r := PTBVHTree.BVHNode.new(bvh.root_node, bvh)

	node_l.is_leaf = true
	node_r.is_leaf = true

	node_l.add_objects([scene_a.scene_objects.spheres[0],
			scene_a.scene_objects.triangles[0], scene_a.scene_objects.spheres[1]], true)
	node_r.add_objects([scene_a.scene_objects.spheres[2],
			scene_a.scene_objects.spheres[3],scene_a.scene_objects.triangles[1]], true)

	bvh.root_node.add_children([node_l, node_r], true)

	# Indices
	bvh.leaf_nodes = [node_l, node_r]
	bvh.bvh_list = [bvh.root_node, node_l, node_r]
	var i := 0
	for node in bvh.bvh_list:
		bvh._node_to_index[node] = i
		if node.is_leaf:
			bvh._node_to_object_id_index[node] = bvh.object_ids.size()
			for object in node.object_list:
				bvh.object_to_leaf[object] = node
				bvh.object_ids.append(object.get_object_id())

		i += 1

	bvh.inner_count = 1
	bvh.leaf_count = 2
	bvh.object_count = 6
	bvh.mesh_object_count = 0

	return bvh


# TODO 2: Create two more scenes and manually index them
func create_test_bvh_b() -> PTBVHTree:
	pass
	return


func create_test_bvh_c() -> PTBVHTree:
	pass
	return
