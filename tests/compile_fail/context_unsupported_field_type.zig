const sdk = @import("sdk");

const Accounts = struct {
    unsupported: u64,
};

comptime {
    _ = sdk.Context(Accounts);
}
