@tool
class_name PTBVHTree
extends RefCounted

# TODO If i turn BVHNodes into actual nodes i can save and load BVHTrees
# TODO Alternatively look at inst_to_dict for serialization, or var_to_bytes

# TODO Make graph representation, maybe with graphEdit

## Base class for BVH trees.
##
##
## Nice reading summary:
## https://hackmd.io/@zOZhMrk6TWqOaocQT3Oa0A/HJUqrveG5
##
## Also really good overview
## https://meistdan.github.io/publications/bvh_star/paper.pdf
##
## The user can add their own algorithmic implementation of the creation code.
## After all BVHNodes point to their respective child nodes and objects, index_tree
## should be called to assure it will work properly with the rest of the Engine.
##
## If there is a function both with and without an underscore, the one with underscore
## probably doesn't handle bvh_list indexing.
##
## PTBVHTrees can have sub-trees within them, visible by the root node of the sub-tree's
## tree property. Each PTBVHTree object has ownership of their sub-tree and they
## should control changes to their own branches and nodes. The super-trees will
## still have indices to nodes in the sub-trees and can only use get functions on them.

## Enum of different possible BVH algorithms, should be updated as more algortithms
##  are added. Only positive numbers (and zero) are allowed as values.
enum BVHType {
	X_SORTED,
	Y_SORTED,
	Z_SORTED,
}

const enum_to_dict := {
	BVHType.X_SORTED : "X-Axis Sorted",
	BVHType.Y_SORTED : "Y-Axis Sorted",
	BVHType.Z_SORTED : "Z-Axis Sorted",
}

static var built_in_bvh_functions := {
	"X-Axis Sorted" : PTBVHAxisSort.x_axis_sorted,
	"Y-Axis Sorted" : PTBVHAxisSort.y_axis_sorted,
	"Z-Axis Sorted" : PTBVHAxisSort.z_axis_sorted,
}

# TODO Should add config file where the user can specify functions and names
#  And they will be added to enum/dict either here or from a Autoload
## The user can add their of own bvh functions to the bvh_functions dict. The only
##  non-optional arguments needs to be a PTObjectContainer followed by a maximum child count.
##  Of course it also needs to return a PTBVHTree or subtype.
static var bvh_functions := built_in_bvh_functions

# TODO add support for meshes
const objects_to_exclude : Array[PTObject.ObjectType] = [
	PTObject.ObjectType.NOT_OBJECT,
	PTObject.ObjectType.PLANE,
	PTObject.ObjectType.MAX,
]

# TODO Implement transforms for bvhnodes

# TODO Fix support for multi order trees
var order : int

# BVHTrees can merge, parent_tree is the BVH this tree was merged with
var parent_tree : PTBVHTree
var is_sub_tree : bool:
	get:
		return is_instance_valid(parent_tree)

var root_node : BVHNode

var object_container : PTObjectContainer
var object_to_leaf := {}
var leaf_nodes : Array[BVHNode]

## Takes in a node gives its index in bvh_list
var _node_to_index := {}

# TODO Add bvh constructor with bvh_list as argument
var bvh_list : Array[BVHNode] = []

var leaf_count : int # Counts nodes with no child nodes
var inner_count : int # Counts nodes with child nodes, including root node
var object_count : int # Counts the number of objects stored in leaf nodes

# NOTE: how to handle meshes with different types
var type : BVHType
var creation_time : int # In usecs
var SAH_cost : float

# TODO Instead make a list of indices that needs to be updated
var updated_nodes : Array[BVHNode] = [] # Nodes that need to update their buffer
# TODO MAke BVHBUffer abler to expand + have empty space

# TODO Make a check for loops existing


func _init(_order := 2) -> void:
	order = _order
	root_node = BVHNode.new(null, self)
	inner_count += 1

	bvh_list = [root_node]


