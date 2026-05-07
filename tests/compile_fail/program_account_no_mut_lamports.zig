const sdk = @import("sdk");

comptime {
    const program: sdk.ProgramAccount = undefined;
    _ = program.tryBorrowMutLamports();
}
