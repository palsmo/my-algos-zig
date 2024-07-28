//! Author: palsmo
//! Status: Done
//! About: Shared Components Among Data Structures

///    type   |                            about
/// ----------|-------------------------------------------------------------
/// .Alloc    | - Any memory allocation is done on the heap.
///           | - User should release memory after use by calling 'deinit'.
///           | - Dependant Struct is valid only during _runtime_.
///           |
/// .Buffer   | - Work with static space in user passed buffer.
///           | - Certain fields in `options` will always be ignored:
///           |   _init_capacity_, _growable_ and _shrinkable_.
///           | - Dependant Struct is valid only during _comptime_ or _runtime_.
///           |
/// .Comptime | - Any memory allocation is done in .rodata or
///           |   (if not referenced runtime) compiler's address space.
///           | - Dependant Struct is valid only during _comptime_.
pub const MemoryMode = enum { Alloc, Buffer, Comptime };
