const std = @import("std");
const fs = std.fs;
const fs_path = fs.path;
const io = std.io;
const mem = std.mem;
const heap = std.heap;
const Allocator = mem.Allocator;
const log = std.log;
const process = std.process;

const clap = @import("clap");

const Adir = @import("ADIR.zig").Adir;
const Aply = @import("APLY.zig").Aply;
const Chunk = @import("ETRY.zig").Chunk;
const Deld = @import("DELD.zig").Deld;
const Etry = @import("ETRY.zig").Etry;
const Fhdr = @import("FHDR.zig").Fhdr;
const header = @import("header.zig");
const BlockType = header.BlockType;
const BlockInfo = header.BlockInfo;

/// Magic number identifying a ZiPatch file (12 bytes)
/// 91 5A 49 50 41 54 43 48 0D 0A 1A 0A (SQ ZIPATCH sequence + CR LF SUB LF)
const ZipatchFileMagic = [_]u8{ 0x91, 'Z', 'I', 'P', 'A', 'T', 'C', 'H', 0x0D, 0x0A, 0x1A, 0x0A };

/// Set the default log level to "info"
pub const default_level: std.log.Level = switch (std.builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe => .notice,
    .ReleaseFast => .info,
    .ReleaseSmall => .info,
};

/// Set the default log level to "info" for all loggers
pub const log_level: std.log.Level = .info;

/// Main entry point for the ZiPatch reader application
pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    try handleCommandLineArgs(allocator);
}

/// Handles command line argument parsing and execution
fn handleCommandLineArgs(allocator: Allocator) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help              Display this help message and exit.
        \\-f, --file <str>        Path to the ZiPatch file to process.
        \\-o, --output <str>      Output directory for extracted files.
        \\-x, --extract           Extract files from the patch.
        \\-d, --directory <str>   Process all .patch files in the specified directory.
        \\-r, --recursive         Recursively search for .patch files in subdirectories.
        \\-t, --table             Display a table of all files in the patch.
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try printUsage();
        return;
    }

    const options = ExtractOptions{
        .file_path = if (res.args.file) |f| f else "D2010.09.18.0000.patch",
        .output_dir = if (res.args.output) |o| o else "output",
        .extract_files = res.args.extract != 0,
        .recursive_search = res.args.recursive != 0,
        .process_directory = res.args.directory,
        .show_table = res.args.table != 0,
    };

    try createOutputDir(options.output_dir);

    if (options.process_directory) |dir_path| {
        try processAllPatchesInDirectory(dir_path, options.output_dir, options.extract_files, options.recursive_search, allocator);
    } else {
        try processPatchFile(options.file_path, options.output_dir, options.extract_files, options, allocator);
    }

    log.info("All operations completed successfully.", .{});
}

const ExtractOptions = struct {
    file_path: []const u8,
    output_dir: []const u8,
    extract_files: bool,
    recursive_search: bool,
    process_directory: ?[]const u8,
    show_table: bool,
};

fn createOutputDir(output_dir: []const u8) !void {
    log.info("Extracting files to: {s}", .{output_dir});

    fs.cwd().makeDir(output_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            log.err("Failed to create output directory: {s}", .{output_dir});
            return err;
        }
    };
}

fn processPatchFile(file_path: []const u8, output_dir: []const u8, extract_files: bool, options: ExtractOptions, allocator: Allocator) !void {
    log.info("Processing file: {s}", .{file_path});

    const file = fs.cwd().openFile(file_path, .{ .mode = .read_only }) catch |err| {
        log.err("Failed to open file: {s}, error: {}", .{ file_path, err });
        return err;
    };
    defer file.close();

    try verifyZipatchMagic(file, file_path);

    try processZipatchBlocks(file, file_path, output_dir, extract_files, options.show_table, allocator);

    log.info("Finished processing file: {s}", .{file_path});
}

