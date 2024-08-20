/// XSystem client errors.
pub const XClientError = error{
    ActedOnNonExistentWindow,
    FailedToAllocateRequestedResource,
    FailedToEstablishConnectionWithServer,
    FailedToGetWindowGeometry,
    WindowAlreadyClosed,
    WindowAlreadyOpen,
    WindowNotOpen,
};

/// Wayland client errors.
pub const WClientError = error{
    FailedToEstablishConnectionWithServer,
};
