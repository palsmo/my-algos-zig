//! Author: palsmo
//! Status: In Progress
//! Brief: Project-wide shared ...

pub const errors = struct {
    ///       error      |                                  about
    /// -----------------|--------------------------------------------------------------------------
    /// NotEnoughSpace   | - When the buffer hasn't enough space for some operation (wouldn't be widened).
    /// --------------------------------------------------------------------------------------------
    pub const BufferError = error{NotEnoughSpace};

    ///       error      |
    /// -----------------|--------------------------------------------------------------------------
    /// OutOfBounds      | - When trying to access space outside the indexable memory span.
    /// --------------------------------------------------------------------------------------------
    pub const IndexError = error{OutOfBounds};

    ///       error      |                                  about
    /// -----------------|--------------------------------------------------------------------------
    /// OutOfRange       | - When the value is outside some designated value range.
    /// Overflow         | - When the value from a calculation would be too big to fit within its type.
    /// Underflow        | - When the value from a calculation would be too small to fit within its type.
    /// UnableToHandle   | - When the context can't handle a given value in any sensible way.
    /// --------------------------------------------------------------------------------------------
    pub const ValueError = error{
        OutOfRange,
        Overflow,
        Underflow,
        UnableToHandle,
    };
};

pub const modes = struct {
    /// Execution modes for functions that support branch optimization.
    ///
    ///    mode   |                                      about
    /// ----------|---------------------------------------------------------------------------------
    /// safe      | - Contains safety checks that may throw or panic.
    ///           | - The suggested mode for most situations, allowing for detection and
    ///           |   consequential handling of errors.
    ///           |
    /// uncheck   | - Fastest but unsafe, most conditional branches (e.g., safety checks) are pruned
    ///           |   to simpler control flows with the downside that undefined behaviors can be hit.
    /// --------------------------------------------------------------------------------------------
    pub const ExecMode = enum { safe, uncheck };

    /// Memory modes for data structures that support different memory handling methods.
    ///
    ///    mode   |                                      about
    /// ----------|---------------------------------------------------------------------------------
    /// alloc     | - Memory allocation is done on the heap, user should release by calling 'deinit'
    ///           | - Valid during *runtime*.
    ///           |
    /// buffer    | - Memory is static and passed as a buffer by the user.
    ///           | - Valid during *runtime* and *comptime*.
    ///           |
    /// comptime  | - Memory allocation is done in .rodata or (if not referenced runtime)
    ///           |   compiler's address space.
    ///           | - Valid during *comptime*.
    /// --------------------------------------------------------------------------------------------
    pub const MemoryMode = enum { alloc, buffer, @"comptime" };
};
