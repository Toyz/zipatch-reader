const std = @import("std");
const testing = std.testing;
const mem = std.mem;

const FHDR = @import("FHDR.zig");
const Fhdr = FHDR.Fhdr;
const FhdrResultType = FHDR.FhdrResultType;

test "FhdrResultType conversions" {
    const diff_bytes = [_]u8{ 'D', 'I', 'F', 'F' };
    const hist_bytes = [_]u8{ 'H', 'I', 'S', 'T' };
    const unknown_bytes = [_]u8{ 'U', 'N', 'K', 'N' };

    try testing.expectEqual(FhdrResultType.diff, FhdrResultType.fromBytes(diff_bytes));
    try testing.expectEqual(FhdrResultType.hist, FhdrResultType.fromBytes(hist_bytes));
    try testing.expectEqual(FhdrResultType.unknown, FhdrResultType.fromBytes(unknown_bytes));

    try testing.expectEqualStrings("diff", FhdrResultType.diff.toString());
    try testing.expectEqualStrings("hist", FhdrResultType.hist.toString());
    try testing.expectEqualStrings("unknown", FhdrResultType.unknown.toString());
}

test "FHDR parseFromBytes with valid DIFF data" {
    const test_data = [_]u8{
        '1',  '0',  '0',  '0',
        'D',  'I',  'F',  'F',
        0x00, 0x00, 0x03, 0xE8,
        0x00, 0x00, 0x00, 0x0A,
        0x00, 0x00, 0x00, 0x05,
    };

    const fhdr = try Fhdr.parseFromBytes(&test_data);

    try testing.expectEqualSlices(u8, &[_]u8{ '1', '0', '0', '0' }, &fhdr.version);
    try testing.expectEqual(FhdrResultType.diff, fhdr.result);
    try testing.expectEqual(@as(u32, 1000), fhdr.number_entry_file);
    try testing.expectEqual(@as(u32, 10), fhdr.number_add_dir);
    try testing.expectEqual(@as(u32, 5), fhdr.number_delete_dir);
}

test "FHDR parseFromBytes with valid HIST data" {
    const test_data = [_]u8{
        '2',  '0',  '0',  '0',
        'H',  'I',  'S',  'T',
        0x00, 0x00, 0x01, 0xF4,
        0x00, 0x00, 0x00, 0x14,
        0x00, 0x00, 0x00, 0x0A,
    };

    const fhdr = try Fhdr.parseFromBytes(&test_data);

    try testing.expectEqualSlices(u8, &[_]u8{ '2', '0', '0', '0' }, &fhdr.version);
    try testing.expectEqual(FhdrResultType.hist, fhdr.result);
    try testing.expectEqual(@as(u32, 500), fhdr.number_entry_file);
    try testing.expectEqual(@as(u32, 20), fhdr.number_add_dir);
    try testing.expectEqual(@as(u32, 10), fhdr.number_delete_dir);
}

test "FHDR parseFromBytes with unknown result type" {
    const test_data = [_]u8{
        '1',  '0',  '0',  '0',
        'U',  'N',  'K',  'N',
        0x00, 0x00, 0x00, 0x64,
        0x00, 0x00, 0x00, 0x05,
        0x00, 0x00, 0x00, 0x02,
    };

    const fhdr = try Fhdr.parseFromBytes(&test_data);

    try testing.expectEqualSlices(u8, &[_]u8{ '1', '0', '0', '0' }, &fhdr.version);
    try testing.expectEqual(FhdrResultType.unknown, fhdr.result);
    try testing.expectEqual(@as(u32, 100), fhdr.number_entry_file);
    try testing.expectEqual(@as(u32, 5), fhdr.number_add_dir);
    try testing.expectEqual(@as(u32, 2), fhdr.number_delete_dir);
}

test "FHDR parseFromBytes with insufficient data" {
    const test_data = [_]u8{
        '1',  '0',  '0',  '0',
        'D',  'I',  'F',  'F',
        0x00, 0x00, 0x03, 0xE8,
    };

    try testing.expectError(error.UnexpectedEndOfFile, Fhdr.parseFromBytes(&test_data));
}

test "FHDR parseFromBytes with empty data" {
    const test_data = [_]u8{};

    try testing.expectError(error.UnexpectedEndOfFile, Fhdr.parseFromBytes(&test_data));
}