static func create_bvh_with_function_name(
		objects : PTObjectContainer,
		_order : int,
		_name : String,
	) -> PTBVHTree:

	if _name not in bvh_functions.keys():
		print("Name: %s, not in list of callable bvh functions" % _name)
		return
	@warning_ignore("unsafe_cast")
	var tempt := bvh_functions[_name] as Callable # UNSTATIC
	var start_time : int = Time.get_ticks_usec()
	var bvh : PTBVHTree = tempt.call(objects, _order) # UNSTATIC
	bvh.creation_time = (Time.get_ticks_usec() - start_time)
	return bvh


func update_aabb(object : PTObject) -> void:
	assert(has(object), "PT: Cannot update the aabb of an object that is not in BVH.\n" +
				"object: " + str(object))

	var node : BVHNode = object_to_leaf[object] # UNSTATIC
	node.update_aabb()


func add_node_to_updated_nodes(node : BVHNode) -> void:
	if not node in updated_nodes:
		updated_nodes.append(node)


func has(object : PTObject) -> bool:
	return object_to_leaf.has(object)


func _add_object_to_tree(object : PTObject) -> Array[BVHNode]:
	# TODO Change to local aabb when using meshes + transforms
	var fitting_node := find_aabb_spot(object.get_global_aabb())
	var new_nodes : Array[BVHNode] = []

	if fitting_node == null:
		fitting_node = root_node

	# If node is full, split and get non-full fitting node
	if fitting_node.is_full:
		if PTRendererAuto.is_debug:
			print("No vacant leaf node to add new object. Splitting node in two.")
		new_nodes.append_array(_split_node(fitting_node))
		fitting_node = find_aabb_spot(object.get_global_aabb(), fitting_node)

	# Add object to node
	if fitting_node.is_inner:
		var new_node := BVHNode.new(fitting_node, self)
		new_node.object_list.append(object)
		new_node.set_aabb()
		fitting_node.add_children([new_node])
		new_nodes.append(new_node)
	else:
		fitting_node.object_list.append(object)
		object_to_leaf[object] = fitting_node # UNSTATIC
		if is_sub_tree:
			parent_tree.object_to_leaf[object] = fitting_node # UNSTATIC

	fitting_node.update_aabb()

	return new_nodes


func add_object(object : PTObject) -> void:
	if object.get_type() in objects_to_exclude:
		push_warning("PT: Cannot add object to BVH as it is explicitly excluded.\n",
				"object: ", object, "\ntype: ", object.get_type_name())
		return

	if has(object):
		print("PT: Object is already in BVHTree.")
		return

	if PTRendererAuto.is_debug:
		print("Adding object ", object, " to bvh")

	var new_nodes := _add_object_to_tree(object)
	for node in new_nodes:
		index_node(node)

	# TODO MAke BVHBUffer abler to expand + have empty space
	# Would set flag for buffer expansion here


func remove_object(object : PTObject) -> void:
	# TODO FIX, currently messes up order of bvh
	# TODO remove object from bvh_list and call back parent_tree
	if not has(object):
		push_warning("Object: %s already removed from bvh tree" % object)
		return

	if PTRendererAuto.is_debug:
		print("Removing object ", object, " from bvh")

	var leaf : BVHNode = object_to_leaf[object] # UNSTATIC
	object_to_leaf.erase(object)

	var index : int = leaf.object_list.find(object)
	if index != -1:
		leaf.object_list.remove_at(index)
		if leaf.size() == 0:
			# TODO Remove BVH node
			pass

		leaf.update_aabb()


func get_node_index(node : BVHNode) -> int:
	return _node_to_index[node] # UNSTATIC


## Returns an array of indexed nodes, based on the calling tree's node index.
func get_indices(node : BVHNode, indices : Array[int] = []) -> Array[int]:
	 # NOTE: Unlike python, an array as a default parameter is an unique instance
	if indices.is_empty() or node.is_leaf:
		indices.append(get_node_index(node))
	if node.is_inner:
		for child in node.children:
			get_indices(child, indices)

	return indices


## Returns an array of nodes that descend from a given node .
func get_subnodes(node : BVHNode, indices : Array[BVHNode] = []) -> Array[BVHNode]:
	 # NOTE: Unlike python, an array as a default parameter is an unique instance
	if indices.is_empty() or node.is_leaf:
		indices.append(node)
	if node.is_inner:
		for child in node.children:
			get_subnodes(child, indices)

	return indices


