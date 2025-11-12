#!/bin/bash

# =========================================================
#  STC89C52 Development Environment Setup Script
#  For Debian/Ubuntu Linux systems
# =========================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo "=========================================="
echo "  STC89C52 Development Setup"
echo "=========================================="
echo ""

# =========================================================
#  Check if running on Linux
# =========================================================
echo -e "${BLUE}🔍 Checking operating system...${NC}"
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo -e "${RED}❌ This script is designed for Linux systems only.${NC}"
    echo -e "${RED}   Detected OS: $OSTYPE${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Linux detected${NC}"
echo ""

# =========================================================
#  Check if running as root (not recommended)
# =========================================================
if [ "$EUID" -eq 0 ]; then 
    echo -e "${YELLOW}⚠️  Warning: Running as root is not recommended.${NC}"
    echo -e "${YELLOW}   Consider running as a regular user.${NC}"
    echo ""
fi

# =========================================================
#  Update and upgrade system
# =========================================================
echo -e "${BLUE}📦 Updating package lists...${NC}"
sudo apt update

echo ""
echo -e "${BLUE}⬆️  Upgrading installed packages...${NC}"
echo -e "${YELLOW}   (This may take a few minutes)${NC}"
sudo apt upgrade -y

echo ""
echo -e "${GREEN}✓ System updated${NC}"
echo ""

# =========================================================
#  Check and install dependencies
# =========================================================
echo -e "${BLUE}🔧 Checking and installing dependencies...${NC}"

# Check for SDCC
if ! command -v sdcc &> /dev/null; then
    echo "   Installing SDCC (Small Device C Compiler)..."
    sudo apt install -y sdcc
else
    echo -e "   ${GREEN}✓ SDCC already installed${NC}"
fi

# Check for Python3
if ! command -v python3 &> /dev/null; then
    echo "   Installing Python3..."
    sudo apt install -y python3
else
    echo -e "   ${GREEN}✓ Python3 already installed${NC}"
fi

# Check for python3-setuptools
if ! dpkg -l | grep -q python3-setuptools; then
    echo "   Installing python3-setuptools..."
    sudo apt install -y python3-setuptools
else
    echo -e "   ${GREEN}✓ python3-setuptools already installed${NC}"
fi

# Check for git
if ! command -v git &> /dev/null; then
    echo "   Installing git..."
    sudo apt install -y git
else
    echo -e "   ${GREEN}✓ git already installed${NC}"
fi

# Install pip if not present
if ! command -v pip3 &> /dev/null; then
    echo "   Installing pip3..."
    sudo apt install -y python3-pip
else
    echo -e "   ${GREEN}✓ pip3 already installed${NC}"
fi

echo ""
echo -e "${GREEN}✓ All dependencies installed${NC}"
echo ""

# =========================================================
#  Clone and install stcgal
# =========================================================
echo -e "${BLUE}📥 Installing stcgal (STC microcontroller programmer)...${NC}"

# Create temporary directory for stcgal installation
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

echo "   Cloning stcgal repository..."
git clone https://github.com/grigorig/stcgal.git
cd stcgal

echo "   Installing stcgal..."
sudo python3 setup.py install

# Clean up
cd ~
sudo rm -rf "$TEMP_DIR"

echo -e "${GREEN}✓ stcgal installed successfully${NC}"
echo ""

# =========================================================
#  Setup user permissions for serial port access
# =========================================================
echo -e "${BLUE}🔐 Setting up serial port permissions...${NC}"
if groups | grep -q dialout; then
    echo -e "   ${GREEN}✓ User already in 'dialout' group${NC}"
else
    echo "   Adding user to 'dialout' group..."
    sudo usermod -a -G dialout $USER
    echo -e "   ${YELLOW}⚠️  You will need to log out and back in for group changes to take effect${NC}"
fi
echo ""

# =========================================================
#  Create project directory
# =========================================================
PROJECT_DIR="$HOME/stc89c52_project"
echo -e "${BLUE}📁 Creating project directory...${NC}"

if [ -d "$PROJECT_DIR" ]; then
    echo -e "${YELLOW}   Project directory already exists: $PROJECT_DIR${NC}"
    read -p "   Overwrite existing files? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}   Skipping file creation. Existing files preserved.${NC}"
        PROJECT_DIR=""
    fi
fi

if [ -n "$PROJECT_DIR" ]; then
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"

    # =========================================================
    #  Create blink.c
    # =========================================================
    echo "   Creating blink.c..."
    cat > blink.c << 'EOF'
