class_name PTTestHelper
extends RefCounted

## Class with some functions to help assert conditions

## Check if all elements of array are keys with values pointing to their index
static func check_dictionary_index(array : Array, dict : Dictionary) -> bool:
	for i in range(array.size()):
		if i != dict.get(array[i]):
			return false
	return true

