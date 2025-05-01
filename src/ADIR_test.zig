const std = @import("std");
const testing = std.testing;
const mem = std.mem;

const ADIR = @import("ADIR.zig");
const Adir = ADIR.Adir;

test "ADIR parseFromBytes with valid data" {
    const allocator = testing.allocator;

    var test_data = [_]u8{
        0x00, 0x00, 0x00, 0x0A,
        't',  'e',  's',  't',
        '/',  'p',  'a',  't',
        'h',  '1',
    };

    const adir = try Adir.parseFromBytes(&test_data, allocator);
    defer allocator.free(adir.path);

    try testing.expectEqual(@as(u32, 10), adir.path_size);
    try testing.expectEqualStrings("test/path1", adir.path[0..adir.path_size]);
}

test "ADIR parseFromBytes with empty path" {
    const allocator = testing.allocator;

    var test_data = [_]u8{
        0x00, 0x00, 0x00, 0x00,
    };

    const adir = try Adir.parseFromBytes(&test_data, allocator);
    defer allocator.free(adir.path);

    try testing.expectEqual(@as(u32, 0), adir.path_size);
    try testing.expectEqualStrings("", adir.path[0..adir.path_size]);
}

test "ADIR parseFromBytes with unexpected end of file" {
    const allocator = testing.allocator;

    var test_data = [_]u8{
        0x00, 0x00, 0x00, 0x0A,
        't',  'e',  's',  't',
    };

    try testing.expectError(error.UnexpectedEndOfFile, Adir.parseFromBytes(&test_data, allocator));
}

test "ADIR parseFromBytes with path size too large" {
    const allocator = testing.allocator;

    var test_data = [_]u8{
        0x00, 0x00, 0x04, 0x01,
    };

    try testing.expectError(error.PathSizeTooLarge, Adir.parseFromBytes(&test_data, allocator));
}

test "ADIR parseFromBytes with insufficient data for path_size" {
    const allocator = testing.allocator;

    var test_data = [_]u8{
        0x00, 0x00,
    };

    try testing.expectError(error.UnexpectedEndOfFile, Adir.parseFromBytes(&test_data, allocator));
}
