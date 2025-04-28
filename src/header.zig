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

    /// Converts a 4-byte array to the corresponding BlockType
    /// bytes: 4-byte array containing block type identifier
    /// Returns: The corresponding BlockType or unknown if not recognized
    pub fn fromBytes(bytes: [4]u8) BlockType {
        if (mem.eql(u8, &bytes, "FHDR")) return .FHDR;
        if (mem.eql(u8, &bytes, "APLY")) return .APLY;
        if (mem.eql(u8, &bytes, "APFS")) return .APFS;
        if (mem.eql(u8, &bytes, "ETRY")) return .ETRY;
        if (mem.eql(u8, &bytes, "ADIR")) return .ADIR;
        if (mem.eql(u8, &bytes, "DELD")) return .DELD;
        return .unknown;
    }

    /// Converts a BlockType to its string representation
    /// Returns: String representation of the block type
    pub fn toString(self: BlockType) []const u8 {
        return switch (self) {
            .FHDR => "FHDR",
            .APLY => "APLY",
            .APFS => "APFS",
            .ETRY => "ETRY",
            .ADIR => "ADIR",
            .DELD => "DELD",
            .unknown => "unknown",
        };
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

    /// Reads block information from the provided reader
    /// reader: The reader to read block information from
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
        type_bytes[0] = header_buffer[4];
        type_bytes[1] = header_buffer[5];
        type_bytes[2] = header_buffer[6];
        type_bytes[3] = header_buffer[7];
        const block_type = BlockType.fromBytes(type_bytes);

        return BlockInfo{
            .size = size,
            .block_type = block_type,
            .crc = 0,
        };
    }
};
