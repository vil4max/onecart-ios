#!/bin/sh
set -e

echo "==> Xcode Cloud: running ci_post_clone.sh"

if [ -n "$CI_BUILD_NUMBER" ]; then
    echo "==> Setting CURRENT_PROJECT_VERSION to $CI_BUILD_NUMBER in project.pbxproj"
    find . -name "project.pbxproj" -exec sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*/CURRENT_PROJECT_VERSION = $CI_BUILD_NUMBER/g" {} +
    echo "==> Successfully updated build number to $CI_BUILD_NUMBER."
else
    echo "==> CI_BUILD_NUMBER not set; keeping current project version."
fi
