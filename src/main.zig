const std = @import("std");
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const heap = std.heap;
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

/// Magic number identifying a ZiPatch file
const ZipatchFileType: [7]u8 = .{ 'Z', 'I', 'P', 'A', 'T', 'C', 'H' };

/// Set the default log level to "info"
pub const log_level: std.log.Level = .info;

/// Main entry point for the ZiPatch reader application
/// Parses command-line arguments and processes the ZiPatch file
pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help              Display this help message and exit.
        \\-f, --file <str>        Path to the ZiPatch file to process.
        \\-o, --output <str>      Output directory for extracted files.
        \\-x, --extract           Extract files from the patch.
        \\-v, --verbose           Enable verbose output.
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

    var file_path: []const u8 = "D2010.09.18.0000.patch";
    var output_dir: []const u8 = "output";
    var extract_files = true;
    var verbose = false;

    if (res.args.file) |f| {
        file_path = f;
    }

    if (res.args.output) |o| {
        output_dir = o;
    }

    if (res.args.extract != 0) {
        extract_files = true;
    }

    if (res.args.verbose != 0) {
        verbose = true;
    }

    if (verbose) {
        log.info("Verbose mode enabled", .{});
    }

    log.info("Processing file: {s}", .{file_path});
    if (extract_files) {
        log.info("Extracting files to: {s}", .{output_dir});

        fs.cwd().makeDir(output_dir) catch |err| {
            if (err != error.PathAlreadyExists) {
                log.err("Failed to create output directory: {s}", .{output_dir});
                return err;
            }
        };
    }

    const file = try fs.cwd().openFile(file_path, .{ .mode = .read_only });
    defer file.close();

    const reader = file.reader();

    var header_buffer: [12]u8 = undefined;
    const bytes_read_header = try reader.readAll(&header_buffer);

    if (bytes_read_header < 12) {
        log.err("File '{s}' is too short to contain a header.", .{file_path});
        return error.UnexpectedEndOfFile;
    }

    if (mem.indexOf(u8, &header_buffer, &ZipatchFileType) == null) {
        log.err("File '{s}' header does not contain the expected ZiPatch file type sequence.", .{file_path});
        log.err("Full header read: {x}", .{&header_buffer});
        log.err("Expected sequence: {s}", .{&ZipatchFileType});
        return error.InvalidMagicNumber;
    }
    log.info("Successfully verified ZiPatch file type header.", .{});

    while (true) {
        log.debug("Reader position before reading BlockInfo: {}", .{try file.getPos()});

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
        log.debug("Reader position after reading BlockInfo: {}", .{try file.getPos()});

        if (block_info.block_type == .unknown) {
            log.err("Unknown block type found: {s} (Size: {})", .{ block_info.block_type.toString(), block_info.size });
            return error.UnknownBlockType;
        }
        log.info("Found block type: {s}, Size: {}", .{ block_info.block_type.toString(), block_info.size });

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
                defer {
                    allocator.free(etry.path);
                }

                log.info("ETRY block: Path: {s}, Size: {}, Chunks: {}", .{ etry.path[0..etry.path_size], etry.path_size, etry.count });

                log.debug("Extract files flag: {}", .{extract_files});

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
            },
            .APFS, .unknown => {
                log.info("Payload data read for block type {s}. No specific processing implemented.", .{block_info.block_type.toString()});
            },
        }

        var crc_buffer: [4]u8 = undefined;
        const bytes_read_crc = try reader.readAll(&crc_buffer);
        if (bytes_read_crc < 4) {
            log.err("Unexpected end of file while reading CRC for block type {s}.", .{block_info.block_type.toString()});
            return error.UnexpectedEndOfFile;
        }
        const crc = mem.readInt(u32, crc_buffer[0..4], .big);
        _ = crc;
        log.debug("CRC value read: {x}", .{crc_buffer});
    }

    log.info("Finished reading blocks until end of file.", .{});
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
        \\
    ;
    try io.getStdOut().writer().print("{s}", .{usage});
}
