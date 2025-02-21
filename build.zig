const std = @import("std");
const raylib_build = @import("raylib");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .Debug,
    });

    const exe = b.addExecutable(.{
        .name = "zgbe",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const raylib_dep = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
        .linux_display_backend = .X11,
    });
    const raylib = raylib_dep.artifact("raylib");

    exe.linkLibrary(raylib);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    const acceptance = b.addExecutable(.{
        .name = "zgbe-acceptance",
        .root_source_file = b.path("src/acceptance.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(acceptance);

    // const acceptance_step = b.step("acceptance", "Build acceptance");
    // acceptance_step.dependOn(&acceptance.step);
    // const install_acceptance = b.addInstallArtifact(exe, .{});
    // acceptance_step.dependOn(&install_acceptance.step);
}
