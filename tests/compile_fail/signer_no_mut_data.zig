const sdk = @import("sdk");

comptime {
    const signer: sdk.Signer = undefined;
    _ = signer.tryBorrowMutData();
}
