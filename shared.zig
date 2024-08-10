//! Author: palsmo
//! Status: In Progress
//! About: Shared Among All Modules

/// Execution modes for functions that support branch optimization.
///
///    mode   |                                        about
/// ----------|-------------------------------------------------------------------------------------
/// .Safe     | - Contains safety checks that may throw or panic.
///           | - This is the suggested mode for most situations, allowing for detection and
///           |   consequential handling of errors.
///           |
/// .Uncheck  | - Fastest but unsafe, most conditional branches (e.g., safety checks) are pruned
///           |   to simpler control flows with the downside that undefined behaviors can be hit.
///           | - If library logging is set _.Verbose_, unsafe scenarios are caught by assertions.
/// ------------------------------------------------------------------------------------------------
pub const ExecMode = enum { Safe, Uncheck };

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
