#!/usr/bin/env bash

# find all .zig files and sum their line count, print
total_lines=$(find . -name "*.zig" -type f -not -path "*/.zig-cache/*" | xargs wc -l | tail -n 1 | awk '{print $1}')
echo "Lines of Code: ${total_lines}";