fn verifyZipatchMagic(file: fs.File, file_path: []const u8) !void {
    const reader = file.reader();

    var header_buffer: [12]u8 = undefined;
    const bytes_read_header = try reader.readAll(&header_buffer);

    if (bytes_read_header < 12) {
        log.err("File '{s}' is too short to contain a header.", .{file_path});
        return error.UnexpectedEndOfFile;
    }

    if (!mem.eql(u8, &header_buffer, &ZipatchFileMagic)) {
        log.err("File '{s}' header does not contain the expected ZiPatch file type sequence.", .{file_path});
        log.err("Header read: {any}", .{std.fmt.fmtSliceHexUpper(&header_buffer)});
        log.err("Expected: {any}", .{std.fmt.fmtSliceHexUpper(&ZipatchFileMagic)});
        return error.InvalidMagicNumber;
    }

    log.info("Successfully verified ZiPatch file type header.", .{});
}

fn processZipatchBlocks(file: fs.File, file_path: []const u8, output_dir: []const u8, extract_files: bool, show_table: bool, allocator: Allocator) !void {
    _ = file_path;
    const reader = file.reader();
    const file_size = try file.getEndPos();

    var entries = std.ArrayList(Etry).init(allocator);
    defer {
        for (entries.items) |*etry| {
            for (etry.chunks) |chunk| {
                allocator.free(chunk.data);
            }
            allocator.free(etry.chunks);
            allocator.free(etry.path);
        }
        entries.deinit();
    }

    var current_size: usize = 12;

    while (current_size < file_size) {
        var block_info = BlockInfo.read(reader) catch |err| {
            switch (err) {
                error.EndOfStream => {
                    log.info("End of stream reached while reading BlockInfo.", .{});
                    break;
                },
                error.UnexpectedEndOfFile => {
                    log.err("Unexpected end of file while reading BlockInfo.", .{});
                    break;
                },
                else => {
                    log.err("Failed to read BlockInfo: {any}", .{err});
                    return err;
                },
            }
        };

        if (block_info.block_type == .unknown) {
            log.err("Unknown block type found: {s} (Size: {})", .{ block_info.block_type.toString(), block_info.size });
            return error.UnknownBlockType;
        }

        log.info("Found block type: {s}, Size: {}", .{ block_info.block_type.toString(), block_info.size });
        try processBlockPayload(reader, &block_info, output_dir, extract_files, show_table, &entries, allocator);
        log.info("Processed block type: {s}, CRC: {d}", .{ block_info.block_type.toString(), block_info.crc });

        // Update current_size: 8 bytes for block header + payload size + 4 bytes for CRC
        current_size += 8 + block_info.size + 4;

        if (current_size >= file_size) {
            log.info("Reached end of file at position {}", .{current_size});
            break;
        }
    }

    if (current_size != file_size) {
        log.err("File size mismatch: expected {d}, got {d}", .{ file_size, current_size });
        return error.FileSizeMismatch;
    }

    if (show_table and entries.items.len > 0) {
        try displayEtryTable(&entries, allocator);
    }
}

