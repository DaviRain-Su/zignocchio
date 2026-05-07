const sdk = @import("sdk");

comptime {
    const readonly: sdk.ReadonlyAccount = undefined;
    _ = readonly.lamports_ptr;
}
