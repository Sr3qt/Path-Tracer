extends _PTBVHTreeSetupHelper

## Class to test functions in PTBVHTree

# How to make test for when adding new index property

var bvh_a_index_node : PTBVHTree


func before_all() -> void:
	super.before_all()

	bvh_a_index_node = create_test_bvh_a1(true)


func test_index_node() -> void:
	var new_bvh := PTBVHTree.new(bvh_a.order, false)
	new_bvh.root_node = bvh_a.root_node
	# new_bvh.index_node()
	# assert_true(tester_a.is_same_as(new_bvh))
	pending()


func test_erase_indices() -> void:
	# Check if bvh.erase_indices is_same_as new bvh with same root node.
	# assert_true(tester_a.is_same_as()
	pending()


## Simply increment/decrement the number when adding/removing property from PTBVHTree.
## This is to remember needing to add/remove tree indices to test like is_similar or is_tree_valid.
func test_property_count() -> void:
	assert_eq(bvh_a.get_property_list().size(), 24, "Assert property count is as expected.")