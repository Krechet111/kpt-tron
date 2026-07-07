#!/usr/bin/env bash
# Create a swap file so a transient memory spike swaps instead of triggering
# the OOM-killer (which likely corrupted the Tron state DB in the first place).
# Run as root:  sudo bash setup-swap.sh [SIZE]
set -euo pipefail

SWAPFILE="/swapfile"
SIZE="${1:-4G}"
SWAPPINESS=10

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: run as root (sudo bash $0)"; exit 1
fi

if swapon --show=NAME --noheadings 2>/dev/null | grep -qx "$SWAPFILE"; then
    echo "ℹ️  Swap already active on $SWAPFILE:"
    swapon --show
    exit 0
fi

echo ">>> Creating ${SIZE} swap file at ${SWAPFILE}"
if ! fallocate -l "$SIZE" "$SWAPFILE" 2>/dev/null; then
    echo "    fallocate unavailable, falling back to dd..."
    # Strip trailing G and convert to MiB count for dd.
    MB=$(( ${SIZE%G} * 1024 ))
    dd if=/dev/zero of="$SWAPFILE" bs=1M count="$MB" status=progress
fi

chmod 600 "$SWAPFILE"
mkswap "$SWAPFILE"
swapon "$SWAPFILE"

# Persist across reboots.
if ! grep -qsE "^\s*${SWAPFILE}\s" /etc/fstab; then
    echo "${SWAPFILE} none swap sw 0 0" >> /etc/fstab
    echo ">>> Added ${SWAPFILE} to /etc/fstab"
fi

# Low swappiness: only use swap under real pressure (avoid GC-hurting swap-out).
sysctl -w vm.swappiness=${SWAPPINESS}
if ! grep -qsE "^\s*vm.swappiness" /etc/sysctl.conf; then
    echo "vm.swappiness=${SWAPPINESS}" >> /etc/sysctl.conf
    echo ">>> Persisted vm.swappiness=${SWAPPINESS} in /etc/sysctl.conf"
fi

echo
echo "✅ Swap ready:"
swapon --show
echo
free -h
