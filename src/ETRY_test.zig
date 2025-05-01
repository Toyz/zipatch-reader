const std = @import("std");

const ETRY = @import("ETRY.zig");
const ChunkMode = ETRY.ChunkMode;
const CompressionMode = ETRY.CompressionMode;

test "ChunkMode conversions" {
    const testing = std.testing;

    try testing.expectEqual(ChunkMode.add, ChunkMode.fromU32(0x41000000));
    try testing.expectEqual(ChunkMode.delete, ChunkMode.fromU32(0x44000000));
    try testing.expectEqual(ChunkMode.modify, ChunkMode.fromU32(0x4D000000));
    try testing.expectEqual(ChunkMode.unknown, ChunkMode.fromU32(0x12345678));

    try testing.expectEqualStrings("add", ChunkMode.add.toString());
    try testing.expectEqualStrings("delete", ChunkMode.delete.toString());
    try testing.expectEqualStrings("modify", ChunkMode.modify.toString());
    try testing.expectEqualStrings("unknown", ChunkMode.unknown.toString());
}

test "CompressionMode conversions" {
    const testing = std.testing;

    try testing.expectEqual(CompressionMode.none, CompressionMode.fromU32(0x4E000000));
    try testing.expectEqual(CompressionMode.zlib, CompressionMode.fromU32(0x5A000000));
    try testing.expectEqual(CompressionMode.unknown, CompressionMode.fromU32(0x12345678));

    try testing.expectEqualStrings("none", CompressionMode.none.toString());
    try testing.expectEqualStrings("zlib", CompressionMode.zlib.toString());
    try testing.expectEqualStrings("unknown", CompressionMode.unknown.toString());
}