fn processBlockPayload(reader: anytype, block_info: *BlockInfo, output_dir: []const u8, extract_files: bool, show_table: bool, entries: *std.ArrayList(Etry), allocator: Allocator) !void {
    const payload_size = block_info.size;
    const payload_buffer = try allocator.alloc(u8, payload_size);
    defer allocator.free(payload_buffer);

    const bytes_read_payload = try reader.readAll(payload_buffer);

    if (bytes_read_payload < payload_size) {
        log.err("Unexpected end of file while reading payload for block type {s}.", .{block_info.block_type.toString()});
        return error.UnexpectedEndOfFile;
    }

    switch (block_info.block_type) {
        .FHDR => {
            const fhdr = try Fhdr.parseFromBytes(payload_buffer);
            log.info("FHDR block data: {any}", .{fhdr});
        },
        .APLY => {
            const aply = try Aply.parseFromBytes(payload_buffer);
            log.info("APLY block data: {any}", .{aply});
        },
        .ADIR => {
            var adir = try Adir.parseFromBytes(payload_buffer, allocator);
            defer allocator.free(adir.path);
            log.info("ADIR block: Create directory: {s}", .{adir.path[0..adir.path_size]});
            if (extract_files) {
                try adir.createDirectory(output_dir, allocator);
            }
        },
        .DELD => {
            var deld = try Deld.parseFromBytes(payload_buffer, allocator);
            defer allocator.free(deld.path);
            log.info("DELD block: Delete directory: {s}", .{deld.path[0..deld.path_size]});
            if (extract_files) {
                try deld.deleteDirectory(output_dir, allocator);
            }
        },
        .ETRY => {
            var etry = try Etry.parseFromBytes(payload_buffer, allocator);
            errdefer {
                allocator.free(etry.path);
                for (etry.chunks) |chunk| {
                    if (chunk.data.len > 0) allocator.free(chunk.data);
                }
                allocator.free(etry.chunks);
            }

            log.info("ETRY block: Path: {s}, Size: {}, Chunks: {}", .{ etry.path[0..etry.path_size], etry.path_size, etry.count });

            if (show_table and etry.chunks.len > 0) {
                try entries.append(etry);
            } else {
                defer {
                    allocator.free(etry.path);
                    for (etry.chunks) |chunk| {
                        if (chunk.data.len > 0) allocator.free(chunk.data);
                    }
                    allocator.free(etry.chunks);
                }

                if (extract_files) {
                    log.info("Attempting to extract file: {s} with {} chunks", .{ etry.path[0..etry.path_size], etry.chunks.len });
                    if (etry.chunks.len == 0) {
                        log.warn("No chunks found for file: {s}", .{etry.path[0..etry.path_size]});
                    } else {
                        try etry.saveAllChunks(output_dir, allocator);
                        log.info("Extracted file: {s}", .{etry.path[0..etry.path_size]});
                    }
                }
            }
        },
        .APFS => {
            log.info("Payload data read for APFS block. No specific processing implemented.", .{});
        },
        .unknown => {
            log.info("Payload data read for unknown block type. No specific processing implemented.", .{});
        },
    }

    try processCrc(reader, block_info);
}

fn processCrc(reader: anytype, block_info: *BlockInfo) !void {
    var crc_buffer: [4]u8 = undefined;
    const bytes_read_crc = try reader.readAll(&crc_buffer);

    if (bytes_read_crc < 4) {
        log.err("Unexpected end of file while reading CRC for block type {s}.", .{block_info.block_type.toString()});
        return error.UnexpectedEndOfFile;
    }

    block_info.crc = mem.readInt(u32, crc_buffer[0..4], .big);
    log.debug("Read CRC for block type {s}: 0x{X:0>8}", .{ block_info.block_type.toString(), block_info.crc });
}

fn processAllPatchesInDirectory(dir_path: []const u8, output_dir: []const u8, extract_files: bool, recursive_search: bool, allocator: Allocator) !void {
    log.info("Searching for .patch files in directory: {s}", .{dir_path});

    var dir = fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        log.err("Failed to open directory: {s}, error: {}", .{ dir_path, err });
        return err;
    };
    defer dir.close();

    var it = dir.iterate();
    var patch_count: usize = 0;

    const options = ExtractOptions{
        .file_path = "",
        .output_dir = output_dir,
        .extract_files = extract_files,
        .recursive_search = recursive_search,
        .process_directory = null,
        .show_table = false,
    };

    while (try it.next()) |entry| {
        if (entry.kind == .directory and recursive_search) {
            const subdir_path = try fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
            defer allocator.free(subdir_path);

            processAllPatchesInDirectory(subdir_path, output_dir, extract_files, recursive_search, allocator) catch |err| {
                log.err("Failed to process subdirectory: {s}, error: {}", .{ subdir_path, err });
            };
            continue;
        }

        if (entry.kind != .file) continue;

        if (!mem.endsWith(u8, entry.name, ".patch")) continue;

        const file_path = try fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
        defer allocator.free(file_path);

        log.info("Found patch file: {s}", .{entry.name});
        patch_count += 1;

        var file_options = options;
        file_options.file_path = file_path;

        processPatchFile(file_path, output_dir, extract_files, file_options, allocator) catch |err| {
            log.err("Failed to process patch file: {s}, error: {}", .{ file_path, err });
        };
    }

    log.info("Processed {d} patch files from directory: {s}", .{ patch_count, dir_path });

    if (patch_count == 0) {
        log.warn("No .patch files found in directory: {s}", .{dir_path});
    }
}

