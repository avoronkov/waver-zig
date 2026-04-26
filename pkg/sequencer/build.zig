const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tool = b.addExecutable(.{
        .name = "generate_struct",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools/generate_dir_index.zig"),
            .target = b.graph.host,
        }),
    });

    var tool_step = b.addRunArtifact(tool);
    tool_step.addDirectoryArg(b.path("res/waver-samples/samples"));
    const output = tool_step.addOutputFileArg("samples.zig");

    const gen_step = b.step("gen", "Generate resources");
    gen_step.dependOn(&tool_step.step);

    const dwav = b.dependency("wav", .{
        .target = target,
        .optimize = optimize,
    }).module("wav");

    const mod = b.addModule("sequencer", .{
        .root_source_file = b.path("src/app.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "wav", .module = dwav },
        },
    });
    mod.addAnonymousImport("samples", .{
        .root_source_file = output,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "sequencer",
        .root_module = mod,
    });
    lib.step.dependOn(&tool_step.step);
    b.installArtifact(lib);

    const test_mod = b.addModule("test_sequencer", .{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "wav", .module = dwav },
        },
    });
    test_mod.addAnonymousImport("samples", .{
        .root_source_file = output,
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
    exe.root_module.addAnonymousImport("samples", .{
        .root_source_file = output,
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