## Sets tree indices of tree for newly created node
func index_node(node : BVHNode) -> void:
	# TODO Change to recursive indexing if we have nested sub-trees
	#assert(node.tree == self, "The given node is not a part of this tree or is in" +
			#"a sub-tree. Please use the sub-tree's methods instead.")
	if node.is_inner:
		for child in node.children:
			child.parent = node
	else:
		for object in node.object_list:
			object_to_leaf[object] = node # UNSTATIC
			if is_sub_tree:
				parent_tree.object_to_leaf[object] = node # UNSTATIC

		if not node in leaf_nodes:
			leaf_nodes.append(node)
			if is_sub_tree:
				parent_tree.leaf_nodes.append(node)

	if not node in _node_to_index:
		_node_to_index[node] = bvh_list.size() # UNSTATIC
		bvh_list.append(node)

		if is_sub_tree:
			parent_tree._node_to_index[node] = parent_tree.bvh_list.size() # UNSTATIC
			parent_tree.bvh_list.append(node)


## Sets the required indexes required for the BVHTree to work with the engine
func index_tree() -> void:
	bvh_list = []
	leaf_nodes = []
	object_to_leaf = {}
	_node_to_index = {}
	inner_count = 0
	leaf_count = 0
	object_count = 0

	_index_node(root_node)


## Recursively index whole tree/sub-tree under given node
func _index_node(node : BVHNode) -> void:
	# TODO Make function comply with new sub-tree policy
	#assert(node.tree == self, "The given node is not a part of this tree or is in" +
			#"a sub-tree. Please use the sub-tree's methods instead.")
	_node_to_index[node] = bvh_list.size() # UNSTATIC
	bvh_list.append(node)
	inner_count += 1

	for child in node.children:
		if child.is_leaf:
			_node_to_index[child] = bvh_list.size()  # UNSTATIC
			bvh_list.append(child)
			leaf_nodes.append(child)

			leaf_count += 1
			object_count += child.object_list.size()
			for object in child.object_list:
				object_to_leaf[object] = child # UNSTATIC
			continue

		#if child
		_index_node(child)


## Finds a non-full inner node recursively
func find_inner_node(node : BVHNode) -> BVHNode:
	assert(node.tree == self, "The given node is not a part of this tree or is in" +
			"a sub-tree. Please use the sub-tree's methods instead.")
	if node.is_leaf:
		return null
	if node.size() < order:
		return node
	else:
		# If inner node is full, check its children
		for child in node.children:
			var temp : BVHNode
			if child.tree != self:
				# TODO I don't think i should do this, just return
				temp = child.tree.find_inner_node(child)
			else:
				temp = find_inner_node(child)
			if is_instance_valid(temp):
				return temp
	return null # If no inner nodes have room return null


## If a node is empty add it to return list and recursively call parents.
## Returns an array of nodes that can be removed. They are not changed by the function
func node_cleanup(node : BVHNode, cleaned_nodes : Array[BVHNode] = []) -> Array[BVHNode]:
	if node.size() == 0:
		cleaned_nodes.append(node)
		return node_cleanup(node.parent)
	# If child is the empty node that called this function
	if node.is_inner and node.size() == 1 and node.children[0] in cleaned_nodes:
		cleaned_nodes.append(node)
		return node_cleanup(node.parent)

	return []


## Splits a node in two, dividing its children/objects evenly among two new nodes.
## Returns these new nodes.
func _split_node(node : BVHNode) -> Array[BVHNode]:
	assert(node.tree == self, "The given node is not a part of this tree or is in" +
			"a sub-tree. Please use the sub-tree's methods instead.")
	var new_node_left := BVHNode.new(node, self)
	var new_node_right := BVHNode.new(node, self)

	new_node_left.is_inner = node.is_inner
	new_node_right.is_inner = node.is_inner

	if node.is_inner:
		@warning_ignore("integer_division")
		var halfway := node.children.size() / 2
		new_node_left.add_children(node.children.slice(0, halfway))
		new_node_right.add_children(node.children.slice(halfway))

		node.children.clear()

		inner_count += 2
	else:
		@warning_ignore("integer_division")
		var halfway := node.object_list.size() / 2
		new_node_left.object_list.append_array(node.object_list.slice(0, halfway))
		new_node_left.object_list.append_array(node.object_list.slice(halfway))

		# Remove leaf node references in node
		node.object_list.clear()
		leaf_nodes.erase(node)
		if is_sub_tree:
			parent_tree.leaf_nodes.erase(node)
		node.is_inner = true

		inner_count += 1
		leaf_count += 1

	node.add_children([new_node_left, new_node_right])
	add_node_to_updated_nodes(node)

	return [new_node_left, new_node_right]


