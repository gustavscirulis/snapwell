#!/bin/bash
# Run after xcodegen generate to fix file types that XcodeGen doesn't know about.

PBXPROJ="$(dirname "$0")/../Snapwell.xcodeproj/project.pbxproj"

# XcodeGen maps .icon to `wrapper.icon`; Xcode/actool needs `folder.iconcomposer.icon`
sed -i '' \
  's/lastKnownFileType = wrapper\.icon; path = AppIcon\.icon/lastKnownFileType = folder.iconcomposer.icon; path = AppIcon.icon/' \
  "$PBXPROJ"

echo "post-xcodegen: patched AppIcon.icon file type"
