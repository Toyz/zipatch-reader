const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options
    const target = b.standardTargetOptions(.{});

    // Standard release options
    const optimize = b.standardOptimizeOption(.{});

    // Add clap dependency
    const clap = b.dependency("clap", .{});

    const exe = b.addExecutable(.{
        .name = "zipatch_reader",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add clap import to the executable
    exe.root_module.addImport("clap", clap.module("clap"));

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
}
