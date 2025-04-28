const std = @import("std");

const header = @import("header.zig");
const BlockType = header.BlockType;

test "BlockType conversions" {
    const testing = std.testing;

    try testing.expectEqual(BlockType.FHDR, BlockType.fromBytes("FHDR".*));
    try testing.expectEqual(BlockType.APLY, BlockType.fromBytes("APLY".*));
    try testing.expectEqual(BlockType.APFS, BlockType.fromBytes("APFS".*));
    try testing.expectEqual(BlockType.ETRY, BlockType.fromBytes("ETRY".*));
    try testing.expectEqual(BlockType.ADIR, BlockType.fromBytes("ADIR".*));
    try testing.expectEqual(BlockType.DELD, BlockType.fromBytes("DELD".*));
    try testing.expectEqual(BlockType.unknown, BlockType.fromBytes("UNKN".*));

    try testing.expectEqualStrings("FHDR", BlockType.FHDR.toString());
    try testing.expectEqualStrings("APLY", BlockType.APLY.toString());
    try testing.expectEqualStrings("APFS", BlockType.APFS.toString());
    try testing.expectEqualStrings("ETRY", BlockType.ETRY.toString());
    try testing.expectEqualStrings("ADIR", BlockType.ADIR.toString());
    try testing.expectEqualStrings("DELD", BlockType.DELD.toString());
    try testing.expectEqualStrings("unknown", BlockType.unknown.toString());
}
