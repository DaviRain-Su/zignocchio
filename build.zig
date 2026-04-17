const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    const optimize = .ReleaseSmall;

    // Build option: which example to build
    const example_name = b.option([]const u8, "example", "Example to build (hello, counter, vault, transfer-sol, pda-storage, token-vault, escrow)") orelse "counter";

    // Step 1: Generate LLVM bitcode using zig build-lib
    const bitcode_path = "entrypoint.bc";

    // All examples are now in examples/{name}/lib.zig
    const example_path = b.fmt("examples/{s}/lib.zig", .{example_name});

    const gen_bitcode = b.addSystemCommand(&.{
        "zig",
        "build-lib",
        "-target",
        "bpfel-freestanding",
        "-O",
        "ReleaseSmall",
        "-femit-llvm-bc=" ++ bitcode_path,
        "-fno-emit-bin",
        "--dep", "sdk",
        b.fmt("-Mroot={s}", .{example_path}),
        "-Msdk=sdk/zignocchio.zig",
    });

    // Ensure output directory exists before linking
    const mkdir_step = b.addSystemCommand(&.{ "mkdir", "-p", "zig-out/lib" });

    // Step 2: Link with sbpf-linker
    // Each example gets its own .so to avoid stale artifact bugs in tests.
    const program_so_path = b.fmt("zig-out/lib/{s}.so", .{example_name});
    const link_program = b.addSystemCommand(&.{
        "sbpf-linker",
        "--cpu", "v2",  // v2: No 32-bit jumps (Solana sBPF compatible)
        "--llvm-args=-bpf-stack-size=4096",  // Configure 4KB stack for Solana sBPF
        "--export", "entrypoint",
        "-o", program_so_path,
        bitcode_path,
    });
    link_program.step.dependOn(&gen_bitcode.step);
    link_program.step.dependOn(&mkdir_step.step);

    // sbpf-linker uses aya-rustc-llvm-proxy which dynamically loads libLLVM.so.
    // On some distros only versioned files (e.g. libLLVM.so.20) exist.
    // We create a local symlink and point LD_LIBRARY_PATH at it.
    const llvm_fix_dir = ".zig-cache/llvm_fix";
    const mkdir_llvm_fix = b.addSystemCommand(&.{ "mkdir", "-p", llvm_fix_dir });
    const llvm_symlink = b.addSystemCommand(&.{
        "ln", "-sf",
        "/usr/lib/x86_64-linux-gnu/libLLVM.so.20.1",
        b.fmt("{s}/libLLVM.so", .{llvm_fix_dir}),
    });
    llvm_symlink.step.dependOn(&mkdir_llvm_fix.step);
    link_program.step.dependOn(&llvm_symlink.step);

    // Prepend our local fix dir to LD_LIBRARY_PATH for the linker.
    const prev_ld_path = b.graph.environ_map.get("LD_LIBRARY_PATH") orelse "";
    const ld_library_path = if (prev_ld_path.len > 0)
        b.fmt("{s}:{s}", .{ llvm_fix_dir, prev_ld_path })
    else
        llvm_fix_dir;
    link_program.setEnvironmentVariable("LD_LIBRARY_PATH", ld_library_path);

    // Default install step depends on linking
    b.getInstallStep().dependOn(&link_program.step);

    // CLI executable
    const cli_module = b.createModule(.{
        .root_source_file = b.path("cli/src/main.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseFast,
    });
    cli_module.link_libc = true;
    const cli_exe = b.addExecutable(.{
        .name = "zignocchio-cli",
        .root_module = cli_module,
    });
    b.installArtifact(cli_exe);

    // Optional unit tests (run on host, not BPF)
    const test_step = b.step("test", "Run unit tests");
    const sdk_module = b.createModule(.{
        .root_source_file = b.path("sdk/zignocchio.zig"),
    });
    const test_module = b.createModule(.{
        .root_source_file = b.path("examples/hello/lib.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    test_module.addImport("sdk", sdk_module);
    const lib_unit_tests = b.addTest(.{
        .root_module = test_module,
    });
    const run_unit_tests = b.addRunArtifact(lib_unit_tests);
    test_step.dependOn(&run_unit_tests.step);
}
