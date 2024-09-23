extends _PTBVHTreeSetupHelper

## Class to test functions in PTBVHTree

# How to make test for when adding new index property


func before_all() -> void:
	super.before_all()


func test_index_node() -> void:
	var new_bvh := PTBVHTree.new(bvh_a.order, false)
	new_bvh.root_node = bvh_a.root_node

	new_bvh.index_node(new_bvh.root_node)
	new_bvh.index_node(new_bvh.root_node.children[0])
	new_bvh.index_node(new_bvh.root_node.children[1])
	new_bvh.index_node(new_bvh.root_node.children[1].children[0])
	new_bvh.index_node(new_bvh.root_node.children[1].children[1])

	assert_true(tester_a.is_same_as(new_bvh), "Manual index_node")


func test_index_subnodes() -> void:
	pending()


func test_erase_indices() -> void:
	var new_bvh := create_test_bvh_a1()
	var new_tester := PTBVHTreeHelper.new(new_bvh)

	var empty_tree_a := PTBVHTree.new(bvh_a.order, false)
	empty_tree_a.root_node = bvh_a.root_node

	new_bvh.erase_indices()

	assert_true(new_tester.is_same_as(empty_tree_a))


## Simply increment/decrement the number when adding/removing property from PTBVHTree.
## This is to remember needing to add/remove tree indices to test like is_similar or is_tree_valid.
func test_property_count() -> void:
	assert_eq(bvh_a.get_property_list().size(), 24, "Assert property count is as expected.")