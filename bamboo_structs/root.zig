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

pub const primitive = @import("./src/primitive/root.zig");

test {
    _ = primitive;
}
