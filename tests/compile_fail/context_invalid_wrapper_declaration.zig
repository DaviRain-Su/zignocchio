const sdk = @import("sdk");

const FakeWrapper = struct {
    pub const zignocchio_framework_account_wrapper = true;
};

const Accounts = struct {
    fake: FakeWrapper,
};

comptime {
    _ = sdk.Context(Accounts);
}
