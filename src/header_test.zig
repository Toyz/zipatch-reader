const std = @import("std");
const testing = std.testing;

const header = @import("header.zig");
const BlockType = header.BlockType;
const BlockInfo = header.BlockInfo;

test "BlockType conversions" {
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

test "BlockInfo read with valid data" {
    const data = [_]u8{
        0x00, 0x00, 0x01, 0x00,
        'F', 'H', 'D', 'R',
    };

    var fbs = std.io.fixedBufferStream(&data);
    const reader = fbs.reader();

    const block_info = BlockInfo.read(reader) catch |err| {
        try testing.expect(false);
        return err;
    };

    try testing.expectEqual(@as(u32, 256), block_info.size);
    try testing.expectEqual(BlockType.FHDR, block_info.block_type);
    try testing.expectEqual(@as(u32, 0), block_info.crc);
}

test "BlockInfo read with unknown block type" {
    const data = [_]u8{
        0x00, 0x00, 0x02, 0x00,
        'U',  'N',  'K',  'N',
    };

    var fbs = std.io.fixedBufferStream(&data);
    const reader = fbs.reader();

    const block_info = BlockInfo.read(reader) catch |err| {
        try testing.expect(false);
        return err;
    };

    try testing.expectEqual(@as(u32, 512), block_info.size);
    try testing.expectEqual(BlockType.unknown, block_info.block_type);
    try testing.expectEqual(@as(u32, 0), block_info.crc);
}

test "BlockInfo read with insufficient data" {
    const data = [_]u8{
        0x00, 0x00, 0x03, 0x00,
        'F',  'H',
    };

    var fbs = std.io.fixedBufferStream(&data);
    const reader = fbs.reader();

    try testing.expectError(error.UnexpectedEndOfFile, BlockInfo.read(reader));
}

test "BlockInfo read with empty data" {
    const data = [_]u8{};

    var fbs = std.io.fixedBufferStream(&data);
    const reader = fbs.reader();

    try testing.expectError(error.UnexpectedEndOfFile, BlockInfo.read(reader));
}
