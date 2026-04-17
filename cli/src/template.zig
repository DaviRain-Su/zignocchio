//! Template strings for zignocchio-cli

pub const build_zig =
    \\const std = @import("std");
    \\
    \\pub fn build(b: *std.Build) !void {
    \\    const optimize = .ReleaseSmall;
    \\
    \\    const bitcode_path = "entrypoint.bc";
    \\    const lib_path = "src/lib.zig";
    \\
    \\    const gen_bitcode = b.addSystemCommand(&.{
    \\        "zig",
    \\        "build-lib",
    \\        "-target",
    \\        "bpfel-freestanding",
    \\        "-O",
    \\        "ReleaseSmall",
    \\        "-femit-llvm-bc=" ++ bitcode_path,
    \\        "-fno-emit-bin",
    \\        "--dep", "sdk",
    \\        b.fmt("-Mroot={s}", .{lib_path}),
    \\        "-Msdk=sdk/zignocchio.zig",
    \\    });
    \\
    \\    const mkdir_step = b.addSystemCommand(&.{ "mkdir", "-p", "zig-out/lib" });
    \\
    \\    const program_so_path = "zig-out/lib/program.so";
    \\    const link_program = b.addSystemCommand(&.{
    \\        "sbpf-linker",
    \\        "--cpu", "v2",
    \\        "--llvm-args=-bpf-stack-size=4096",
    \\        "--export", "entrypoint",
    \\        "-o", program_so_path,
    \\        bitcode_path,
    \\    });
    \\    link_program.step.dependOn(&gen_bitcode.step);
    \\    link_program.step.dependOn(&mkdir_step.step);
    \\
    \\    const llvm_fix_dir = ".zig-cache/llvm_fix";
    \\    const mkdir_llvm_fix = b.addSystemCommand(&.{ "mkdir", "-p", llvm_fix_dir });
    \\    const llvm_symlink = b.addSystemCommand(&.{
    \\        "ln", "-sf",
    \\        "/usr/lib/x86_64-linux-gnu/libLLVM.so.20.1",
    \\        b.fmt("{s}/libLLVM.so", .{llvm_fix_dir}),
    \\    });
    \\    llvm_symlink.step.dependOn(&mkdir_llvm_fix.step);
    \\    link_program.step.dependOn(&llvm_symlink.step);
    \\
    \\    const prev_ld_path = b.graph.environ_map.get("LD_LIBRARY_PATH") orelse "";
    \\    const ld_library_path = if (prev_ld_path.len > 0)
    \\        b.fmt("{s}:{s}", .{ llvm_fix_dir, prev_ld_path })
    \\    else
    \\        llvm_fix_dir;
    \\    link_program.setEnvironmentVariable("LD_LIBRARY_PATH", ld_library_path);
    \\
    \\    b.getInstallStep().dependOn(&link_program.step);
    \\
    \\    const test_step = b.step("test", "Run unit tests");
    \\    const sdk_module = b.createModule(.{
    \\        .root_source_file = b.path("sdk/zignocchio.zig"),
    \\    });
    \\    const test_module = b.createModule(.{
    \\        .root_source_file = b.path("src/lib.zig"),
    \\        .target = b.graph.host,
    \\        .optimize = optimize,
    \\    });
    \\    test_module.addImport("sdk", sdk_module);
    \\    const lib_unit_tests = b.addTest(.{
    \\        .root_module = test_module,
    \\    });
    \\    const run_unit_tests = b.addRunArtifact(lib_unit_tests);
    \\    test_step.dependOn(&run_unit_tests.step);
    \\}
    \\
;

