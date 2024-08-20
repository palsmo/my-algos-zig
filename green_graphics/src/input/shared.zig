/// Input errors.
pub const InputError = error{
    DeviceNotFound,
    DeviceBusy,
    PermissionDenied,
    Undefined,
};
