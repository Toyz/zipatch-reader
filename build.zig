const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const clap = b.dependency("clap", .{});

    const exe = b.addExecutable(.{
        .name = "zipatch_reader",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("clap", clap.module("clap"));
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);

    const release_step = b.step("release", "Build with release-safe optimizations");
    const release_exe = b.addExecutable(.{
        .name = "zipatch_reader",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
    });
    release_exe.root_module.addImport("clap", clap.module("clap"));
    const release_install = b.addInstallArtifact(release_exe, .{});
    release_step.dependOn(&release_install.step);

    const release_fast_step = b.step("release-fast", "Build with release-fast optimizations");
    const release_fast_exe = b.addExecutable(.{
        .name = "zipatch_reader",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    release_fast_exe.root_module.addImport("clap", clap.module("clap"));
    const release_fast_install = b.addInstallArtifact(release_fast_exe, .{});
    release_fast_step.dependOn(&release_fast_install.step);

    const release_small_step = b.step("release-small", "Build with release-small optimizations");
    const release_small_exe = b.addExecutable(.{
        .name = "zipatch_reader",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = .ReleaseSmall,
    });
    release_small_exe.root_module.addImport("clap", clap.module("clap"));
    const release_small_install = b.addInstallArtifact(release_small_exe, .{});
    release_small_step.dependOn(&release_small_install.step);

    const test_step = b.step("test", "Run unit tests");

    const test_files = [_][]const u8{
        "src/ETRY.zig",
        "src/header.zig",
        "src/ADIR.zig",
        "src/APLY.zig",
        "src/DELD.zig",
        "src/FHDR.zig",
    };

    const dedicated_test_files = [_][]const u8{
        "src/ETRY_test.zig",
        "src/header_test.zig",
    };

    for (test_files) |file| {
        const file_test = b.addTest(.{
            .root_source_file = b.path(file),
            .target = target,
            .optimize = optimize,
        });

        const run_test = b.addRunArtifact(file_test);
        test_step.dependOn(&run_test.step);
    }

    for (dedicated_test_files) |file| {
        const file_test = b.addTest(.{
            .root_source_file = b.path(file),
            .target = target,
            .optimize = optimize,
        });

        const run_test = b.addRunArtifact(file_test);
        test_step.dependOn(&run_test.step);
    }
}
