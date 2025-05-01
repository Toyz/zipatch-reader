const std = @import("std");
const fs = std.fs;
const log = std.log;
const io = std.io;
const mem = std.mem;
const Allocator = mem.Allocator;
const deflate = std.compress.flate;

/// Represents the mode of a chunk in an ETRY block
pub const ChunkMode = enum(u32) {
    add = 0x41000000,
    delete = 0x44000000,
    modify = 0x4D000000,
    unknown,

    /// Converts a u32 value to the corresponding ChunkMode.
    ///
    /// Parameters:
    ///   value: The u32 value to convert
    ///
    /// Returns: The corresponding ChunkMode
    pub fn fromU32(value: u32) ChunkMode {
        return switch (value) {
            0x41000000 => .add,
            0x44000000 => .delete,
            0x4D000000 => .modify,
            else => .unknown,
        };
    }

    /// Converts a ChunkMode to its string representation.
    ///
    /// Returns: String representation of the chunk mode
    pub fn toString(self: ChunkMode) []const u8 {
        return @tagName(self);
    }
};

/// Represents the compression mode of a chunk in an ETRY block
pub const CompressionMode = enum(u32) {
    none = 0x4E000000,
    zlib = 0x5A000000,
    unknown,

    /// Converts a u32 value to the corresponding CompressionMode.
    ///
    /// Parameters:
    ///   value: The u32 value to convert
    ///
    /// Returns: The corresponding CompressionMode
    pub fn fromU32(value: u32) CompressionMode {
        return switch (value) {
            0x4E000000 => .none,
            0x5A000000 => .zlib,
            else => .unknown,
        };
    }

    /// Converts a CompressionMode to its string representation.
    ///
    /// Returns: String representation of the compression mode
    pub fn toString(self: CompressionMode) []const u8 {
        return @tagName(self);
    }
};

