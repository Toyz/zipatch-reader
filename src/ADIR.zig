const std = @import("std");
const log = std.log;
const mem = std.mem;
const fs = std.fs;
const fs_path = std.fs.path;
const Allocator = std.mem.Allocator;

/// Represents an Add Directory block in a ZiPatch file
/// Used to create directories during patch application
pub const Adir = struct {
    /// Size of the directory path in bytes
    path_size: u32,
    /// Directory path as a null-terminated string
    path: []u8,

    /// Parses an ADIR block from raw bytes
    /// bytes: Raw payload data from the block
    /// allocator: Memory allocator for path allocation
    /// Returns: Parsed Adir structure or error
    pub fn parseFromBytes(bytes: []const u8, allocator: Allocator) !Adir {
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

        log.debug("Directory path size: {}", .{path_size});

        if (bytes.len < offset + path_size) {
            return error.UnexpectedEndOfFile;
        }

        var path = try allocator.alloc(u8, path_size + 1);
        @memcpy(path[0..path_size], bytes[offset .. offset + path_size]);
        path[path_size] = 0;
        offset += path_size;

        return Adir{
            .path_size = path_size,
            .path = path,
        };
    }

    /// Creates the directory specified in the ADIR block
    /// output_dir: Base output directory where the directory will be created
    /// allocator: Memory allocator for path operations
    /// Returns: void on success or error on failure
    pub fn createDirectory(self: *const Adir, output_dir: []const u8, allocator: Allocator) !void {
        log.info("Creating directory: {s}", .{self.path[0..self.path_size]});

        const output_path = try fs_path.join(allocator, &[_][]const u8{ output_dir, self.path[0..self.path_size] });
        defer allocator.free(output_path);

        fs.cwd().makePath(output_path) catch |err| {
            if (err != error.PathAlreadyExists) {
                log.err("Failed to create directory: {s}, error: {}", .{ output_path, err });
                return err;
            }
            log.info("Directory already exists: {s}", .{output_path});
        };

        log.info("Successfully created directory: {s}", .{output_path});
    }
};
