const std = @import("std");
const log = std.log;
const mem = std.mem;

/// Represents an Apply (APLY) block in a ZiPatch file.
/// Contains metadata about the patch application.
pub const Aply = struct {
    /// First value in the APLY block
    value1: [4]u8,

    /// Second value in the APLY block
    value2: [4]u8,

    /// Third value in the APLY block
    value3: [4]u8,

    /// Parses an APLY block from raw bytes.
    ///
    /// Parameters:
    ///   bytes: Raw payload data from the block
    ///
    /// Returns: Parsed Aply structure or error
    pub fn parseFromBytes(bytes: []const u8) !Aply {
        if (bytes.len < 12) {
            return error.UnexpectedEndOfFile;
        }

        log.debug("Parsing APLY from bytes: {x}", .{bytes});

        var value1: [4]u8 = undefined;
        var value2: [4]u8 = undefined;
        var value3: [4]u8 = undefined;

        @memcpy(&value1, bytes[0..4]);
        @memcpy(&value2, bytes[4..8]);
        @memcpy(&value3, bytes[8..12]);

        return Aply{
            .value1 = value1,
            .value2 = value2,
            .value3 = value3,
        };
    }
};
