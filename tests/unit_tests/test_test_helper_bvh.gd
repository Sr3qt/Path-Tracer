extends GutTest

## Test script to test functions in test_helper_bvh

var SceneA := preload("res://tests/test_scenes/test_scene_bvh_a.tscn")
var scene_a : PTScene
var bvh_a : PTBVHTree
var bvh_a2 : PTBVHTree
var tester_a : PTTestHelperBVH


## Create a valid small tree
func create_test_bvh_a1(test_index_node := false) -> PTBVHTree:
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

    if test_index_node:
        # TODO Make test to verify that # Indices is equal to this
        var bvh_list : Array[PTBVHTree.BVHNode] = [
                bvh.root_node, node_l, node_r, node_rl, node_rr]
        for node in bvh_list:
            bvh.index_node(node)
    else:
        # Indices
        bvh.leaf_nodes = [node_l, node_rl, node_rr]
        bvh.bvh_list = [bvh.root_node, node_l, node_r, node_rl, node_rr]
        var i := 0
        for node in bvh.bvh_list:
            bvh._node_to_index[node] = i
            if node.is_leaf:
                node.object_id_index = bvh.object_ids.size() # DEPRECATED
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
            node.object_id_index = bvh.object_ids.size() # DEPRECATED
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


func create_test_bvh_b() -> PTBVHTree:
    pass
    return


func create_test_bvh_c() -> PTBVHTree:
    pass
    return


func before_all() -> void:
    bvh_a = create_test_bvh_a1()
    bvh_a2 = create_test_bvh_a2()

    tester_a = PTTestHelperBVH.new(bvh_a)


func after_all() -> void:
    scene_a.free()


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
