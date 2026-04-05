const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dwav = b.dependency("wav", .{
        .target = target,
        .optimize = optimize,
    }).module("wav");

    const mod = b.addModule("sequencer", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "wav", .module = dwav },
        },
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "sequencer",
        .root_module = mod,
    });
    b.installArtifact(lib);

    const test_mod = b.addModule("test_sequencer", .{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "wav", .module = dwav },
        },
    });

    const mod_tests = b.addTest(.{
        .root_module = test_mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    const exe_mod = b.addModule("waver", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "wav", .module = dwav },
        },
    });
    const exe = b.addExecutable(.{
        .name = "sequencer",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
