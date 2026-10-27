#!/bin/bash

# This script generates a coverage summary from coverage/lcov.info
# It excludes generated files (.g.dart, .drift.dart, .freezed.dart, and generated/ directories)

LCOV_FILE="coverage/lcov.info"

if [ ! -f "$LCOV_FILE" ]; then
  echo "Error: $LCOV_FILE not found. Run 'flutter test --coverage' first."
  exit 1
fi

echo "Per-file coverage (excluding generated files):"
echo "------------------------------------------------"

# Per-file summary
awk -F: '
  /^SF:/ { file = $2; }
  /^LH:/ { lh[file] = $2; }
  /^LF:/ { lf[file] = $2; }
  END {
    for (f in lf) {
      if (f !~ /(\.g\.dart|\.drift\.dart|\.freezed\.dart|generated\/)/) {
        if (lf[f] > 0) {
          printf "%6.2f%% | %s\n", (lh[f]/lf[f])*100, f;
        }
      }
    }
  }' "$LCOV_FILE" | sort -n

echo "------------------------------------------------"
echo "Core Logic Total Coverage:"

# Total summary
awk '
  BEGIN { RS = "end_of_record\n" }
  !/SF:.*(\.g\.dart|\.drift\.dart|\.freezed\.dart|generated\/)/ {
    split($0, lines, "\n");
    for (i in lines) {
      if (lines[i] ~ /^LH:/) {
        split(lines[i], parts, ":");
        lh += parts[2];
      }
      if (lines[i] ~ /^LF:/) {
        split(lines[i], parts, ":");
        lf += parts[2];
      }
    }
  }
  END {
    if (lf > 0) printf "Lines Hit: %d, Total Lines: %d, Coverage: %.2f%%\n", lh, lf, (lh/lf)*100;
    else print "No lines found";
  }' "$LCOV_FILE"