## Index the result of _split_node
func _split_node_index(nodes : Array[BVHNode]) -> Array[BVHNode]:
	var left := nodes[0]
	var right := nodes[1]

	add_node_to_updated_nodes(left)
	left.set_aabb()
	right.update_aabb() # Also calls updated_nodes.append

	index_node(left)
	index_node(right)

	return nodes


## Splits a node in two, dividing its children/objects evenly among two new nodes.
## Returns these new nodes.
func split_node(node : BVHNode) -> Array[BVHNode]:
	return _split_node_index(_split_node(node))


## Based on an AABB, finds a spot in the tree where it is fully enclosed
## by a node's AABB if there is one. If not then return null.
## The function does not account for whether the found node is full or not.
## NOTE: This is a greedy search algorithm and it will return the first spot
##  that is good enough
func find_aabb_spot(aabb : AABB, node := root_node) -> BVHNode:
	if node.aabb.encloses(aabb):
		if node.is_inner:
			for child in node.children:
				var temp_node := find_aabb_spot(aabb, child)
				if is_instance_valid(temp_node):
					# Return the first child that encloses aabb
					return temp_node
		# node fits, but none of its children (if it has children) does
		return node

	# We found no nodes that fit
	return null



## Merge another BVHTree into this one.
## Return new nodes that need to be added to bvh_list.
func _merge_with(other : PTBVHTree, root := root_node) -> Array[BVHNode]:
	# Find inner node to place other
	var fitting_node := find_aabb_spot(other.root_node.aabb, root)
	var new_nodes : Array[BVHNode] = []

	if fitting_node == null:
		fitting_node = root_node

	# If node is full or a leaf, split and get non-full fitting node
	if fitting_node.is_full or fitting_node.is_leaf:
		if PTRendererAuto.is_debug:
			print("No vacant leaf node to add new object. Splitting node in two.")
		new_nodes.append_array(_split_node(fitting_node))
		fitting_node = find_aabb_spot(other.root_node.aabb, fitting_node)

	new_nodes.append_array(other.bvh_list.duplicate())

	# "Glue the seam"
	fitting_node.add_children([other.root_node])
	fitting_node.update_aabb()
	add_node_to_updated_nodes(fitting_node)
	other.root_node.parent = fitting_node

	object_to_leaf.merge(other.object_to_leaf)
	_node_to_index.merge(other._node_to_index)
	leaf_nodes.append_array(other.leaf_nodes)

	object_count += other.object_count
	leaf_count += other.leaf_count
	inner_count += other.inner_count

	other.parent_tree = self

	return new_nodes
	# TODO Add print/assert to verify succesfull merge


## Inserts another tree at a node in the bvh.
## An optional argument root can be given, the insertion will
##  happen to one of its children
func merge_with(other : PTBVHTree, root := root_node) -> void:
	_merge_with(other, root)

	var index_offset := bvh_list.size()
	bvh_list.append_array(other.bvh_list)

	# Reindexing
	for node : BVHNode in other.bvh_list:
		_node_to_index[node] += index_offset # UNSTATIC



func _remove_node(node : BVHNode) -> void:
	#assert(node.tree == self, "The given node is not a part of this tree or is in" +
			#"a sub-tree. Please use the sub-tree's methods instead.")
	# TODO Remember to reindex / or fill hole with last node + fix indices
	bvh_list.remove_at(get_node_index(node))
	_node_to_index.erase(node)
	if node.is_inner:
		for child in node.children:
			_remove_node(child)
		inner_count -= 1
	else:
		leaf_nodes.erase(node)
		for object in node.object_list:
			object_to_leaf.erase(object)
			object_count -= 1
		leaf_count -= 1


