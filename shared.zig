//! Author: palsmo
//! Status: In Progress
//! About: ...

///    mode   |                              about
/// ----------|-----------------------------------------------------------------
/// .Silent   | - All logging in library is pruned.
///           | - The binary is somewhat smaller.
///           |
/// .Normal   | - Only high performance code have their logs pruned.
///           | - Best for most cases, won't effect performance.
///           |
/// .Verbose  | - No logs are pruned, best used for debugging.
///             - May display warnings for unsafe use of high performance code.
///           | - Not recommended for release builds.
/// ----------------------------------------------------------------------------
pub const LogVerbosity = enum {
    Silent,
    Normal,
    Verbose,
};