#include <8051.h>  // SDCC 8051 header

void delay_ms(unsigned int ms) {
    unsigned int i, j;
    for (i = 0; i < ms; i++)
        for (j = 0; j < 120; j++); // Rough delay loop
}

void main(void) {
    P1 = 0x00; // Set port 1 as output

    while (1) {
        P1 ^= 0x01;   // Toggle P1.0 (pin for LED)
        delay_ms(500);
    }
}
EOF

    # =========================================================
    #  Create Makefile
    # =========================================================
    echo "   Creating Makefile..."
    cat > Makefile << 'EOF'
# =========================================================
#  Makefile for STC89C52 (Debian/Linux)
#  Auto-compiles, shows assembly, and uploads via stcgal
# =========================================================

TARGET = blink
SRC = $(TARGET).c
CC = sdcc
OBJCOPY = packihx
UPLOAD = stcgal
BAUD = 115200

# Build artifacts
IHX = $(TARGET).ihx
HEX = $(TARGET).hex
ASM = $(TARGET).asm
LST = $(TARGET).lst
SYM = $(TARGET).sym

# =========================================================
#  Detect serial port automatically (USB0 first, then ACM)
# =========================================================
PORT := $(shell ls /dev/ttyUSB* 2>/dev/null | head -n 1)
ifeq ($(PORT),)
    PORT := $(shell ls /dev/ttyACM* 2>/dev/null | head -n 1)
endif

# =========================================================
#  Declare phony targets
# =========================================================
.PHONY: all upload showasm asm help clean check-tools

# =========================================================
#  Default target: check tools, compile, show assembly
# =========================================================
all: check-tools $(HEX) showasm

# =========================================================
#  Check if required tools are installed
# =========================================================
check-tools:
	@which $(CC) > /dev/null || (echo "❌ sdcc not found. Install with: sudo apt install sdcc" && exit 1)
	@which $(OBJCOPY) > /dev/null || (echo "❌ packihx not found. Install with: sudo apt install sdcc" && exit 1)
	@which $(UPLOAD) > /dev/null || (echo "❌ stcgal not found. Install with: pip3 install stcgal" && exit 1)
	@echo "✓ All required tools found"

# =========================================================
#  Compile and link
# =========================================================
$(HEX): $(SRC)
	@echo "🧩 Compiling $(SRC) ..."
	$(CC) -mmcs51 --code-size 8192 --verbose $(SRC)
	@echo "🔧 Packing to HEX ..."
	$(OBJCOPY) $(IHX) > $(HEX)
	@echo "✅ Build complete → $(HEX)"

# =========================================================
#  Upload target
# =========================================================
upload: all
	@if [ -z "$(PORT)" ]; then \
		echo "❌ No serial device found. Plug in your USB-to-serial adapter."; \
		echo "   Looking for: /dev/ttyUSB* or /dev/ttyACM*"; \
		exit 1; \
	else \
		echo "🚀 Uploading $(HEX) via $(PORT) at $(BAUD) baud ..."; \
		$(UPLOAD) -p $(PORT) -b $(BAUD) $(HEX); \
	fi

# =========================================================
#  Alternative: upload with manual port specification
#  Usage: make upload-manual PORT=/dev/ttyUSB0
# =========================================================
upload-manual: all
	@if [ -z "$(PORT)" ]; then \
		echo "❌ Please specify PORT. Example: make upload-manual PORT=/dev/ttyUSB0"; \
		exit 1; \
	else \
		echo "🚀 Uploading $(HEX) via $(PORT) at $(BAUD) baud ..."; \
		$(UPLOAD) -p $(PORT) -b $(BAUD) $(HEX); \
	fi

# =========================================================
#  Assembly viewing options
# =========================================================
.SILENT: showasm
showasm:
	@echo ""
	@echo "=== 🧠 First 25 lines of $(ASM) ==="
	@echo ""
	@if [ -f $(ASM) ]; then \
		head -n 25 $(ASM) | sed 's/^/    /'; \
		echo ""; \
		echo "[...] (Full assembly in $(ASM) and $(LST))"; \
	else \
		echo "❌ No assembly file found. Run 'make' first."; \
	fi

asm:
	@echo "🧾 Opening full assembly in VS Code..."
	@if [ -f $(ASM) ]; then \
		code $(ASM); \
	else \
		echo "❌ No assembly file found. Run 'make' first."; \
	fi