/// Represents a chunk of data in an ETRY block
pub const Chunk = struct {
    /// Operation mode for this chunk (add, delete, modify)
    mode: ChunkMode,

    /// SHA1 hash of the previous version of the file
    prev_hash: [20]u8,

    /// SHA1 hash of the file after this chunk is applied
    next_hash: [20]u8,

    /// Compression mode used for this chunk
    compression_mode: CompressionMode,

    /// Size of the compressed data in bytes
    size: u32,

    /// Size of the file before this chunk is applied
    prev_size: u32,

    /// Size of the file after this chunk is applied
    next_size: u32,

    /// The chunk data (may be compressed)
    data: []u8,

    /// Parses a chunk from raw bytes.
    ///
    /// Parameters:
    ///   bytes: Raw payload data containing the chunk
    ///   allocator: Memory allocator for data allocation
    ///
    /// Returns: Parsed Chunk structure or error
    pub fn parseFromBytes(bytes: []const u8, allocator: Allocator) !Chunk {
        const fixed_size = 4 + 20 + 20 + 4 + 4 + 4 + 4;

        if (bytes.len < fixed_size) {
            return error.UnexpectedEndOfFile;
        }

        var offset: usize = 0;
        var temp_buffer_u32: [4]u8 = undefined;

        @memcpy(&temp_buffer_u32, bytes[offset .. offset + 4]);
        const mode_value = mem.readInt(u32, &temp_buffer_u32, .big);
        const mode = ChunkMode.fromU32(mode_value);
        offset += 4;

        var prev_hash: [20]u8 = undefined;
        @memcpy(&prev_hash, bytes[offset .. offset + 20]);
        offset += 20;

        var next_hash: [20]u8 = undefined;
        @memcpy(&next_hash, bytes[offset .. offset + 20]);
        offset += 20;

        @memcpy(&temp_buffer_u32, bytes[offset .. offset + 4]);
        const compression_mode_value = mem.readInt(u32, &temp_buffer_u32, .big);
        const compression_mode = CompressionMode.fromU32(compression_mode_value);
        offset += 4;

        @memcpy(&temp_buffer_u32, bytes[offset .. offset + 4]);
        const size = mem.readInt(u32, &temp_buffer_u32, .big);
        offset += 4;

        @memcpy(&temp_buffer_u32, bytes[offset .. offset + 4]);
        const prev_size = mem.readInt(u32, &temp_buffer_u32, .big);
        offset += 4;

        @memcpy(&temp_buffer_u32, bytes[offset .. offset + 4]);
        const next_size = mem.readInt(u32, &temp_buffer_u32, .big);
        offset += 4;

        if (bytes.len < offset + size) {
            return error.UnexpectedEndOfFile;
        }

        const data = try allocator.alloc(u8, size);
        @memcpy(data, bytes[offset .. offset + size]);

        return Chunk{
            .mode = mode,
            .prev_hash = prev_hash,
            .next_hash = next_hash,
            .compression_mode = compression_mode,
            .size = size,
            .prev_size = prev_size,
            .next_size = next_size,
            .data = data,
        };
    }

    /// Saves the chunk data to the specified file handle.
    /// Handles different compression modes and returns the data written.
    ///
    /// Parameters:
    ///   file: File handle to write the data to
    ///   allocator: Memory allocator for decompression operations
    ///
    /// Returns: Slice of bytes that were written to the file
    pub fn saveToFileHandle(self: *const Chunk, file: fs.File, allocator: Allocator) ![]u8 {
        switch (self.compression_mode) {
            .none => {
                try file.writeAll(self.data);
                log.info("Wrote {} bytes of uncompressed data", .{self.data.len});

                const data_copy = try allocator.alloc(u8, self.data.len);
                @memcpy(data_copy, self.data);
                return data_copy;
            },
            .zlib => {
                const decompressed_data = self.decompressZlib(allocator) catch |err| {
                    log.err("Failed to decompress ZLIB data: {}", .{err});
                    log.warn("Writing compressed data directly as fallback.", .{});
                    try file.writeAll(self.data);
                    log.info("Wrote {} bytes of compressed data", .{self.data.len});

                    const data_copy = try allocator.alloc(u8, self.data.len);
                    @memcpy(data_copy, self.data);
                    return data_copy;
                };
                defer allocator.free(decompressed_data);

                try file.writeAll(decompressed_data);
                log.info("Wrote {} bytes of decompressed data (from {} compressed bytes)", .{ decompressed_data.len, self.data.len });

                const data_copy = try allocator.alloc(u8, decompressed_data.len);
                @memcpy(data_copy, decompressed_data);
                return data_copy;
            },
            .unknown => {
                return error.UnknownCompressionMode;
            },
        }
    }

    /// Decompresses ZLIB-compressed data in a chunk.
    ///
    /// Parameters:
    ///   allocator: Memory allocator for decompression operations
    ///
    /// Returns: Decompressed data or error
    fn decompressZlib(self: *const Chunk, allocator: Allocator) ![]u8 {
        if (self.compression_mode != .zlib) {
            return error.NotCompressed;
        }

        const decompressed = try allocator.alloc(u8, self.next_size);
        errdefer allocator.free(decompressed);

        if (self.data.len == 0) {
            if (self.next_size == 0) {
                return decompressed;
            }
            return error.InvalidZlibData;
        }

        if (self.data[0] != 0x78) {
            log.warn("Unexpected ZLIB header byte: 0x{X:0>2} (expected 0x78)", .{self.data[0]});
        }

        if (self.data.len < 6) {
            return error.InvalidZlibData;
        }

        const deflate_data = self.data[2 .. self.data.len - 4];
        var deflate_stream = std.io.fixedBufferStream(deflate_data);
        var decompress = deflate.decompressor(deflate_stream.reader());

        const bytes_read = decompress.reader().readAll(decompressed) catch |err| {
            log.err("Failed to decompress ZLIB data: {}", .{err});
            return err;
        };

        if (bytes_read != self.next_size) {
            log.warn("Decompressed size ({}) doesn't match expected size ({})", .{ bytes_read, self.next_size });
            if (bytes_read < self.next_size) {
                log.err("Incomplete decompression result", .{});
            }
            return allocator.realloc(decompressed, bytes_read);
        }

        return decompressed;
    }

    /// Saves the chunk data to the specified file path.
    ///
    /// Parameters:
    ///   output_path: Path to save the chunk data to
    ///   allocator: Memory allocator for file operations
    ///
    /// Returns: void on success or error on failure
    pub fn saveToFile(self: *const Chunk, output_path: []const u8, allocator: Allocator) !void {
        log.info("Saving chunk to file: {s}", .{output_path});

        try createParentDirectories(output_path);

        const file = try fs.cwd().createFile(output_path, .{});
        defer file.close();

        _ = try self.saveToFileHandle(file, allocator);
    }
};

