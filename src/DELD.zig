const std = @import("std");
const fs = std.fs;
const log = std.log;
const mem = std.mem;
const Allocator = mem.Allocator;

/// Represents a Delete Directory (DELD) block in a ZiPatch file.
/// Used to remove directories during patch application.
pub const Deld = struct {
    /// Size of the directory path in bytes
    path_size: u32,

    /// Directory path as a null-terminated string
    path: []u8,

    /// Parses a DELD block from raw bytes.
    ///
    /// Parameters:
    ///   bytes: Raw payload data from the block
    ///   allocator: Memory allocator for path allocation
    ///
    /// Returns: Parsed Deld structure or error
    pub fn parseFromBytes(bytes: []const u8, allocator: Allocator) !Deld {
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

        return Deld{
            .path_size = path_size,
            .path = path,
        };
    }

    /// Deletes the directory specified in the DELD block if it exists.
    ///
    /// Parameters:
    ///   output_dir: Base output directory where the directory should be deleted from
    ///   allocator: Memory allocator for path operations
    ///
    /// Returns: void on success or error on failure
    pub fn deleteDirectory(self: *const Deld, output_dir: []const u8, allocator: Allocator) !void {
        log.info("Deleting directory: {s}", .{self.path[0..self.path_size]});

        const output_path = try fs.path.join(allocator, &[_][]const u8{ output_dir, self.path[0..self.path_size] });
        defer allocator.free(output_path);

        log.info("Deleting path: {s}", .{output_path});

        var dir = fs.cwd().openDir(output_path, .{}) catch |err| {
            if (err == error.FileNotFound or err == error.PathNotFound) {
                log.info("Directory not found: {s}", .{output_path});
                return;
            }

            if (err == error.NotDir) {
                log.info("Path is a file, deleting file: {s}", .{output_path});
                fs.cwd().deleteFile(output_path) catch |file_err| {
                    log.err("Failed to delete file: {s}, error: {}", .{ output_path, file_err });
                    return file_err;
                };
                log.info("Successfully deleted file: {s}", .{output_path});
                return;
            }

            log.err("Failed to open directory: {s}, error: {}", .{ output_path, err });
            return err;
        };
        defer dir.close();

        try deleteDirectoryRecursively(output_path, allocator);
        log.info("Successfully deleted directory and its contents: {s}", .{output_path});
    }
};

/// Recursively deletes a directory and all its contents.
///
/// Parameters:
///   path: Path to the directory to delete
///   allocator: Memory allocator for path operations
///
/// Returns: void on success or error on failure
fn deleteDirectoryRecursively(path: []const u8, allocator: Allocator) !void {
    var dir = fs.cwd().openDir(path, .{ .iterate = true }) catch |err| {
        log.err("Failed to open directory for deletion: {s}, error: {}", .{ path, err });
        return err;
    };
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        const entry_path = try fs.path.join(allocator, &[_][]const u8{ path, entry.name });
        defer allocator.free(entry_path);

        switch (entry.kind) {
            .file => {
                dir.deleteFile(entry.name) catch |err| {
                    log.err("Failed to delete file: {s}, error: {}", .{ entry_path, err });
                };
            },
            .directory => {
                try deleteDirectoryRecursively(entry_path, allocator);
            },
            else => {
                log.warn("Skipping non-file/directory entry: {s}", .{entry_path});
            },
        }
    }

    fs.cwd().deleteDir(path) catch |err| {
        log.err("Failed to delete directory after emptying: {s}, error: {}", .{ path, err });
        return err;
    };
}
