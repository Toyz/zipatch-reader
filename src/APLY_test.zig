const std = @import("std");
const testing = std.testing;
const mem = std.mem;

const APLY = @import("APLY.zig");
const Aply = APLY.Aply;

test "APLY parseFromBytes with valid data" {
    const test_data = [_]u8{
        0x01, 0x02, 0x03, 0x04,
        0x11, 0x22, 0x33, 0x44,
        0xAA, 0xBB, 0xCC, 0xDD,
    };

    const aply = try Aply.parseFromBytes(&test_data);

    try testing.expectEqualSlices(u8, &[_]u8{ 0x01, 0x02, 0x03, 0x04 }, &aply.value1);
    try testing.expectEqualSlices(u8, &[_]u8{ 0x11, 0x22, 0x33, 0x44 }, &aply.value2);
    try testing.expectEqualSlices(u8, &[_]u8{ 0xAA, 0xBB, 0xCC, 0xDD }, &aply.value3);
}

test "APLY parseFromBytes with all zeros" {
    const test_data = [_]u8{
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
    };

    const aply = try Aply.parseFromBytes(&test_data);

    try testing.expectEqualSlices(u8, &[_]u8{ 0x00, 0x00, 0x00, 0x00 }, &aply.value1);
    try testing.expectEqualSlices(u8, &[_]u8{ 0x00, 0x00, 0x00, 0x00 }, &aply.value2);
    try testing.expectEqualSlices(u8, &[_]u8{ 0x00, 0x00, 0x00, 0x00 }, &aply.value3);
}

test "APLY parseFromBytes with insufficient data" {
    const test_data = [_]u8{
        0x01, 0x02, 0x03, 0x04,
        0x11, 0x22, 0x33, 0x44,
    };

    try testing.expectError(error.UnexpectedEndOfFile, Aply.parseFromBytes(&test_data));
}

test "APLY parseFromBytes with empty data" {
    const test_data = [_]u8{};

    try testing.expectError(error.UnexpectedEndOfFile, Aply.parseFromBytes(&test_data));
}
