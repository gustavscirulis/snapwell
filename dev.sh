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

# ── App Store archive & upload ──────────────────────────────────

release_fail() {
    printf "${RED}Error: %s${RESET}\n" "$1" >&2
    exit 1
}

run_release_command() {
    if command -v xcbeautify &>/dev/null; then
        "$@" 2>&1 | xcbeautify --quiet
    else
        "$@"
    fi
}

release_preflight() {
    local needs_xcodegen="${1:-false}"

    command -v xcodebuild &>/dev/null || release_fail "xcodebuild not found"
    if [[ "$needs_xcodegen" == "true" ]]; then
        command -v xcodegen &>/dev/null || release_fail "XcodeGen not found. Install it with: brew install xcodegen"
    fi
    local signing_identities
    signing_identities=$(security find-identity -v -p codesigning)
    [[ "$signing_identities" == *"Apple Distribution"* ]] \
        || release_fail "No Apple Distribution certificate found in Keychain"
}

confirm_app_store_upload() {
    local platform="$1"
    local version="$2"
    local build="$3"
    local response

    printf "\n${YELLOW}${BOLD}Publish %s %s (build %s)?${RESET}\n" "$platform" "$version" "$build"
    printf "Confirm this build number is higher than every %s build in App Store Connect.\n" "$platform"
    printf "This will archive and upload the app to Apple, but will not submit it for review. [y/N] "
    IFS= read -r response

    [[ "$response" == "y" || "$response" == "Y" ]]
}

publish_ios() {
    release_preflight false

    local project_dir="$SCRIPT_DIR/ios"
    local build_dir="$project_dir/build"
    local archive_path="$build_dir/Snapwell.xcarchive"
    local upload_dir="$build_dir/upload"
    local upload_options="$build_dir/ExportOptions-Upload.plist"
    local settings
    local version
    local build

    settings=$(xcodebuild -showBuildSettings \
        -project "$project_dir/Snapwell.xcodeproj" \
        -scheme Snapwell \
        -configuration Release \
        -destination 'generic/platform=iOS' 2>/dev/null)
    version=$(printf '%s\n' "$settings" | awk '/^[[:space:]]*MARKETING_VERSION = / {print $3; exit}')
    build=$(printf '%s\n' "$settings" | awk '/^[[:space:]]*CURRENT_PROJECT_VERSION = / {print $3; exit}')
    [[ -n "$version" && -n "$build" ]] || release_fail "Could not read the iOS version and build number"

    if ! confirm_app_store_upload "iOS" "$version" "$build"; then
        printf "${DIM}Upload cancelled.${RESET}\n"
        return
    fi

    printf "\n${BOLD}Archiving Snapwell for iOS...${RESET}\n\n"
    rm -rf "$build_dir"
    mkdir -p "$build_dir"

    run_release_command xcodebuild archive \
        -project "$project_dir/Snapwell.xcodeproj" \
        -scheme Snapwell \
        -configuration Release \
        -archivePath "$archive_path" \
        -allowProvisioningUpdates \
        -destination 'generic/platform=iOS'

    local app_info="$archive_path/Products/Applications/Snapwell.app/Info.plist"
    local extension_info="$archive_path/Products/Applications/Snapwell.app/PlugIns/ShareExtension.appex/Info.plist"
    [[ -f "$app_info" && -f "$extension_info" ]] \
        || release_fail "Archive is missing the iOS app or share-extension Info.plist"

    local archived_version
    local archived_build
    local extension_version
    local extension_build
    archived_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_info")
    archived_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_info")
    extension_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$extension_info")
    extension_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$extension_info")

    [[ "$archived_version" == "$version" && "$archived_build" == "$build" ]] \
        || release_fail "Archived iOS version does not match the confirmed version"
    [[ "$extension_version" == "$archived_version" && "$extension_build" == "$archived_build" ]] \
        || release_fail "The iOS app and share extension versions do not match"
    printf "${GREEN}✓ Verified iOS %s (build %s)${RESET}\n" "$archived_version" "$archived_build"

    cp "$project_dir/ExportOptions-AppStore.plist" "$upload_options"
    /usr/libexec/PlistBuddy -c 'Delete :destination' "$upload_options" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c 'Add :destination string upload' "$upload_options"

    printf "\n${BOLD}Uploading to App Store Connect...${RESET}\n\n"
    run_release_command xcodebuild -exportArchive \
        -archivePath "$archive_path" \
        -exportPath "$upload_dir" \
        -exportOptionsPlist "$upload_options" \
        -allowProvisioningUpdates

    printf "\n${GREEN}✓ Uploaded iOS %s (build %s) to App Store Connect${RESET}\n" "$archived_version" "$archived_build"
    print_review_next_steps
}