# =========================================================
#  List detected serial ports
# =========================================================
list-ports:
	@echo "🔌 Detected serial ports:"
	@ls -1 /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || echo "   (none found)"

# =========================================================
#  Show build information
# =========================================================
info:
	@echo ""
	@echo "📊 Build Configuration"
	@echo "====================="
	@echo "Target:       $(TARGET)"
	@echo "Source:       $(SRC)"
	@echo "Output:       $(HEX)"
	@echo "Compiler:     $(CC)"
	@echo "Upload tool:  $(UPLOAD)"
	@echo "Baud rate:    $(BAUD)"
	@echo "Serial port:  $(if $(PORT),$(PORT),(none detected))"
	@echo ""

# =========================================================
#  Help / usage instructions
# =========================================================
help:
	@echo ""
	@echo "📖 STC89C52 Makefile Usage Instructions"
	@echo "=========================================="
	@echo ""
	@echo "Building:"
	@echo "  make              Compiles, generates .hex, shows top 25 lines of assembly"
	@echo "  make check-tools  Verifies all required tools are installed"
	@echo ""
	@echo "Uploading:"
	@echo "  make upload       Builds (if needed) and uploads to first detected serial port"
	@echo "  make upload-manual PORT=/dev/ttyUSB0  Upload to specific port"
	@echo ""
	@echo "Assembly viewing:"
	@echo "  make showasm      Prints the first 25 lines of the .asm file"
	@echo "  make asm          Opens the full .asm file in VS Code"
	@echo ""
	@echo "Utilities:"
	@echo "  make list-ports   Shows all detected serial devices"
	@echo "  make info         Display build configuration"
	@echo "  make clean        Removes all build outputs"
	@echo "  make help         Shows this help message"
	@echo ""
	@echo "Configuration:"
	@echo "  Change baud rate: make upload BAUD=57600"
	@echo "  Change target:    make TARGET=myproject"
	@echo ""

# =========================================================
#  Cleanup
# =========================================================
clean:
	rm -f *.asm *.lst *.rel *.rst *.sym *.ihx *.hex *.map *.lk *.mem
	@echo "🧹 Clean complete."
EOF

    echo -e "${GREEN}✓ Project files created in: $PROJECT_DIR${NC}"
fi

# =========================================================
#  Display completion message and instructions
# =========================================================
echo ""
echo "=========================================="
echo -e "${GREEN}✅ Setup Complete!${NC}"
echo "=========================================="
echo ""
echo -e "${BLUE}📍 Project Location:${NC}"
echo "   $PROJECT_DIR"
echo ""
echo -e "${BLUE}🚀 Quick Start Guide:${NC}"
echo ""
echo "1. Navigate to project directory:"
echo -e "   ${YELLOW}cd $PROJECT_DIR${NC}"
echo ""
echo "2. Build your project:"
echo -e "   ${YELLOW}make${NC}"
echo "   (Compiles blink.c and shows assembly preview)"
echo ""
echo "3. Check available serial ports:"
echo -e "   ${YELLOW}make list-ports${NC}"
echo ""
echo "4. Upload to microcontroller:"
echo -e "   ${YELLOW}make upload${NC}"
echo "   (Auto-detects serial port and uploads)"
echo ""
echo "   Or specify port manually:"
echo -e "   ${YELLOW}make upload-manual PORT=/dev/ttyUSB0${NC}"
echo ""
echo "5. View all available commands:"
echo -e "   ${YELLOW}make help${NC}"
echo ""
echo -e "${BLUE}📋 Other Useful Commands:${NC}"
echo -e "   ${YELLOW}make clean${NC}        - Remove build files"
echo -e "   ${YELLOW}make info${NC}         - Show build configuration"
echo -e "   ${YELLOW}make asm${NC}          - View full assembly in VS Code"
echo ""
echo -e "${BLUE}🔌 Hardware Setup:${NC}"
echo "   1. Connect your STC89C52 via USB-to-serial adapter"
echo "   2. The Makefile will auto-detect the serial port"
echo "   3. Run 'make upload' to program the chip"
echo ""

# Check if user needs to re-login for dialout group
if ! groups | grep -q dialout; then
    echo -e "${YELLOW}⚠️  IMPORTANT: You were added to the 'dialout' group${NC}"
    echo -e "${YELLOW}   Please log out and back in for serial port access${NC}"
    echo ""
fi

echo -e "${GREEN}Happy coding! 🎉${NC}"
echo ""
