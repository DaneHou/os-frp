#!/bin/sh

# Download and install FRP + ssserver-rust binaries
# Usage: setup.sh [frp|ssserver|all]

FRP_VERSION="0.61.1"
SS_VERSION="1.24.0"

FRP_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_freebsd_amd64.tar.gz"
SS_URL="https://github.com/shadowsocks/shadowsocks-rust/releases/download/v${SS_VERSION}/shadowsocks-v${SS_VERSION}.x86_64-unknown-freebsd.tar.xz"

INSTALL_DIR="/usr/local/bin"
TMP_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

install_frp() {
    # Check if already installed with correct version
    if [ -x "${INSTALL_DIR}/frpc" ]; then
        current=$("${INSTALL_DIR}/frpc" --version 2>/dev/null || echo "")
        if [ "$current" = "$FRP_VERSION" ]; then
            echo "FRP v${FRP_VERSION} already installed, skipping."
            return 0
        fi
    fi

    echo "Downloading FRP v${FRP_VERSION}..."
    fetch -o "${TMP_DIR}/frp.tar.gz" "$FRP_URL" || {
        echo "Failed to download FRP"
        return 1
    }

    echo "Extracting FRP..."
    tar -xzf "${TMP_DIR}/frp.tar.gz" -C "$TMP_DIR" || {
        echo "Failed to extract FRP"
        return 1
    }

    frp_dir="${TMP_DIR}/frp_${FRP_VERSION}_freebsd_amd64"
    if [ ! -d "$frp_dir" ]; then
        echo "FRP directory not found after extraction"
        return 1
    fi

    echo "Installing FRP binaries..."
    install -m 755 "${frp_dir}/frpc" "${INSTALL_DIR}/frpc"
    install -m 755 "${frp_dir}/frps" "${INSTALL_DIR}/frps"

    echo "FRP v${FRP_VERSION} installed successfully."
}

install_ssserver() {
    # Check if already installed with correct version
    if [ -x "${INSTALL_DIR}/ssserver" ]; then
        current=$("${INSTALL_DIR}/ssserver" --version 2>/dev/null | awk '{print $2}' || echo "")
        if [ "$current" = "$SS_VERSION" ]; then
            echo "ssserver v${SS_VERSION} already installed, skipping."
            return 0
        fi
    fi

    echo "Downloading shadowsocks-rust v${SS_VERSION}..."
    fetch -o "${TMP_DIR}/ss.tar.xz" "$SS_URL" || {
        echo "Failed to download shadowsocks-rust"
        return 1
    }

    echo "Extracting shadowsocks-rust..."
    xz -d "${TMP_DIR}/ss.tar.xz"
    tar -xf "${TMP_DIR}/ss.tar" -C "$TMP_DIR" || {
        echo "Failed to extract shadowsocks-rust"
        return 1
    }

    if [ ! -f "${TMP_DIR}/ssserver" ]; then
        echo "ssserver binary not found after extraction"
        return 1
    fi

    echo "Installing ssserver binary..."
    install -m 755 "${TMP_DIR}/ssserver" "${INSTALL_DIR}/ssserver"

    echo "ssserver v${SS_VERSION} installed successfully."
}

case "${1:-all}" in
    frp)
        install_frp
        ;;
    ssserver)
        install_ssserver
        ;;
    all)
        install_frp
        install_ssserver
        ;;
    *)
        echo "Usage: $0 [frp|ssserver|all]"
        exit 1
        ;;
esac
