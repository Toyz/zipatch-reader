const std = @import("std");
const log = std.log;
const io = std.io;
const mem = std.mem;
const root = @import("root");

/// Represents an Apply (APLY) block in a ZiPatch file
/// Contains metadata about the patch application
pub const Aply = struct {
    /// First value in the APLY block
    value1: [4]u8,
    /// Second value in the APLY block
    value2: [4]u8,
    /// Third value in the APLY block
    value3: [4]u8,

    /// Parses an APLY block from raw bytes
    /// bytes: Raw payload data from the block
    /// Returns: Parsed Aply structure or error
    pub fn parseFromBytes(bytes: []const u8) !Aply {
        if (bytes.len < 12) {
            return error.UnexpectedEndOfFile;
        }

        log.debug("Parsing APLY from bytes: {x}", .{bytes});

        var value1: [4]u8 = undefined;
        value1[0] = bytes[0];
        value1[1] = bytes[1];
        value1[2] = bytes[2];
        value1[3] = bytes[3];

        var value2: [4]u8 = undefined;
        value2[0] = bytes[4];
        value2[1] = bytes[5];
        value2[2] = bytes[6];
        value2[3] = bytes[7];

        var value3: [4]u8 = undefined;
        value3[0] = bytes[8];
        value3[1] = bytes[9];
        value3[2] = bytes[10];
        value3[3] = bytes[11];

        return Aply{
            .value1 = value1,
            .value2 = value2,
            .value3 = value3,
        };
    }
};
