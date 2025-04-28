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
pub const log_level: std.log.Level = .info;

/// Main entry point for the ZiPatch reader application
pub fn main() !void {
    // Set up allocator
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Define and parse command line arguments
    try handleCommandLineArgs(allocator);
}

/// Handles command line argument parsing and execution
fn handleCommandLineArgs(allocator: Allocator) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help              Display this help message and exit.
        \\-f, --file <str>        Path to the ZiPatch file to process.
        \\-o, --output <str>      Output directory for extracted files.
        \\-x, --extract           Extract files from the patch.
        \\-v, --verbose           Enable verbose output.
        \\-d, --directory <str>   Process all .patch files in the specified directory.
        \\-r, --recursive         Recursively search for .patch files in subdirectories.
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

    // Display help if requested
    if (res.args.help != 0) {
        try printUsage();
        return;
    }

    // Initialize options with defaults
    const options = ExtractOptions{
        .file_path = if (res.args.file) |f| f else "D2010.09.18.0000.patch",
        .output_dir = if (res.args.output) |o| o else "output",
        .extract_files = true,
        .verbose = res.args.verbose != 0,
        .recursive_search = res.args.recursive != 0,
        .process_directory = res.args.directory,
    };

    // Create output directory
    try createOutputDir(options.output_dir);

    // Process files based on options
    if (options.process_directory) |dir_path| {
        try processAllPatchesInDirectory(dir_path, options.output_dir, options.extract_files, options.verbose, options.recursive_search, allocator);
    } else {
        try processPatchFile(options.file_path, options.output_dir, options.extract_files, options.verbose, allocator);
    }

    log.info("All operations completed successfully.", .{});
}

/// Options for extracting ZiPatch files
const ExtractOptions = struct {
    file_path: []const u8,
    output_dir: []const u8,
    extract_files: bool,
    verbose: bool,
    recursive_search: bool,
    process_directory: ?[]const u8,
};

/// Creates the output directory if it doesn't exist
fn createOutputDir(output_dir: []const u8) !void {
    log.info("Extracting files to: {s}", .{output_dir});

    fs.cwd().makeDir(output_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            log.err("Failed to create output directory: {s}", .{output_dir});
            return err;
        }
    };
}

/// Processes a single ZiPatch file
fn processPatchFile(file_path: []const u8, output_dir: []const u8, extract_files: bool, verbose: bool, allocator: Allocator) !void {
    log.info("Processing file: {s}", .{file_path});

    const file = fs.cwd().openFile(file_path, .{ .mode = .read_only }) catch |err| {
        log.err("Failed to open file: {s}, error: {}", .{ file_path, err });
        return err;
    };
    defer file.close();

    try verifyZipatchMagic(file, file_path);
    try processZipatchBlocks(file, file_path, output_dir, extract_files, verbose, allocator);

    log.info("Finished processing file: {s}", .{file_path});
}

/// Verifies the ZiPatch file magic number
fn verifyZipatchMagic(file: fs.File, file_path: []const u8) !void {
    const reader = file.reader();

    var header_buffer: [12]u8 = undefined;
    const bytes_read_header = try reader.readAll(&header_buffer);

    if (bytes_read_header < 12) {
        log.err("File '{s}' is too short to contain a header.", .{file_path});
        return error.UnexpectedEndOfFile;
    }

    // Compare the entire header buffer with ZipatchFileMagic
    if (!mem.eql(u8, &header_buffer, &ZipatchFileMagic)) {
        log.err("File '{s}' header does not contain the expected ZiPatch file type sequence.", .{file_path});
        log.err("Header read: {any}", .{std.fmt.fmtSliceHexUpper(&header_buffer)});
        log.err("Expected: {any}", .{std.fmt.fmtSliceHexUpper(&ZipatchFileMagic)});
        return error.InvalidMagicNumber;
    }

    log.info("Successfully verified ZiPatch file type header.", .{});
}

