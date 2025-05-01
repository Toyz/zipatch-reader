const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Standard debug build
    const exe = createExecutable(b, target, optimize);
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);

    // Release builds with different optimization levels
    createReleaseBuild(b, target, .ReleaseSafe, "release");
    createReleaseBuild(b, target, .ReleaseFast, "release-fast");
    createReleaseBuild(b, target, .ReleaseSmall, "release-small");

    // Tests
    const test_step = b.step("test", "Run unit tests");
    addAllTests(b, target, optimize, test_step);
}

fn addDependencies(b: *std.Build, module: *std.Build.Module) void {
    const clap = b.dependency("clap", .{});
    module.addImport("clap", clap.module("clap"));
}

fn createExecutable(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "zipatch_reader",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    addDependencies(b, exe.root_module);
    return exe;
}

fn createReleaseBuild(b: *std.Build, target: std.Build.ResolvedTarget, optimize_mode: std.builtin.OptimizeMode, step_name: []const u8) void {
    const description = b.fmt("Build with {s} optimizations", .{@tagName(optimize_mode)});
    const release_step = b.step(step_name, description);

    const release_exe = b.addExecutable(.{
        .name = "zipatch_reader",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize_mode,
    });

    addDependencies(b, release_exe.root_module);
    const release_install = b.addInstallArtifact(release_exe, .{});
    release_step.dependOn(&release_install.step);
}

fn addAllTests(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, test_step: *std.Build.Step) void {
    const src_dir = b.pathFromRoot("src");

    var dir = std.fs.openDirAbsolute(src_dir, .{ .iterate = true }) catch @panic("Failed to open src directory");
    defer dir.close();

    var it = dir.iterate();
    while (it.next() catch @panic("Failed to iterate src directory")) |entry| {
        if (entry.kind != .file) continue;

        const is_zig_file = std.mem.endsWith(u8, entry.name, ".zig");
        if (!is_zig_file) continue;

        if (std.mem.eql(u8, entry.name, "main.zig")) continue;

        const file_path = b.fmt("src/{s}", .{entry.name});
        const file_test = b.addTest(.{
            .root_source_file = b.path(file_path),
            .target = target,
            .optimize = optimize,
        });

        addDependencies(b, file_test.root_module);
        const run_test = b.addRunArtifact(file_test);
        test_step.dependOn(&run_test.step);
    }
}
