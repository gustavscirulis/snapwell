#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[36m'
GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
RESET='\033[0m'
CLEAR_LINE='\033[2K'

# ── Arrow-key menu ──────────────────────────────────────────────

select_option() {
    local options=("$@")
    local selected=0
    local count=${#options[@]}

    # Hide cursor
    printf '\033[?25l'
    trap 'printf "\033[?25h"' EXIT

    # Draw initial menu
    for i in "${!options[@]}"; do
        if [[ $i -eq $selected ]]; then
            printf "  ${CYAN}▸ %s${RESET}\n" "${options[$i]}"
        else
            printf "    %s\n" "${options[$i]}"
        fi
    done

    while true; do
        # Read a single keypress
        IFS= read -rsn1 key

        # Arrow keys send ESC [ A/B sequences
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 seq
            case "$seq" in
                '[A') # Up
                    ((selected > 0)) && ((selected--))
                    ;;
                '[B') # Down
                    ((selected < count - 1)) && ((selected++))
                    ;;
            esac
        elif [[ "$key" == "" ]]; then
            # Enter pressed
            printf '\033[?25h'
            echo
            return $selected
        fi

        # Redraw: move cursor up, overwrite
        printf "\033[${count}A"
        for i in "${!options[@]}"; do
            if [[ $i -eq $selected ]]; then
                printf "${CLEAR_LINE}  ${CYAN}▸ %s${RESET}\n" "${options[$i]}"
            else
                printf "${CLEAR_LINE}    %s\n" "${options[$i]}"
            fi
        done
    done
}

# ── Mac build & run ─────────────────────────────────────────────

run_mac() {
    printf "\n${BOLD}Building Snapwell for Mac...${RESET}\n\n"

    cd "$SCRIPT_DIR/macos"

    printf "${DIM}Building...${RESET}\n"
    local build_dir
    build_dir=$(xcodebuild -showBuildSettings \
        -project Snapwell.xcodeproj \
        -scheme Snapwell \
        -configuration Debug \
        2>/dev/null | grep '^\s*BUILT_PRODUCTS_DIR' | awk '{print $3}')

    xcodebuild build \
        -project Snapwell.xcodeproj \
        -scheme Snapwell \
        -configuration Debug \
        -destination 'platform=macOS' \
        2>&1 | tail -3

    local app_path="$build_dir/Snapwell.app"
    if [[ ! -d "$app_path" ]]; then
        printf "${RED}Build failed — app not found at %s${RESET}\n" "$app_path"
        exit 1
    fi

    printf "\n${GREEN}✓ Build succeeded${RESET}\n"
    printf "${DIM}Launching %s${RESET}\n" "$app_path"
    open "$app_path"
}

# ── iOS build & run ─────────────────────────────────────────────

run_ios() {
    printf "\n${BOLD}Building Snapwell for iOS...${RESET}\n\n"

    # Try connected iPhone first, fall back to simulator
    printf "${DIM}Looking for connected iPhone...${RESET}\n"
    local device_line
    device_line=$(xcrun devicectl list devices 2>/dev/null | grep -i 'iphone' | grep -E 'connected|available' | head -1 || true)

    if [[ -n "$device_line" ]]; then
        run_ios_device "$device_line"
    else
        printf "${YELLOW}No connected iPhone found — using Simulator${RESET}\n"
        run_ios_simulator
    fi
}

