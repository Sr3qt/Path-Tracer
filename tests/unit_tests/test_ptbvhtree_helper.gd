extends _PTBVHTreeSetupHelper

## Test script to test methods in PTBVHTreeHelper


func test_is_contigous_memory() -> void:
	assert_true(tester_a.is_memory_contiguous(), "Normal bvh")

	for node in bvh_a.bvh_list:
		assert_true(tester_a.is_node_contiguous(node), "Testing all individual nodes")

	bvh_a.root_node.children.reverse()
	assert_false(tester_a.is_node_contiguous(bvh_a.root_node), "Reversing root's children, node")
	assert_false(tester_a.is_memory_contiguous(), "Reversing root's children, tree")
	bvh_a.root_node.children.reverse()

	bvh_a.bvh_list[3].object_list.reverse()
	assert_false(tester_a.is_node_contiguous(bvh_a.bvh_list[3]), "Reversing leaf's objects, node")
	assert_false(tester_a.is_memory_contiguous(),  "Reversing leaf's objects, tree")
	bvh_a.bvh_list[3].object_list.reverse()

	var temp := bvh_a.bvh_list[1].object_list[1]
	bvh_a.bvh_list[1].object_list[1] = bvh_a.bvh_list[1].object_list[2]
	bvh_a.bvh_list[1].object_list[2] = temp

	assert_true(tester_a.is_node_contiguous(bvh_a.bvh_list[1]), "Swapping child order, safe")
	bvh_a.bvh_list[1].object_list.reverse()
	assert_false(tester_a.is_node_contiguous(bvh_a.bvh_list[1]), "Swapping child order, unsafe")


func test_is_similar_to() -> void:
	assert_true(tester_a.is_similar_to(bvh_a2), "Trivial true")

	bvh_a2.bvh_list.append(PTBVHTree.BVHNode.new(null, bvh_a2))
	assert_true(tester_a.is_similar_to(bvh_a2), "Empty node ignored")

	bvh_a2.object_count += 1
	assert_false(
			tester_a.is_similar_to(bvh_a2) or
			tester_a.is_similar_diff[0] or
			tester_a.is_similar_diff.count(true) != 6,
			"Differing object count"
	)
	bvh_a2.object_count -= 1

	var poor_orphan := PTSphere.new(Vector3(10, 10, 10), 2)
	bvh_a2.bvh_list[1].add_object(poor_orphan)
	bvh_a2.bvh_list[1].update_aabb()
	assert_false(
			tester_a.is_similar_to(bvh_a2) or
			tester_a.is_similar_diff[2] or
			tester_a.is_similar_diff.count(true) != 6,
			"Differing aabb + unindexed object"
	)

	poor_orphan.free()
