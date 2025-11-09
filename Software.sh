#!/bin/bash

# This script now calls infrarust.sh which handles the complete infrarust installation
# https://crates.io/crates/infrarust

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/infrarust.sh"