/// Processes the blocks in a ZiPatch file
fn processZipatchBlocks(file: fs.File, file_path: []const u8, output_dir: []const u8, extract_files: bool, verbose: bool, allocator: Allocator) !void {
    _ = file_path; // autofix
    const reader = file.reader();

    while (true) {
        if (verbose) {
            log.debug("Reader position before reading BlockInfo: {}", .{try file.getPos()});
        }

        const block_info = BlockInfo.read(reader) catch |err| {
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

        if (verbose) {
            log.debug("Reader position after reading BlockInfo: {}", .{try file.getPos()});
        }

        if (block_info.block_type == .unknown) {
            log.err("Unknown block type found: {s} (Size: {})", .{ block_info.block_type.toString(), block_info.size });
            return error.UnknownBlockType;
        }

        log.info("Found block type: {s}, Size: {}", .{ block_info.block_type.toString(), block_info.size });

        try processBlockPayload(reader, block_info, output_dir, extract_files, verbose, allocator);
    }
}

/// Block handler interface for processing different block types
const BlockHandler = struct {
    /// Type of data this handler processes
    type: BlockType,

    /// Function to parse and process block payload
    processPayloadFn: *const fn (payload: []const u8, output_dir: []const u8, extract_files: bool, verbose: bool, allocator: Allocator) anyerror!void,

    /// Name of the block type (for logging)
    name: []const u8,
};

/// Comptime map of block types to their handlers
const block_handlers = blk: {
    const handlers = [_]BlockHandler{
        // FHDR handler
        .{
            .type = .FHDR,
            .name = "FHDR",
            .processPayloadFn = struct {
                fn process(payload: []const u8, _: []const u8, _: bool, _: bool, _: Allocator) !void {
                    const fhdr = try Fhdr.parseFromBytes(payload);
                    log.info("FHDR block data: {any}", .{fhdr});
                }
            }.process,
        },

        // APLY handler
        .{
            .type = .APLY,
            .name = "APLY",
            .processPayloadFn = struct {
                fn process(payload: []const u8, _: []const u8, _: bool, _: bool, _: Allocator) !void {
                    const aply = try Aply.parseFromBytes(payload);
                    log.info("APLY block data: {any}", .{aply});
                }
            }.process,
        },

        // ADIR handler
        .{
            .type = .ADIR,
            .name = "ADIR",
            .processPayloadFn = struct {
                fn process(payload: []const u8, output_dir: []const u8, extract_files: bool, _: bool, allocator: Allocator) !void {
                    var adir = try Adir.parseFromBytes(payload, allocator);
                    defer allocator.free(adir.path);
                    log.info("ADIR block: Create directory: {s}", .{adir.path[0..adir.path_size]});
                    if (extract_files) {
                        try adir.createDirectory(output_dir, allocator);
                    }
                }
            }.process,
        },

        // DELD handler
        .{
            .type = .DELD,
            .name = "DELD",
            .processPayloadFn = struct {
                fn process(payload: []const u8, output_dir: []const u8, extract_files: bool, _: bool, allocator: Allocator) !void {
                    var deld = try Deld.parseFromBytes(payload, allocator);
                    defer allocator.free(deld.path);
                    log.info("DELD block: Delete directory: {s}", .{deld.path[0..deld.path_size]});
                    if (extract_files) {
                        try deld.deleteDirectory(output_dir, allocator);
                    }
                }
            }.process,
        },

        // ETRY handler
        .{
            .type = .ETRY,
            .name = "ETRY",
            .processPayloadFn = struct {
                fn process(payload: []const u8, output_dir: []const u8, extract_files: bool, verbose: bool, allocator: Allocator) !void {
                    var etry = try Etry.parseFromBytes(payload, allocator);
                    defer allocator.free(etry.path);
                    log.info("ETRY block: Path: {s}, Size: {}, Chunks: {}", .{ etry.path[0..etry.path_size], etry.path_size, etry.count });
                    if (verbose) {
                        log.debug("Extract files flag: {}", .{extract_files});
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
                    for (etry.chunks) |chunk| {
                        allocator.free(chunk.data);
                    }
                    allocator.free(etry.chunks);
                }
            }.process,
        },

        // APFS handler (placeholder - just logs)
        .{
            .type = .APFS,
            .name = "APFS",
            .processPayloadFn = struct {
                fn process(_: []const u8, _: []const u8, _: bool, _: bool, _: Allocator) !void {
                    log.info("Payload data read for APFS block. No specific processing implemented.", .{});
                }
            }.process,
        },
    };

    // Generate a map from block type to handler at compile time
    // Use a fixed size array based on the known block types
    var map: [7]?BlockHandler = [_]?BlockHandler{null} ** 7;

    // Manually assign handlers to their corresponding positions
    for (handlers) |handler| {
        switch (handler.type) {
            .FHDR => map[0] = handler,
            .APLY => map[1] = handler,
            .ADIR => map[2] = handler,
            .DELD => map[3] = handler,
            .ETRY => map[4] = handler,
            .APFS => map[5] = handler,
            .unknown => map[6] = handler,
        }
    }

    break :blk map;
};

/// Processes a block payload based on its type using comptime handler map
fn processBlockPayload(reader: anytype, block_info: BlockInfo, output_dir: []const u8, extract_files: bool, verbose: bool, allocator: Allocator) !void {
    const payload_size = block_info.size;
    const payload_buffer = try allocator.alloc(u8, payload_size);
    defer allocator.free(payload_buffer);

    const bytes_read_payload = try reader.readAll(payload_buffer);

    if (bytes_read_payload < payload_size) {
        log.err("Unexpected end of file while reading payload for block type {s}.", .{block_info.block_type.toString()});
        return error.UnexpectedEndOfFile;
    }

    const block_type = block_info.block_type;

    // Find the correct handler based on block type
    var handler: ?BlockHandler = null;
    switch (block_type) {
        .FHDR => handler = block_handlers[0],
        .APLY => handler = block_handlers[1],
        .ADIR => handler = block_handlers[2],
        .DELD => handler = block_handlers[3],
        .ETRY => handler = block_handlers[4],
        .APFS => handler = block_handlers[5],
        .unknown => handler = block_handlers[6],
    }

    if (handler) |h| {
        try h.processPayloadFn(payload_buffer, output_dir, extract_files, verbose, allocator);
    } else {
        log.info("Payload data read for block type {s}. No specific processing implemented.", .{block_info.block_type.toString()});
    }

    try processCrc(reader, block_info, verbose);
}

/// Processes the CRC at the end of a block
fn processCrc(reader: anytype, block_info: BlockInfo, verbose: bool) !void {
    var crc_buffer: [4]u8 = undefined;
    const bytes_read_crc = try reader.readAll(&crc_buffer);

    if (bytes_read_crc < 4) {
        log.err("Unexpected end of file while reading CRC for block type {s}.", .{block_info.block_type.toString()});
        return error.UnexpectedEndOfFile;
    }

    const crc = mem.readInt(u32, crc_buffer[0..4], .big);
    _ = crc;

    if (verbose) {
        log.debug("CRC value read: {x}", .{crc_buffer});
    }
}

/// Processes all ZiPatch files in a directory
fn processAllPatchesInDirectory(dir_path: []const u8, output_dir: []const u8, extract_files: bool, verbose: bool, recursive_search: bool, allocator: Allocator) !void {
    log.info("Searching for .patch files in directory: {s}", .{dir_path});

    var dir = fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        log.err("Failed to open directory: {s}, error: {}", .{ dir_path, err });
        return err;
    };
    defer dir.close();

    var it = dir.iterate();
    var patch_count: usize = 0;

    while (try it.next()) |entry| {
        // Handle subdirectories if recursive search is enabled
        if (entry.kind == .directory and recursive_search) {
            const subdir_path = try fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
            defer allocator.free(subdir_path);

            processAllPatchesInDirectory(subdir_path, output_dir, extract_files, verbose, recursive_search, allocator) catch |err| {
                log.err("Failed to process subdirectory: {s}, error: {}", .{ subdir_path, err });
                // Continue processing other directories even if one fails
            };
            continue;
        }

        if (entry.kind != .file) continue;

        // Check if file has .patch extension
        if (!mem.endsWith(u8, entry.name, ".patch")) continue;

        const file_path = try fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
        defer allocator.free(file_path);

        log.info("Found patch file: {s}", .{entry.name});
        patch_count += 1;

        processPatchFile(file_path, output_dir, extract_files, verbose, allocator) catch |err| {
            log.err("Failed to process patch file: {s}, error: {}", .{ file_path, err });
            // Continue processing other files even if one fails
        };
    }

    log.info("Processed {d} patch files from directory: {s}", .{ patch_count, dir_path });

    if (patch_count == 0) {
        log.warn("No .patch files found in directory: {s}", .{dir_path});
    }
}

/// Prints usage information for the command-line interface
fn printUsage() !void {
    const usage =
        \\Usage: zipatch_reader [options]
        \\
        \\Options:
        \\  -h, --help              Display this help message
        \\  -f, --file <path>       Path to the ZiPatch file (default: D2010.09.18.0000.patch)
        \\  -o, --output <dir>      Output directory for extracted files (default: output)
        \\  -x, --extract           Extract files from the patch (enabled by default)
        \\  -v, --verbose           Enable verbose output
        \\  -d, --directory <path>  Process all .patch files in the specified directory
        \\  -r, --recursive         Recursively search for .patch files in subdirectories
        \\
    ;
    try io.getStdOut().writer().print("{s}", .{usage});
}