/// Creates parent directories for a file path if they don't exist.
///
/// Parameters:
///   file_path: Path to create parent directories for
///
/// Returns: void on success or error on failure
fn createParentDirectories(file_path: []const u8) !void {
    const dir_path = fs.path.dirname(file_path) orelse return;
    fs.cwd().makePath(dir_path) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };
}

/// Represents an Entry (ETRY) block in a ZiPatch file.
/// Contains file data and metadata for file operations.
pub const Etry = struct {
    /// Size of the file path in bytes
    path_size: u32,

    /// File path as a null-terminated string
    path: []u8,

    /// Number of chunks in this entry
    count: u32,

    /// Array of chunks for this entry
    chunks: []Chunk,

    /// Parses an ETRY block from raw bytes.
    ///
    /// Parameters:
    ///   bytes: Raw payload data from the block
    ///   allocator: Memory allocator for path and chunks allocation
    ///
    /// Returns: Parsed Etry structure or error
    pub fn parseFromBytes(bytes: []const u8, allocator: Allocator) !Etry {
        var offset: usize = 0;
        var temp_buffer_u32: [4]u8 = undefined;

        if (bytes.len < offset + 4) {
            return error.UnexpectedEndOfFile;
        }
        @memcpy(&temp_buffer_u32, bytes[offset .. offset + 4]);
        const path_size = mem.readInt(u32, &temp_buffer_u32, .big);
        offset += 4;

        if (path_size > 1024) {
            log.warn("Path size too large: {}", .{path_size});
            return error.PathSizeTooLarge;
        }

        log.debug("Path size: {}", .{path_size});

        if (bytes.len < offset + path_size) {
            return error.UnexpectedEndOfFile;
        }

        var path = try allocator.alloc(u8, path_size + 1);
        errdefer allocator.free(path);
        @memcpy(path[0..path_size], bytes[offset .. offset + path_size]);
        path[path_size] = 0;
        offset += path_size;

        if (bytes.len < offset + 4) {
            allocator.free(path);
            return error.UnexpectedEndOfFile;
        }

        @memcpy(&temp_buffer_u32, bytes[offset .. offset + 4]);
        const count = mem.readInt(u32, &temp_buffer_u32, .big);
        offset += 4;

        log.debug("Chunk count: {}", .{count});

        var chunks = try allocator.alloc(Chunk, count);
        errdefer {
            for (chunks) |chunk| {
                if (chunk.data.len > 0) allocator.free(chunk.data);
            }
            allocator.free(chunks);
        }

        if (count > 0) {
            var remaining_data = bytes[offset..];
            var chunk_offset: usize = 0;

            for (0..count) |i| {
                const chunk_header_size = 4 + 20 + 20 + 4 + 4 + 4 + 4;

                if (remaining_data.len < chunk_offset + chunk_header_size) {
                    allocator.free(path);
                    allocator.free(chunks);
                    return error.UnexpectedEndOfFile;
                }

                var size_bytes: [4]u8 = undefined;
                @memcpy(&size_bytes, remaining_data[chunk_offset + 48 .. chunk_offset + 52]);
                const chunk_size = mem.readInt(u32, &size_bytes, .big);

                if (remaining_data.len < chunk_offset + chunk_header_size + chunk_size) {
                    allocator.free(path);
                    allocator.free(chunks);
                    return error.UnexpectedEndOfFile;
                }

                chunks[i] = try Chunk.parseFromBytes(remaining_data[chunk_offset .. chunk_offset + chunk_header_size + chunk_size], allocator);

                chunk_offset += chunk_header_size + chunk_size;
            }
        }

        return Etry{
            .path_size = path_size,
            .path = path,
            .count = count,
            .chunks = chunks,
        };
    }

    /// Saves all chunks to the specified output directory.
    /// Combines chunks into a single file and verifies the SHA1 hash.
    ///
    /// Parameters:
    ///   output_dir: Base output directory to save files to
    ///   allocator: Memory allocator for file operations
    ///
    /// Returns: void on success or error on failure
    pub fn saveAllChunks(self: *const Etry, output_dir: []const u8, allocator: Allocator) !void {
        if (self.chunks.len == 0) {
            log.warn("No chunks to save for path: {s}", .{self.path[0..self.path_size]});
            return;
        }

        log.info("Building output path with: base={s}, file={s}", .{ output_dir, self.path[0..self.path_size] });

        const output_path = try fs.path.join(allocator, &[_][]const u8{ output_dir, self.path[0..self.path_size] });
        defer allocator.free(output_path);

        log.info("Processing chunks for file: {s}", .{output_path});

        if (self.chunks[0].mode == .delete) {
            log.info("Delete operation detected for file: {s}", .{output_path});

            fs.cwd().deleteFile(output_path) catch |err| {
                if (err == error.FileNotFound) {
                    log.warn("File not found: {s}", .{output_path});
                    log.info("Extracted file: {s}", .{self.path[0..self.path_size]});
                    return;
                }
                log.err("Failed to delete file: {s}, error: {}", .{ output_path, err });
                return err;
            };

            log.info("File successfully deleted: {s}", .{output_path});
            log.info("Extracted file: {s}", .{self.path[0..self.path_size]});
            return;
        }

        try createParentDirectories(output_path);

        if (self.chunks[0].mode == .modify) {
            log.info("Modify operation detected for file: {s}", .{output_path});

            if (!try verifyExistingFileHash(output_path, &self.chunks[0].prev_hash, allocator)) {
                log.warn("Cannot modify file: {s}, hash verification failed or file not found", .{output_path});
                log.warn("Will proceed with modification, but result may be incorrect", .{});
            } else {
                log.info("Existing file hash verified for modification: {s}", .{output_path});
            }
        } else if (self.chunks[0].mode == .add) {
            log.info("Add operation detected for file: {s}", .{output_path});

            const file_exists = check_file_exists: {
                const file = fs.cwd().openFile(output_path, .{}) catch |err| {
                    if (err == error.FileNotFound) {
                        break :check_file_exists false;
                    }
                    log.err("Failed to open file: {s}, error: {}", .{ output_path, err });
                    return err;
                };
                defer file.close();
                break :check_file_exists true;
            };

            if (file_exists) {
                log.warn("File already exists for ADD operation: {s}, it will be overwritten", .{output_path});
            }
        } else {
            log.warn("Unknown operation mode: {s} for file: {s}", .{ self.chunks[0].mode.toString(), output_path });
        }

        const file = try fs.cwd().createFile(output_path, .{});
        defer file.close();

        var all_data = std.ArrayList(u8).init(allocator);
        defer all_data.deinit();

        for (self.chunks, 0..) |chunk, i| {
            log.info("Processing chunk {}/{} (mode: {s}) for file: {s}", .{ i + 1, self.chunks.len, chunk.mode.toString(), output_path });

            if (chunk.size == 0) {
                log.info("Skipping chunk with size 0", .{});
                continue;
            }

            const chunk_data = try chunk.saveToFileHandle(file, allocator);
            defer allocator.free(chunk_data);

            try all_data.appendSlice(chunk_data);
        }

        if (self.chunks.len > 0 and self.chunks[0].mode != .delete) {
            const last_chunk = self.chunks[self.chunks.len - 1];
            log.info("Verifying SHA1 hash for file: {s}", .{output_path});

            var sha1 = std.crypto.hash.Sha1.init(.{});
            sha1.update(all_data.items);
            var file_hash: [20]u8 = undefined;
            sha1.final(&file_hash);

            if (!mem.eql(u8, &file_hash, &last_chunk.next_hash)) {
                const is_empty_file_zero_hash = all_data.items.len == 0;
                var is_zero_hash = true;
                for (last_chunk.next_hash) |b| {
                    if (b != 0) {
                        is_zero_hash = false;
                        break;
                    }
                }

                if (!is_empty_file_zero_hash or !is_zero_hash) {
                    log.err("Final hash verification failed for file: {s}", .{output_path});
                    log.err("Expected next hash: {X}", .{std.fmt.fmtSliceHexUpper(&last_chunk.next_hash)});
                    log.err("Got: {X}", .{std.fmt.fmtSliceHexUpper(&file_hash)});
                    return error.HashVerificationFailed;
                }
            }

            log.info("Final hash verification successful for file: {s}", .{output_path});
        }

        log.info("Successfully saved file: {s}", .{output_path});
    }

    /// Verifies that an existing file matches the expected hash
    /// Returns true if either:
    /// 1. The file exists and its hash matches the expected hash
    /// 2. The expected hash is all zeros (indicating new file) and the file doesn't exist
    ///
    /// Parameters:
    ///   file_path: Path to the file to verify
    ///   expected_hash: Expected SHA1 hash of the file
    ///   allocator: Memory allocator for file operations
    ///
    /// Returns: true if the conditions above are met, false otherwise
    fn verifyExistingFileHash(file_path: []const u8, expected_hash: *const [20]u8, allocator: Allocator) !bool {
        var is_zero_hash = true;
        for (expected_hash) |b| {
            if (b != 0) {
                is_zero_hash = false;
                break;
            }
        }

        const file = fs.cwd().openFile(file_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                if (is_zero_hash) {
                    return true;
                }
                log.warn("File not found: {s}", .{file_path});
                return false;
            }
            return err;
        };
        defer file.close();

        if (is_zero_hash) {
            log.warn("File exists but expected new file (zero hash): {s}", .{file_path});
            return false;
        }

        const file_size = try file.getEndPos();
        if (file_size > 100 * 1024 * 1024) {
            log.warn("File too large to verify hash: {s} ({} bytes)", .{ file_path, file_size });
            return false;
        }

        const file_data = try allocator.alloc(u8, @intCast(file_size));
        defer allocator.free(file_data);

        const bytes_read = try file.readAll(file_data);
        if (bytes_read != file_size) {
            log.warn("Failed to read entire file: {s}", .{file_path});
            return false;
        }

        var sha1 = std.crypto.hash.Sha1.init(.{});
        sha1.update(file_data);
        var file_hash: [20]u8 = undefined;
        sha1.final(&file_hash);

        if (!mem.eql(u8, &file_hash, expected_hash)) {
            log.warn("Previous hash mismatch for file: {s}", .{file_path});
            log.warn("Expected previous hash: {s}", .{std.fmt.fmtSliceHexUpper(expected_hash)});
            log.warn("Got: {s}", .{std.fmt.fmtSliceHexUpper(&file_hash)});
            return false;
        }

        log.info("Previous hash verified for file: {s}", .{file_path});
        return true;
    }
};