pub const lib_zig =
    \\//! %%NAME%% program entrypoint
    \\
    \\const sdk = @import("sdk");
    \\
    \\pub const CounterState = extern struct {
    \\    pub const DISCRIMINATOR: u8 = 0xC0;
    \\    discriminator: u8,
    \\    owner: sdk.Pubkey,
    \\    count: u64,
    \\};
    \\
    \\pub const InitializeAccounts = struct {
    \\    owner: sdk.AccountInfo,
    \\    counter: sdk.AccountInfo,
    \\    system_program: sdk.AccountInfo,
    \\};
    \\
    \\fn validateInitialize(
    \\    accounts: []sdk.AccountInfo,
    \\    program_id: *const sdk.Pubkey,
    \\) sdk.ProgramError!InitializeAccounts {
    \\    if (accounts.len < 3) return error.NotEnoughAccountKeys;
    \\    const owner = accounts[0];
    \\    const counter = accounts[1];
    \\    const system_program = accounts[2];
    \\
    \\    try sdk.guard.assert_signer(owner);
    \\    try sdk.guard.assert_writable(counter);
    \\
    \\    var system_program_id: sdk.Pubkey = undefined;
    \\    sdk.system.getSystemProgramId(&system_program_id);
    \\    try sdk.guard.assert_owner(counter, &system_program_id);
    \\
    \\    if (counter.lamports() != 0) return error.AccountAlreadyInitialized;
    \\
    \\    const owner_key = owner.key().*;
    \\    const seeds = &[_][]const u8{ "counter", &owner_key };
    \\    var expected_counter: sdk.Pubkey = undefined;
    \\    var bump: u8 = undefined;
    \\    try sdk.findProgramAddress(seeds, program_id, &expected_counter, &bump);
    \\    if (!sdk.pubkeyEq(counter.key(), &expected_counter)) return error.IncorrectProgramId;
    \\
    \\    if (!sdk.pubkeyEq(system_program.key(), &system_program_id)) return error.IncorrectProgramId;
    \\
    \\    return InitializeAccounts{ .owner = owner, .counter = counter, .system_program = system_program };
    \\}
    \\
    \\pub fn processInitialize(
    \\    program_id: *const sdk.Pubkey,
    \\    accounts: []sdk.AccountInfo,
    \\) sdk.ProgramResult {
    \\    const validated = try validateInitialize(accounts, program_id);
    \\
    \\    const space: u64 = @sizeOf(CounterState);
    \\    const rent_exempt = ((space / 256) + 1) * 6960;
    \\    const lamports = rent_exempt;
    \\
    \\    const owner_key = validated.owner.key().*;
    \\    const seeds = &[_][]const u8{ "counter", &owner_key };
    \\    var expected_counter: sdk.Pubkey = undefined;
    \\    var bump: u8 = undefined;
    \\    try sdk.findProgramAddress(seeds, program_id, &expected_counter, &bump);
    \\
    \\    const signers_seeds = &[_][]const u8{
    \\        "counter",
    \\        &owner_key,
    \\        &[_]u8{bump},
    \\    };
    \\
    \\    try sdk.system.createAccountSigned(
    \\        validated.owner,
    \\        validated.counter,
    \\        program_id,
    \\        space,
    \\        lamports,
    \\        signers_seeds,
    \\    );
    \\
    \\    const Schema = sdk.schema.AccountSchema(CounterState);
    \\    const data = validated.counter.borrowMutDataUnchecked();
    \\    var state = Schema.from_bytes_unchecked(data);
    \\    state.discriminator = CounterState.DISCRIMINATOR;
    \\    state.owner = validated.owner.key().*;
    \\    state.count = 0;
    \\}
    \\
    \\pub const INSTRUCTION_INIT = 0;
    \\
    \\pub fn processInstruction(
    \\    program_id: *const sdk.Pubkey,
    \\    accounts: []sdk.AccountInfo,
    \\    instruction_data: []const u8,
    \\) sdk.ProgramResult {
    \\    if (instruction_data.len < 1) return error.InvalidInstructionData;
    \\    const discriminator = instruction_data[0];
    \\    switch (discriminator) {
    \\        INSTRUCTION_INIT => try processInitialize(program_id, accounts),
    \\        else => return error.InvalidInstructionData,
    \\    }
    \\}
    \\
    \\pub const entrypoint = sdk.createEntrypointWithMaxAccounts(6, processInstruction);
    \\
;

