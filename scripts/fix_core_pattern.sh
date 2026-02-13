#!/bin/bash
# Fix Linux core_pattern so AFL can run without aborting.
# Must be run with sudo. Run once per boot (or set persistently).
#
# Error this fixes:
#   PROGRAM ABORT : Pipe at the beginning of 'core_pattern'

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (sudo)."
    echo "Usage: sudo $0"
    exit 1
fi

echo "Current core_pattern: $(cat /proc/sys/kernel/core_pattern)"
echo core >/proc/sys/kernel/core_pattern
echo "New core_pattern: $(cat /proc/sys/kernel/core_pattern)"
echo "Done. AFL should no longer abort on core_pattern."
echo ""
echo "To make this persistent across reboots, add to /etc/sysctl.conf:"
echo "  kernel.core_pattern=core"
echo "Then run: sysctl -p"
