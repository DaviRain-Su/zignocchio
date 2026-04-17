const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const cli_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_module.link_libc = true;

    const exe = b.addExecutable(.{
        .name = "zignocchio-cli",
        .root_module = cli_module,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the CLI");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run CLI tests");
    const test_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_module.link_libc = true;
    const unit_tests = b.addTest(.{
        .root_module = test_module,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);
}
