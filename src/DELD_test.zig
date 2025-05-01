const std = @import("std");
const testing = std.testing;
const mem = std.mem;

const DELD = @import("DELD.zig");
const Deld = DELD.Deld;

test "DELD parseFromBytes with valid data" {
    const allocator = testing.allocator;

    var test_data = [_]u8{
        0x00, 0x00, 0x00, 0x0C,
        't',  'e',  's',  't',
        '/',  'd',  'e',  'l',
        'e',  't',  'e',  '1',
    };

    const deld = try Deld.parseFromBytes(&test_data, allocator);
    defer allocator.free(deld.path);

    try testing.expectEqual(@as(u32, 12), deld.path_size);
    try testing.expectEqualStrings("test/delete1", deld.path[0..deld.path_size]);
}

test "DELD parseFromBytes with empty path" {
    const allocator = testing.allocator;

    var test_data = [_]u8{
        0x00, 0x00, 0x00, 0x00,
    };

    const deld = try Deld.parseFromBytes(&test_data, allocator);
    defer allocator.free(deld.path);

    try testing.expectEqual(@as(u32, 0), deld.path_size);
    try testing.expectEqualStrings("", deld.path[0..deld.path_size]);
}

test "DELD parseFromBytes with unexpected end of file" {
    const allocator = testing.allocator;

    var test_data = [_]u8{
        0x00, 0x00, 0x00, 0x0C,
        't',  'e',  's',  't',
        '/',
    };

    try testing.expectError(error.UnexpectedEndOfFile, Deld.parseFromBytes(&test_data, allocator));
}

test "DELD parseFromBytes with path size too large" {
    const allocator = testing.allocator;

    var test_data = [_]u8{
        0x00, 0x00, 0x04, 0x01,
    };

    try testing.expectError(error.PathSizeTooLarge, Deld.parseFromBytes(&test_data, allocator));
}

test "DELD parseFromBytes with insufficient data for path_size" {
    const allocator = testing.allocator;

    var test_data = [_]u8{
        0x00, 0x00,
    };

    try testing.expectError(error.UnexpectedEndOfFile, Deld.parseFromBytes(&test_data, allocator));
}
