extends GutTest


func test_create_missing_texture_grid() -> void:
    var result2 : Array[int] = [
        56, 16, 56, 56,
        0, 0, 0, 56,

        0, 0, 0, 56,
        56, 16, 56, 56,
    ]
    var result4 : Array[int] = [
        56, 16, 56, 56,
        0, 0, 0, 56,
        56, 16, 56, 56,
        0, 0, 0, 56,

        0, 0, 0, 56,
        56, 16, 56, 56,
        0, 0, 0, 56,
        56, 16, 56, 56,

        56, 16, 56, 56,
        0, 0, 0, 56,
        56, 16, 56, 56,
        0, 0, 0, 56,

        0, 0, 0, 56,
        56, 16, 56, 56,
        0, 0, 0, 56,
        56, 16, 56, 56,
    ]

    # Unfortunately i do not know any other way to create a PackedByteArray 
    #  without it wrongly converting numbers
    var res2 : PackedByteArray = []
    var res4 : PackedByteArray = []
    res2.resize(result2.size())
    res4.resize(result4.size())

    for i in range(res2.size()):
        res2.encode_u8(i, result2[i])
    

    for i in range(res4.size()):
        res4.encode_u8(i, result4[i])


    assert_eq(PTUtils.create_missing_texture_grid(2), res2)
    assert_eq(PTUtils.create_missing_texture_grid(4), res4)
