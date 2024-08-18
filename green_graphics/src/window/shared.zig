/// XSystem client errors.
pub const XClientError = error{
    FailedToEstablishConnectionWithServer,
};

/// Wayland client errors.
pub const WClientError = error{
    FailedToEstablishConnectionWithServer,
};
