const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const hither = b.addModule("hither", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/hither.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "hither",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("hither", hither);
    b.installArtifact(exe);

    const run_step = b.step("run", "run hither");
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    run_step.dependOn(&run.step);

    const tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("hither", hither);
    const tests_run = b.addRunArtifact(tests);
    const tests_step = b.step("test", "test hither");
    tests_step.dependOn(&tests_run.step);
}
