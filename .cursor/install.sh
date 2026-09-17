#!/usr/bin/env bash
#
# Cloud Agent (Linux) environment bootstrap for NextSeason.
#
# NextSeason is an iOS/SwiftUI app; building or running the app itself requires
# macOS + Xcode and is not possible on a Linux Cloud Agent. This script installs
# the Linux tooling that *is* usable here:
#
#   * The Swift 6.2 toolchain, which provides `swift format` for linting the
#     Swift sources against the repo's .swift-format config (and `swiftc` for
#     syntax checks of platform-agnostic code).
#   * The system packages the toolchain needs at runtime.
#
# Python 3 (used by the helper scripts in Scripts/, which are standard-library
# only) already ships in the base image, so nothing extra is needed for those.
#
# The script is idempotent: it is safe to run repeatedly and skips the Swift
# download when a matching toolchain is already installed.

set -euo pipefail

SWIFT_VERSION="6.2"
SWIFT_TAG="swift-${SWIFT_VERSION}-RELEASE"
SWIFT_PLATFORM="ubuntu24.04"
SWIFT_URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu2404/${SWIFT_TAG}/${SWIFT_TAG}-${SWIFT_PLATFORM}.tar.gz"
SWIFT_ROOT="/opt/swift"

echo "==> Installing Swift toolchain runtime dependencies"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    binutils \
    git \
    curl \
    libc6-dev \
    libcurl4-openssl-dev \
    libedit2 \
    libgcc-13-dev \
    libncurses-dev \
    libpython3-dev \
    libsqlite3-0 \
    libstdc++-13-dev \
    libxml2-dev \
    libz3-dev \
    pkg-config \
    tzdata \
    unzip \
    zlib1g-dev

if /usr/local/bin/swift --version 2>/dev/null | grep -q "${SWIFT_TAG}"; then
    echo "==> Swift ${SWIFT_VERSION} already installed; skipping download"
else
    echo "==> Downloading Swift ${SWIFT_VERSION} (${SWIFT_PLATFORM})"
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "${tmp_dir}"' EXIT
    curl -fL -o "${tmp_dir}/swift.tar.gz" "${SWIFT_URL}"

    echo "==> Extracting to ${SWIFT_ROOT}"
    sudo mkdir -p "${SWIFT_ROOT}"
    sudo tar -xzf "${tmp_dir}/swift.tar.gz" -C "${SWIFT_ROOT}" --strip-components=1

    sudo ln -sf "${SWIFT_ROOT}/usr/bin/swift" /usr/local/bin/swift
    sudo ln -sf "${SWIFT_ROOT}/usr/bin/swiftc" /usr/local/bin/swiftc
    sudo ln -sf "${SWIFT_ROOT}/usr/bin/swift-format" /usr/local/bin/swift-format
fi

echo "==> Toolchain versions"
swift --version
python3 --version

echo "==> Environment bootstrap complete"
