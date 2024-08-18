#!/bin/bash

# find all .zig files and count their lines
total_lines=$(find . -name "*.zig" -type f -not -path "*/.zig-cache/*" | xargs wc -l | tail -n 1 | awk '{print $1}')

echo "Lines of Code: ${total_lines}";