## Remove all nodes that are descendants of a given node from the tree
func remove_subtree(node : BVHNode) -> void:
	# TODO Make recursive function to find any sub-trees that are removed in the process
	# TODO Also this function almost certainly doesn't work properly
	assert(node.tree == self or node == node.tree.root_node,
			"The given node is not a part of this tree or is the root node of a " +
			"sub-tree. Please use the sub-tree's methods instead.")
	# Remove from parent node
	node.parent.children.erase(node)

	var index : int = _node_to_index[node] # UNSTATIC
	_remove_node(node)

	# Reindex all nodes from index to end of bvh_list
	for i in range(index, bvh_list.size()):
		_node_to_index[bvh_list[i]] = i # UNTSTATIC


## Adds and removes requested objects and meshes. Only called by PTScene.
## Returns an array of indices of nodes that needs buffer updating.
func _rebalance_objects(
		added_objects : PTObjectContainer,
		removed_objects : PTObjectContainer
	) -> Array[int]:

	# This should only be called by PTScene, max once per frame.
	# It will ensure that all objects added/removed are not part of any potential meshes

	var node_indices_to_update : Array[int] = []

	## Removing
	var removed_nodes : Array[BVHNode] = []
	# Remove meshes from tree
	for mesh in removed_objects.meshes:
		var node := mesh.bvh.root_node
		removed_nodes.append_array(get_subnodes(node))
		node.parent.children.erase(node)

	# Remove scene objects from tree
	for _type : PTObject.ObjectType in PTObject.ObjectType.values(): # UNSTATIC
		for object : PTObject in removed_objects.get_object_array(_type): # UNSTATIC
			var node : BVHNode = object_to_leaf[object] # UNSTATIC
			object_to_leaf.erase(object)
			node.object_list.erase(object)

			# If node has no more objects delete it, also check parents for emptiness
			if node.object_list.is_empty():
				removed_nodes.append_array(node_cleanup(node))

	# Sort nodes based on index in bvh_list, highest index first
	removed_nodes.sort_custom(
		func(a : BVHNode, b : BVHNode) -> bool:
			return get_node_index(a) > get_node_index(b)
	)

	var removed_nodes_indices : Array[int] = []

	# Remove references to removed nodes
	for node in removed_nodes:
		removed_nodes_indices.append(get_node_index(node))
		_node_to_index.erase(node)
		if node.is_inner:
			inner_count -= 1
		else:
			leaf_nodes.erase(node)
			for object in node.object_list:
				object_to_leaf.erase(object)
				object_count -= 1
			leaf_count -= 1

	## Adding
	var added_nodes : Array[BVHNode] = []
	# Add meshes to tree
	for mesh in added_objects.meshes:
		added_nodes.append_array(_merge_with(mesh.bvh))

	# Add objects to tree, updated nodes are appended to updated_nodes
	for _type : PTObject.ObjectType in PTObject.ObjectType.values():
		for object : PTObject in removed_objects.get_object_array(_type): # UNSTATIC
			added_nodes.append_array(_add_object_to_tree(object))

	# Fit new objects into holes created by removed nodes (if any)
	for node in added_nodes:
		var index := bvh_list.size()
		if not removed_nodes_indices.is_empty():
			index = removed_nodes_indices.pop_back() # UNSTATIC
			assert(index < bvh_list.size(), "Node marked as removed was prematuraly removed from bvh_list")
			bvh_list[index] = node
			_node_to_index[node] = index # UNSTATIC
			node_indices_to_update.append(index)
			continue

		# If no more holes to fill, simply append the back
		bvh_list.append(node)
		_node_to_index[node] = index # UNSTATIC
		node_indices_to_update.append(index)

	# If more nodes were removed than added move the ones at the back into the holes
	if not removed_nodes_indices.is_empty():
		for index in removed_nodes_indices:
			var last_index := bvh_list.size() - 1
			if index == last_index:
				bvh_list.pop_back()
				continue

			var node := bvh_list[last_index]
			_node_to_index[node] = index # UNSTATIC
			bvh_list[index] = node

			node_indices_to_update.append(index)

	return node_indices_to_update