pub const test_ts =
    \\import {
    \\  Connection,
    \\  Keypair,
    \\  PublicKey,
    \\  Transaction,
    \\  TransactionInstruction,
    \\  sendAndConfirmTransaction,
    \\} from '@solana/web3.js';
    \\import { execSync, spawn } from 'child_process';
    \\import * as fs from 'fs';
    \\import * as path from 'path';
    \\
    \\describe('%%NAME%% Program', () => {
    \\  let validator: ReturnType<typeof spawn>;
    \\  let connection: Connection;
    \\  let programId: PublicKey;
    \\  let payer: Keypair;
    \\
    \\  const INIT = 0;
    \\
    \\  beforeAll(async () => {
    \\    try { execSync('pkill -f surfpool', { stdio: 'ignore' }); } catch (e) {}
    \\    await new Promise(r => setTimeout(r, 2000));
    \\
    \\    console.log('Building program...');
    \\    execSync('zig build', { stdio: 'inherit' });
    \\
    \\    const programKeypair = Keypair.generate();
    \\    programId = programKeypair.publicKey;
    \\    console.log('Program ID:', programId.toBase58());
    \\
    \\    const programKeypairPath = path.join(__dirname, 'program-keypair.json');
    \\    fs.writeFileSync(programKeypairPath, JSON.stringify(Array.from(programKeypair.secretKey)));
    \\
    \\    const programPath = path.join(__dirname, 'zig-out', 'lib', 'program.so');
    \\    if (!fs.existsSync(programPath)) {
    \\      throw new Error(`Program not found at ${programPath}`);
    \\    }
    \\
    \\    console.log('Starting surfpool...');
    \\    validator = spawn('surfpool', ['start', '--ci', '--no-tui', '--offline'], {
    \\      detached: true,
    \\      stdio: ['ignore', 'pipe', 'pipe'],
    \\    });
    \\    validator.unref();
    \\    await new Promise(r => setTimeout(r, 5000));
    \\
    \\    connection = new Connection('http://localhost:8899', 'confirmed');
    \\
    \\    payer = Keypair.generate();
    \\    const airdropSig = await connection.requestAirdrop(payer.publicKey, 2_000_000_000);
    \\    await connection.confirmTransaction(airdropSig);
    \\    console.log('Payer funded:', payer.publicKey.toBase58());
    \\
    \\    const programData = fs.readFileSync(programPath);
    \\    const deployRes = await fetch('http://127.0.0.1:8899', {
    \\      method: 'POST',
    \\      headers: { 'Content-Type': 'application/json' },
    \\      body: JSON.stringify({
    \\        jsonrpc: '2.0',
    \\        id: 1,
    \\        method: 'surfnet_setAccount',
    \\        params: [
    \\          programId.toBase58(),
    \\          {
    \\            lamports: 1000000000,
    \\            data: programData.toString('hex'),
    \\            owner: 'BPFLoader2111111111111111111111111111111111',
    \\            executable: true,
    \\          },
    \\        ],
    \\      }),
    \\    });
    \\    const deployJson = await deployRes.json() as any;
    \\    if (deployJson.error) {
    \\      throw new Error(`Deploy failed: ${deployJson.error.message}`);
    \\    }
    \\
    \\    let ready = false;
    \\    for (let i = 0; i < 10; i++) {
    \\      const info = await connection.getAccountInfo(programId);
    \\      if (info && info.executable) { ready = true; break; }
    \\      await new Promise(r => setTimeout(r, 500));
    \\    }
    \\    if (!ready) throw new Error('Program not executable');
    \\    console.log('Program deployed successfully!');
    \\  }, 60000);
    \\
    \\  afterAll(async () => {
    \\    try { (connection as any)._rpcWebSocket?.close(); } catch (e) {}
    \\    try { execSync('pkill -f surfpool'); } catch (e) {}
    \\    try {
    \\      fs.unlinkSync(path.join(__dirname, 'program-keypair.json'));
    \\    } catch (e) {}
    \\    await new Promise(r => setTimeout(r, 100));
    \\  });
    \\
    \\  function findCounterPDA(ownerPubkey: PublicKey): PublicKey {
    \\    const [pda] = PublicKey.findProgramAddressSync(
    \\      [Buffer.from('counter'), ownerPubkey.toBuffer()],
    \\      programId
    \\    );
    \\    return pda;
    \\  }
    \\
    \\  it('should initialize counter', async () => {
    \\    const counter = findCounterPDA(payer.publicKey);
    \\    const data = Buffer.from([INIT]);
    \\    const ix = new TransactionInstruction({
    \\      keys: [
    \\        { pubkey: payer.publicKey, isSigner: true, isWritable: true },
    \\        { pubkey: counter, isSigner: false, isWritable: true },
    \\        { pubkey: PublicKey.default, isSigner: false, isWritable: false }, // system program
    \\      ],
    \\      programId,
    \\      data,
    \\    });
    \\    const tx = new Transaction().add(ix);
    \\    const signature = await sendAndConfirmTransaction(connection, tx, [payer]);
    \\    console.log('Initialize signature:', signature);
    \\    const accountInfo = await connection.getAccountInfo(counter);
    \\    expect(accountInfo).not.toBeNull();
    \\    expect(accountInfo!.data[0]).toBe(0xC0);
    \\  });
    \\});
    \\
;
