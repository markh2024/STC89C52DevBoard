#!/bin/bash
# Auto-upload script for STC89C52 using stcgal

HEX_FILE="main.hex"

# Detect serial port
detect_port() {
    for dev in /dev/ttyUSB* /dev/ttyACM*; do
        [ -e "$dev" ] && echo "$dev" && return
    done
    echo ""
}

PORT=$(detect_port)

if [ -z "$PORT" ]; then
    echo "No USB serial device found."
    echo "Please plug in your USB-to-serial adapter..."
    while [ -z "$PORT" ]; do
        sleep 1
        PORT=$(detect_port)
    done
    echo "Detected device: $PORT"
else
    echo "Detected serial device: $PORT"
fi

echo ""
echo "================================================="
echo " Ready to upload $HEX_FILE to STC89C52"
echo " Please RESET the board (press the reset button)"
echo "================================================="
echo ""

# Wait until user resets and MCU appears
sleep 1
stcgal -P stc89 -p "$PORT" -b 115200 "$HEX_FILE"
