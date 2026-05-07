const sdk = @import("sdk");

comptime {
    const readonly: sdk.ReadonlyAccount = undefined;
    _ = readonly.__zignocchio_opaque_state;
}