/// Formats and displays ETRY information in a table
fn displayEtryTable(entries: *const std.ArrayList(Etry), allocator: Allocator) !void {
    const stdout = std.io.getStdOut();
    var bw = std.io.bufferedWriter(stdout.writer());
    const writer = bw.writer();

    try writer.print("\nFiles in patch: {d}\n", .{entries.items.len});

    if (entries.items.len == 0) {
        try writer.writeAll("No files found in the patch.\n");
        try bw.flush();
        return;
    }

    var max_path_len: usize = 9;
    for (entries.items) |etry| {
        max_path_len = @max(max_path_len, etry.path_size);
    }
    max_path_len += 2;

    try writer.writeAll("INDEX | FILE PATH");
    for (0..max_path_len - 9) |_| try writer.writeByte(' ');
    try writer.writeAll(" | SIZE       | CHUNKS | MODE   | PREV HASH                               | NEXT HASH\n");

    try writer.writeAll("------+");
    for (0..max_path_len + 2) |_| try writer.writeByte('-');
    try writer.writeAll("+------------+--------+--------+----------------------------------------+----------------------------------------\n");

    for (entries.items, 0..) |etry, index| {
        if (etry.chunks.len == 0) continue;

        const first_chunk = etry.chunks[0];
        const last_chunk = etry.chunks[etry.chunks.len - 1];

        const prev_hash_str = try std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexUpper(&first_chunk.prev_hash)});
        defer allocator.free(prev_hash_str);

        const next_hash_str = try std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexUpper(&last_chunk.next_hash)});
        defer allocator.free(next_hash_str);

        const size_str = try formatSize(last_chunk.next_size, allocator);
        defer allocator.free(size_str);

        try writer.print("{d:5} | ", .{index});

        try writer.writeAll(etry.path[0..etry.path_size]);
        for (0..max_path_len - etry.path_size) |_| try writer.writeByte(' ');

        try writer.print(" | {s:10} | {d:6} | {s:6} | {s:38} | {s:38}\n", .{
            size_str,
            etry.chunks.len,
            first_chunk.mode.toString(),
            prev_hash_str,
            next_hash_str,
        });
    }

    try writer.writeAll("\n");
    try bw.flush();
}

/// Formats a byte size into a human-readable string (B, KB, MB, GB)
fn formatSize(size: u64, allocator: Allocator) ![]const u8 {
    const units = [_][]const u8{ "B", "KB", "MB", "GB", "TB" };
    var size_f: f64 = @floatFromInt(size);
    var unit_index: usize = 0;

    while (size_f >= 1024.0 and unit_index < units.len - 1) {
        size_f /= 1024.0;
        unit_index += 1;
    }

    if (unit_index == 0) {
        return std.fmt.allocPrint(allocator, "{d} {s}", .{ @as(u64, @intFromFloat(size_f)), units[unit_index] });
    } else {
        if (size_f < 10) {
            return std.fmt.allocPrint(allocator, "{d:.1} {s}", .{ size_f, units[unit_index] });
        } else {
            return std.fmt.allocPrint(allocator, "{d:.0} {s}", .{ size_f, units[unit_index] });
        }
    }
}

fn printUsage() !void {
    const usage =
        \\Usage: zipatch_reader [options]
        \\
        \\Options:
        \\  -h, --help              Display this help message
        \\  -f, --file <path>       Path to the ZiPatch file (default: D2010.09.18.0000.patch)
        \\  -o, --output <dir>      Output directory for extracted files (default: output)
        \\  -x, --extract           Extract files from the patch
        \\  -d, --directory <path>  Process all .patch files in the specified directory
        \\  -r, --recursive         Recursively search for .patch files in subdirectories
        \\  -t, --table             Display a table of all files in the patch
        \\
    ;
    try io.getStdOut().writer().print("{s}", .{usage});
}
