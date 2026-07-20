const std = @import("std");

pub fn build(b: *std.Build) void {
    // hack to build in arm64-termux-proot-fedora.
    const isAarch64 = b.graph.host.result.cpu.arch.isAARCH64();
    const target = if (isAarch64) b.resolveTargetQuery(.{
        .cpu_arch = .aarch64,
        .os_tag = .linux,
        .abi = .gnu,
    }) else b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize,
    });
    if (isAarch64) {
        translate_c.addIncludePath(.{ .cwd_relative = "/usr/include" });
    }
    const translate_c_mod = translate_c.createModule();
    if (isAarch64) {
        translate_c_mod.addLibraryPath(.{ .cwd_relative = "/usr/lib64" });
    }
    translate_c_mod.linkSystemLibrary("libpulse-simple", .{});

    const mod = b.addModule("waver", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "c",
                .module = translate_c_mod,
            },
        },
    });

    const exe = b.addExecutable(.{
        .name = "waver-zig",
        .root_module = mod,
    });

    const dseq = b.dependency("seq", .{
        .target = target,
        .optimize = optimize,
    }).module("seq");

    exe.root_module.addImport("seq", dseq);

    const dwav = b.dependency("wav", .{
        .target = target,
        .optimize = optimize,
    }).module("wav");

    exe.root_module.addImport("wav", dwav);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