func size() -> int:
	"""Returns the total bumber of nodes in the tree"""
	return inner_count + leaf_count


func depth() -> int:
	"""Returns the length of the longest path from the root to a leaf node"""
	var counter : int = 0
	var current_node := root_node
	# The default tree is created in a way in which the longest path will be
	#	along the first indices of each node
	while !current_node.is_leaf:
		current_node = current_node.children[0]
		counter += 1
	return counter


# TODO Implement sah_cost fucntion
func tree_sah_cost() -> void:
	"Calculates the SAH cost for the whole tree"


func to_byte_array() -> PackedByteArray:
	var bytes := PackedByteArray()
	for node in bvh_list:
		bytes += node.to_byte_array()
	return bytes


class BVHNode:
	## This class represents a Node in a bvh tree.
	##
	## Ideally all bvh trees would use the same Node class, since their only
	## intention is to hold information.
	##
	## A BVHNode is either an inner node, where the children property point to
	## other BVHNodes, or a leaf node, where its object_list property point to
	## objects. Having a mixed node is technically supported, but is unadviced.
	## Rather, wrap the objects in the mixed node into a new leaf node child.

	var tree : PTBVHTree # Reference to the tree this node is a part of
	var parent : BVHNode # Reference to parent BVHNode
	var children : Array[BVHNode] # Reference to child BVHNodes
	var aabb : AABB

	# Leaf nodes in the tree have no children and have a list pointing to objects
	#  The object list is no larger than tree.order
	var object_list : Array[PTObject] = []
	var is_leaf := false
	var is_inner : bool:
		get:
			return not is_leaf
		set(value):
			is_inner = value
			is_leaf = not value

	var is_full : bool:
		get:
			if is_inner:
				assert(children.size() <= tree.order,
						"BVHNode has more children than tree.order allows.")
				return children.size() == tree.order

			assert(object_list.size() <= tree.order,
						"BVHNode has more children than tree.order allows.")
			return object_list.size() == tree.order


	func _init(p_parent : BVHNode, p_tree : PTBVHTree) -> void:
		parent = p_parent
		tree = p_tree


	func size() -> int:
		"""Returns number of children and number of references to objects"""
		return children.size() + object_list.size()


	func set_aabb() -> void:
		if is_leaf and not object_list.is_empty():
			aabb = object_list[0].get_global_aabb()
			for object in object_list:
				aabb = aabb.merge(object.get_global_aabb())
			return

		if not children.is_empty():
			aabb = children[0].aabb
			for child in children:
				if child.aabb:
					aabb = aabb.merge(child.aabb)
				else:
					push_warning("Warning: Child node %s does not have aabb" % child)


	func update_aabb() -> void:
		var old_aabb := aabb
		set_aabb()
		if aabb.is_equal_approx(old_aabb):
			tree.add_node_to_updated_nodes(self)
			if is_instance_valid(parent):
				parent.update_aabb()


	func add_children(new_children : Array[BVHNode]) -> void:
		if size() + new_children.size() <= tree.order:
			children += new_children
			set_aabb() # Update aabb
		else:
			push_warning("Warning: Cannot fit child BVHNode(s) to node: ", self)


	func to_byte_array() -> PackedByteArray:
		var child_indices_array := []

		# Add children nodes and objects to children list
		for child in children:
			child_indices_array.append(tree.get_node_index(child))

		for object in object_list:
			var type : int = object.get_type()
			var _index : int = tree.object_container.get_object_index(object)
			child_indices_array.append(PTObject.make_object_id(_index, type))

		# Needed for buffer alignement
		#child_indices_array.resize(tree.order)
		child_indices_array.resize(tree.order +
								   int((tree.order % 4) - 4) * -1)

		var bbox_bytes : PackedByteArray = PTObject.aabb_to_byte_array(aabb)

		return PackedInt32Array(child_indices_array).to_byte_array() + bbox_bytes


