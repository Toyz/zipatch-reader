const std = @import("std");
const io = std.io;
const mem = std.mem;

/// Represents the different block types in a ZiPatch file
pub const BlockType = enum(u32) {
    FHDR,
    APLY,
    APFS,
    ETRY,
    ADIR,
    DELD,
    unknown,

    /// Converts a 4-byte array to the corresponding BlockType.
    ///
    /// Parameters:
    ///   bytes: 4-byte array containing block type identifier
    ///
    /// Returns: The corresponding BlockType or unknown if not recognized
    pub fn fromBytes(bytes: [4]u8) BlockType {
        const value = mem.readInt(u32, &bytes, .big);

        return switch (value) {
            0x46484452 => .FHDR,
            0x41504C59 => .APLY,
            0x41504653 => .APFS,
            0x45545259 => .ETRY,
            0x41444952 => .ADIR,
            0x44454C44 => .DELD,
            else => .unknown,
        };
    }

    /// Converts a BlockType to its string representation.
    ///
    /// Returns: String representation of the block type
    pub fn toString(self: BlockType) []const u8 {
        return @tagName(self);
    }
};

/// Contains information about a block in the ZiPatch file
pub const BlockInfo = struct {
    /// Size of the block payload in bytes
    size: u32,

    /// Type of the block
    block_type: BlockType,

    /// CRC checksum for the block
    crc: u32,

    /// Reads block information from the provided reader.
    ///
    /// Parameters:
    ///   reader: The reader to read block information from
    ///
    /// Returns: BlockInfo structure or error
    pub fn read(reader: anytype) !BlockInfo {
        var header_buffer: [8]u8 = undefined;
        const bytes_read = reader.read(&header_buffer) catch |err| {
            if (err == error.EndOfStream) {
                return error.EndOfStream;
            }
            return err;
        };

        if (bytes_read < 8) {
            return error.UnexpectedEndOfFile;
        }

        const size = mem.readInt(u32, header_buffer[0..4], .big);

        var type_bytes: [4]u8 = undefined;
        @memcpy(&type_bytes, header_buffer[4..8]);
        const block_type = BlockType.fromBytes(type_bytes);

        return BlockInfo{
            .size = size,
            .block_type = block_type,
            .crc = 0,
        };
    }
};
