//! Author: palsmo
//! Status: Done
//! About: Shared Components Among Data Structures
//!
//! Cache Locality Scale:
//!
//!  cache loc |
//! -----------|------------------------------------------------------------------------------------
//! good       | Contiguous or mostly contiguous memory layout with minimal fragmentation.
//!            | Example: Well-managed array based structure...
//!            |
//! decent     | Non-contiguous but structured memory layout with some locality.
//!            | Example: Balanced tree structure, skip list...
//!            |
//! poor       | Highly fragmented or scattered memory layout with little locality.
//!            | Example: Linked list, scattered hash table...
//! ------------------------------------------------------------------------------------------------

/// Memory modes for data structures that support different memory handling methods.
///
///    mode   |                                        about
/// ----------|-------------------------------------------------------------------------------------
/// .Alloc    | - Memory allocation is done on the heap, user should release by calling 'deinit'.
///           | - Valid during _runtime_.
///           |
/// .Buffer   | - Memory is static and passed as a buffer by the user.
///           | - Valid during _runtime_ and _comptime_.
///           |
/// .Comptime | - Memory allocation is done in .rodata or (if not referenced runtime) compiler's
///           |   address space.
///           | - Valid during _comptime_.
/// ------------------------------------------------------------------------------------------------
pub const MemoryMode = enum { Alloc, Buffer, Comptime };

///     error    |                                       about
/// -------------|----------------------------------------------------------------------------------
/// .Overflow    | - When trying to access space **above** capacity which wouldn't be widened.
/// .Underflow   | - When trying to access space **below** capacity which wouldn't be widened.
/// ------------------------------------------------------------------------------------------------
pub const BufferError = error{ Overflow, Underflow, NotEnoughSpace };

///     error    |
/// -------------|----------------------------------------------------------------------------------
/// .OutOfBounds | - When trying to access space outside the indexable memory span.
/// ------------------------------------------------------------------------------------------------
pub const IndexError = error{OutOfBounds};
