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

    try testing.expectEqualStrings("ADD", ChunkMode.add.toString());
    try testing.expectEqualStrings("DELETE", ChunkMode.delete.toString());
    try testing.expectEqualStrings("MODIFY", ChunkMode.modify.toString());
    try testing.expectEqualStrings("UNKNOWN_MODE", ChunkMode.unknown.toString());
}

test "CompressionMode conversions" {
    const testing = std.testing;

    try testing.expectEqual(CompressionMode.none, CompressionMode.fromU32(0x4E000000));
    try testing.expectEqual(CompressionMode.zlib, CompressionMode.fromU32(0x5A000000));
    try testing.expectEqual(CompressionMode.unknown, CompressionMode.fromU32(0x12345678));

    try testing.expectEqualStrings("NONE", CompressionMode.none.toString());
    try testing.expectEqualStrings("ZLIB", CompressionMode.zlib.toString());
    try testing.expectEqualStrings("UNKNOWN_COMPRESSION", CompressionMode.unknown.toString());
}
