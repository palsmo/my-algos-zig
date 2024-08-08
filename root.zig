const root_shared = @import("./shared.zig");

const LibSettings = struct {
    // * you may want to change this to _.Normal_ for release.
    log_verbosity: root_shared.LogVerbosity = .Verbose,
};

pub var lib_settings = LibSettings{};
