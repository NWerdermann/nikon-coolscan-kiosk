#!/bin/bash
set -e

CMDLINE="/boot/firmware/cmdline.txt"
OVERLAY_PARAM="overlayroot=tmpfs:recurse=0"

case "${1:-}" in
    enable)
        # Install overlayroot if not present
        if ! dpkg -s overlayroot &>/dev/null; then
            echo "Installing overlayroot package..."
            sudo apt update && sudo apt install -y overlayroot
        fi

        if grep -q "$OVERLAY_PARAM" "$CMDLINE"; then
            echo "Overlay is already enabled."
            exit 0
        fi

        # Remount boot partition as read-write (may be read-only)
        sudo mount -o remount,rw /boot/firmware 2>/dev/null || true

        # Append parameter to the kernel command line
        sudo sed -i "s|$| $OVERLAY_PARAM|" "$CMDLINE"
        echo "Overlay enabled. Reboot to activate read-only mode."
        ;;

    disable)
        if ! grep -q "$OVERLAY_PARAM" "$CMDLINE"; then
            echo "Overlay is already disabled."
            exit 0
        fi

        # Remount boot partition as read-write (needed when overlay is active)
        sudo mount -o remount,rw /boot/firmware 2>/dev/null || true

        # Remove parameter from the kernel command line
        sudo sed -i "s| $OVERLAY_PARAM||" "$CMDLINE"
        echo "Overlay disabled. Reboot to restore read-write mode."
        ;;

    status)
        if grep -q "$OVERLAY_PARAM" "$CMDLINE"; then
            echo "Overlay is ENABLED (active after next reboot)."
        else
            echo "Overlay is DISABLED."
        fi
        ;;

    *)
        echo "Usage: $0 {enable|disable|status}"
        echo ""
        echo "  enable   - Activate read-only overlay on root filesystem"
        echo "  disable  - Deactivate overlay (for making changes)"
        echo "  status   - Show current overlay configuration"
        exit 1
        ;;
esac
