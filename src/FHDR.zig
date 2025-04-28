const std = @import("std");
const log = std.log;
const io = std.io;
const mem = std.mem;

/// Represents the result type in the FHDR block
pub const FhdrResultType = enum {
    diff,
    hist,
    unknown,

    /// Converts a 4-byte array to the corresponding FhdrResultType.
    ///
    /// Parameters:
    ///   bytes: 4-byte array containing result type identifier
    ///
    /// Returns: The corresponding FhdrResultType or unknown if not recognized
    pub fn fromBytes(bytes: [4]u8) FhdrResultType {
        if (mem.eql(u8, &bytes, "DIFF")) {
            return .diff;
        } else if (mem.eql(u8, &bytes, "HIST")) {
            return .hist;
        }

        return .unknown;
    }

    /// Converts an FhdrResultType to its string representation.
    ///
    /// Returns: String representation of the result type
    pub fn toString(self: FhdrResultType) []const u8 {
        return @tagName(self);
    }
};

/// Represents a File Header (FHDR) block in a ZiPatch file.
/// Contains version and file count information for the patch.
pub const Fhdr = struct {
    /// Version information for the patch
    version: [4]u8,

    /// Type of result (diff or hist)
    result: FhdrResultType,

    /// Number of entry files in the patch
    number_entry_file: u32,

    /// Number of directory add operations in the patch
    number_add_dir: u32,

    /// Number of directory delete operations in the patch
    number_delete_dir: u32,

    /// Parses an FHDR block from raw bytes.
    ///
    /// Parameters:
    ///   bytes: Raw payload data from the block
    ///
    /// Returns: Parsed Fhdr structure or error
    pub fn parseFromBytes(bytes: []const u8) !Fhdr {
        if (bytes.len < 20) {
            return error.UnexpectedEndOfFile;
        }
        log.debug("Parsing FHDR from bytes: {x}", .{bytes});

        var version: [4]u8 = undefined;
        var result_bytes: [4]u8 = undefined;

        @memcpy(&version, bytes[0..4]);
        @memcpy(&result_bytes, bytes[4..8]);

        const number_entry_file = mem.readInt(u32, bytes[8..12], .big);
        const number_add_dir = mem.readInt(u32, bytes[12..16], .big);
        const number_delete_dir = mem.readInt(u32, bytes[16..20], .big);

        return Fhdr{
            .version = version,
            .result = FhdrResultType.fromBytes(result_bytes),
            .number_entry_file = number_entry_file,
            .number_add_dir = number_add_dir,
            .number_delete_dir = number_delete_dir,
        };
    }
};
