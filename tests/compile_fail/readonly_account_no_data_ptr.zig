const sdk = @import("sdk");

comptime {
    const readonly: sdk.ReadonlyAccount = undefined;
    _ = readonly.data_ptr;
}