publish_mac() {
    release_preflight true

    local project_dir="$SCRIPT_DIR/macos"
    local build_dir="$project_dir/build"
    local archive_path="$build_dir/Snapwell.xcarchive"
    local upload_dir="$build_dir/upload"
    local upload_options="$build_dir/ExportOptions-Upload.plist"
    local version
    local build
    version=$(awk -F': ' '/MARKETING_VERSION:/ {gsub(/"/, "", $2); print $2; exit}' "$project_dir/project.yml")
    build=$(awk -F': ' '/CURRENT_PROJECT_VERSION:/ {print $2; exit}' "$project_dir/project.yml")
    [[ -n "$version" && -n "$build" ]] || release_fail "Could not read the Mac version and build number"

    if ! confirm_app_store_upload "macOS" "$version" "$build"; then
        printf "${DIM}Upload cancelled.${RESET}\n"
        return
    fi

    printf "\n${DIM}Generating the Mac project...${RESET}\n"
    cd "$project_dir"
    xcodegen generate
    scripts/post-xcodegen.sh

    printf "\n${BOLD}Archiving Snapwell for Mac...${RESET}\n\n"
    rm -rf "$build_dir"
    mkdir -p "$build_dir"

    run_release_command xcodebuild archive \
        -project Snapwell.xcodeproj \
        -scheme Snapwell \
        -configuration Release \
        -archivePath "$archive_path" \
        -allowProvisioningUpdates

    local app_info="$archive_path/Products/Applications/Snapwell.app/Contents/Info.plist"
    [[ -f "$app_info" ]] || release_fail "Archive is missing the Mac app Info.plist"

    local archived_version
    local archived_build
    archived_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_info")
    archived_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_info")
    [[ "$archived_version" == "$version" && "$archived_build" == "$build" ]] \
        || release_fail "Archived Mac version does not match the confirmed version"
    printf "${GREEN}✓ Verified macOS %s (build %s)${RESET}\n" "$archived_version" "$archived_build"

    cp "$project_dir/ExportOptions.plist" "$upload_options"
    /usr/libexec/PlistBuddy -c 'Delete :destination' "$upload_options" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c 'Add :destination string upload' "$upload_options"

    printf "\n${BOLD}Uploading to App Store Connect...${RESET}\n\n"
    run_release_command xcodebuild -exportArchive \
        -archivePath "$archive_path" \
        -exportPath "$upload_dir" \
        -exportOptionsPlist "$upload_options" \
        -allowProvisioningUpdates

    printf "\n${GREEN}✓ Uploaded macOS %s (build %s) to App Store Connect${RESET}\n" "$archived_version" "$archived_build"
    print_review_next_steps
}

print_review_next_steps() {
    printf "\n${DIM}App Store Connect still needs to process the build. Then add the build and What's New notes to the version and submit it for App Review.${RESET}\n"
}

choose_mac_action() {
    printf "\n${BOLD}Mac app${RESET}\n\n"
    local actions=("Run locally" "Publish to the App Store")
    local action
    select_option "${actions[@]}" && action=$? || action=$?

    case $action in
        0) run_mac ;;
        1) publish_mac ;;
    esac
}

choose_ios_action() {
    printf "\n${BOLD}iOS app${RESET}\n\n"
    local actions=("Run locally" "Publish to the App Store")
    local action
    select_option "${actions[@]}" && action=$? || action=$?

    case $action in
        0) run_ios ;;
        1) publish_ios ;;
    esac
}

# ── Main ────────────────────────────────────────────────────────

printf "\n${BOLD}Snapwell Dev Runner${RESET}\n\n"
printf "Select target:\n\n"

options=(
    "Mac app     →  run locally or publish"
    "iOS app     →  run locally or publish"
    "Website     →  Next.js dev server"
)
select_option "${options[@]}" && choice=$? || choice=$?

case $choice in
    0) choose_mac_action ;;
    1) choose_ios_action ;;
    2) run_site ;;
esac
