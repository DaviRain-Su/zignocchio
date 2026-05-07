const std = @import("std");

const regression_examples = [_][]const u8{
    "counter",
    "vault",
    "transfer-sol",
    "pda-storage",
    "token-vault",
    "escrow",
};

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    const optimize = .ReleaseSmall;

    // Build option: which example to build
    const example_name = b.option([]const u8, "example", "Example to build (hello, counter, vault, transfer-sol, pda-storage, token-vault, escrow)") orelse "counter";

    const link_program = addExampleProgram(b, example_name, "entrypoint.bc");

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

    addCompileFailFixture(
        b,
        test_step,
        "framework_lowercase_instructions",
        "tests/compile_fail/framework_lowercase_instructions.zig",
        "framework Program declaration is missing `Instruction` declaration",
    );
    addCompileFailFixture(
        b,
        test_step,
        "context_non_struct_accounts",
        "tests/compile_fail/context_non_struct_accounts.zig",
        "Context requires a struct Accounts type",
    );
    addCompileFailFixture(
        b,
        test_step,
        "context_unsupported_field_type",
        "tests/compile_fail/context_unsupported_field_type.zig",
        "unsupported account field type `u64`",
    );
    addCompileFailFixture(
        b,
        test_step,
        "context_invalid_wrapper_declaration",
        "tests/compile_fail/context_invalid_wrapper_declaration.zig",
        "invalid account wrapper declaration",
    );
    addCompileFailFixture(
        b,
        test_step,
        "readonly_account_no_mut_data",
        "tests/compile_fail/readonly_account_no_mut_data.zig",
        "tryBorrowMutData",
    );
    addCompileFailFixture(
        b,
        test_step,
        "signer_no_mut_data",
        "tests/compile_fail/signer_no_mut_data.zig",
        "tryBorrowMutData",
    );
    addCompileFailFixture(
        b,
        test_step,
        "program_account_no_mut_lamports",
        "tests/compile_fail/program_account_no_mut_lamports.zig",
        "tryBorrowMutLamports",
    );

    // Keep representative low-level examples build-safe as part of the normal
    // Zig validator. Each regression build uses its own bitcode path so
    // parallel test execution cannot race on the default entrypoint.bc.
    inline for (regression_examples) |regression_example| {
        const regression_bitcode = b.fmt(".zig-cache/regression/{s}.bc", .{regression_example});
        const regression_build = addExampleProgram(b, regression_example, regression_bitcode);
        test_step.dependOn(&regression_build.step);
    }
}

fn addCompileFailFixture(
    b: *std.Build,
    test_step: *std.Build.Step,
    name: []const u8,
    path: []const u8,
    diagnostic: []const u8,
) void {
    const compile_fail = b.addSystemCommand(&.{
        "sh",
        "-c",
        \\set -eu
        \\name="$1"
        \\path="$2"
        \\diagnostic="$3"
        \\err=".zig-cache/${name}.err"
        \\mkdir -p ".zig-cache"
        \\rm -f "$err"
        \\if zig build-obj -fno-emit-bin --dep sdk -Mroot="$path" -Msdk=sdk/zignocchio.zig 2>"$err"; then
        \\  echo "expected $path to fail compilation" >&2
        \\  exit 1
        \\fi
        \\if ! rg -F "$diagnostic" "$err" >/dev/null; then
        \\  cat "$err" >&2
        \\  exit 1
        \\fi
        ,
        "compile-fail",
        name,
        path,
        diagnostic,
    });
    test_step.dependOn(&compile_fail.step);
}

fn addExampleProgram(
    b: *std.Build,
    example_name: []const u8,
    bitcode_path: []const u8,
) *std.Build.Step.Run {
    // Step 1: Generate LLVM bitcode using zig build-lib.
    // All examples are in examples/{name}/lib.zig.
    const example_path = b.fmt("examples/{s}/lib.zig", .{example_name});
    const gen_bitcode = b.addSystemCommand(&.{
        "zig",
        "build-lib",
        "-target",
        "bpfel-freestanding",
        "-O",
        "ReleaseSmall",
        b.fmt("-femit-llvm-bc={s}", .{bitcode_path}),
        "-fno-emit-bin",
        "--dep",
        "sdk",
        b.fmt("-Mroot={s}", .{example_path}),
        "-Msdk=sdk/zignocchio.zig",
    });

    // Ensure output and per-example cache directories exist before building.
    const mkdir_out = b.addSystemCommand(&.{ "mkdir", "-p", "zig-out/lib" });
    const mkdir_regression_cache = b.addSystemCommand(&.{ "mkdir", "-p", ".zig-cache/regression" });
    gen_bitcode.step.dependOn(&mkdir_regression_cache.step);

    // Step 2: Link with sbpf-linker.
    // Each example gets its own .so to avoid stale artifact bugs in tests.
    const program_so_path = b.fmt("zig-out/lib/{s}.so", .{example_name});
    const link_program = b.addSystemCommand(&.{
        "sbpf-linker",
        "--cpu", "v2", // v2: No 32-bit jumps (Solana sBPF compatible)
        "--llvm-args=-bpf-stack-size=4096", // Configure 4KB stack for Solana sBPF
        "--export",
        "entrypoint",
        "-o",
        program_so_path,
        bitcode_path,
    });
    link_program.step.dependOn(&gen_bitcode.step);
    link_program.step.dependOn(&mkdir_out.step);

    // sbpf-linker uses aya-rustc-llvm-proxy which dynamically loads libLLVM.so.
    // On some distros only versioned files (e.g. libLLVM.so.20) exist.
    // We create a local symlink and point LD_LIBRARY_PATH at it.
    const llvm_fix_dir = ".zig-cache/llvm_fix";
    const llvm_lib_path = "/usr/lib/x86_64-linux-gnu/libLLVM.so.20.1";
    const mkdir_llvm_fix = b.addSystemCommand(&.{ "mkdir", "-p", llvm_fix_dir });
    const llvm_symlink = b.addSystemCommand(&.{
        "ln",
        "-sf",
        llvm_lib_path,
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

    return link_program;
}