run_ios_device() {
    local device_line="$1"

    local device_id
    device_id=$(echo "$device_line" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}')
    local device_name
    device_name=$(echo "$device_line" | awk -F'   ' '{gsub(/^[ \t]+|[ \t]+$/, "", $1); print $1}')

    printf "${GREEN}Found: %s${RESET} ${DIM}(%s)${RESET}\n" "$device_name" "$device_id"

    cd "$SCRIPT_DIR/ios"

    printf "${DIM}Building...${RESET}\n"
    xcodebuild build \
        -project Snapwell.xcodeproj \
        -scheme Snapwell \
        -configuration Debug \
        -destination "platform=iOS,id=$device_id" \
        -allowProvisioningUpdates \
        2>&1 | tail -3

    local build_dir
    build_dir=$(xcodebuild -showBuildSettings \
        -project Snapwell.xcodeproj \
        -scheme Snapwell \
        -configuration Debug \
        -destination "platform=iOS,id=$device_id" \
        2>/dev/null | grep '^\s*BUILT_PRODUCTS_DIR' | awk '{print $3}')

    local app_path="$build_dir/Snapwell.app"
    if [[ ! -d "$app_path" ]]; then
        printf "${RED}Build failed — app not found at %s${RESET}\n" "$app_path"
        exit 1
    fi

    printf "\n${GREEN}✓ Build succeeded${RESET}\n"

    printf "${DIM}Installing on %s...${RESET}\n" "$device_name"
    local install_output
    install_output=$(xcrun devicectl device install app --device "$device_id" "$app_path" 2>&1)
    echo "$install_output"

    local bundle_id
    bundle_id=$(echo "$install_output" | grep 'bundleID:' | awk '{print $3}')
    bundle_id="${bundle_id:-co.snapwell.app}"

    printf "${DIM}Launching...${RESET}\n"
    xcrun devicectl device process launch --device "$device_id" "$bundle_id" 2>&1

    printf "${GREEN}✓ Snapwell is running on %s${RESET}\n" "$device_name"
}

run_ios_simulator() {
    local sim_name="iPhone 17 Pro"
    local sim_id
    sim_id=$(xcrun simctl list devices available | grep "$sim_name" | head -1 | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}')

    if [[ -z "$sim_id" ]]; then
        printf "${RED}Error: No '$sim_name' simulator found.${RESET}\n"
        exit 1
    fi

    printf "${GREEN}Using simulator: %s${RESET} ${DIM}(%s)${RESET}\n" "$sim_name" "$sim_id"

    cd "$SCRIPT_DIR/ios"

    printf "${DIM}Booting simulator...${RESET}\n"
    xcrun simctl boot "$sim_id" 2>/dev/null || true
    open -a Simulator

    printf "${DIM}Building...${RESET}\n"
    xcodebuild build \
        -project Snapwell.xcodeproj \
        -scheme Snapwell \
        -configuration Debug \
        -destination "platform=iOS Simulator,id=$sim_id" \
        2>&1 | tail -3

    local build_dir
    build_dir=$(xcodebuild -showBuildSettings \
        -project Snapwell.xcodeproj \
        -scheme Snapwell \
        -configuration Debug \
        -destination "platform=iOS Simulator,id=$sim_id" \
        2>/dev/null | grep '^\s*BUILT_PRODUCTS_DIR' | awk '{print $3}')

    local app_path="$build_dir/Snapwell.app"
    if [[ ! -d "$app_path" ]]; then
        printf "${RED}Build failed — app not found at %s${RESET}\n" "$app_path"
        exit 1
    fi

    printf "\n${GREEN}✓ Build succeeded${RESET}\n"

    printf "${DIM}Installing on simulator...${RESET}\n"
    xcrun simctl install "$sim_id" "$app_path"

    printf "${DIM}Launching...${RESET}\n"
    xcrun simctl launch "$sim_id" "co.snapwell.app"

    printf "${GREEN}✓ Snapwell is running on %s simulator${RESET}\n" "$sim_name"
}

# ── Website dev server ──────────────────────────────────────────

run_site() {
    printf "\n${BOLD}Starting Snapwell website dev server...${RESET}\n\n"

    cd "$SCRIPT_DIR/site"

    if [[ ! -d node_modules ]]; then
        printf "${DIM}Installing dependencies...${RESET}\n"
        npm install
    fi

    printf "${GREEN}✓ Starting at http://localhost:3000${RESET}\n\n"
    npm run dev
}

# ── Main ────────────────────────────────────────────────────────

printf "\n${BOLD}Snapwell Dev Runner${RESET}\n\n"
printf "Select target:\n\n"

options=("Mac app     →  build & run locally" "iOS app     →  build & run on iPhone" "Website     →  Next.js dev server")
select_option "${options[@]}" && choice=$? || choice=$?

case $choice in
    0) run_mac ;;
    1) run_ios ;;
    2) run_site ;;
esac
