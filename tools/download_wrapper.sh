#!/usr/bin/env bash
# Download Manager Shell Wrapper
# =============================
# This script provides a shell interface to the Python download manager
# for easy integration with existing bash scripts.

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOAD_MANAGER="$SCRIPT_DIR/download_manager.py"

# Check if Python 3 is available
check_python3() {
    if ! command -v python3 >/dev/null 2>&1; then
        echo "Error: Python 3 is required for advanced download functionality" >&2
        return 1
    fi
    
    if [[ ! -f "$DOWNLOAD_MANAGER" ]]; then
        echo "Error: Download manager not found at $DOWNLOAD_MANAGER" >&2
        return 1
    fi
    
    return 0
}

# Enhanced curl replacement with Python download manager
# Usage: enhanced_curl <url> <output_file> [options]
enhanced_curl() {
    local url="$1"
    local output="$2"
    shift 2
    
    # Parse additional options
    local verify_checksum=""
    local algorithm="sha256"
    local retries="3"
    local timeout="30"
    local quiet=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verify-*)
                algorithm="${1#--verify-}"
                verify_checksum="$2"
                shift 2
                ;;
            --retries=*)
                retries="${1#--retries=}"
                shift
                ;;
            --timeout=*)
                timeout="${1#--timeout=}"
                shift
                ;;
            --quiet|-q)
                quiet="--quiet"
                shift
                ;;
            *)
                shift  # Skip unknown options
                ;;
        esac
    done
    
    # Try Python download manager first
    if check_python3 >/dev/null 2>&1; then
        local cmd="python3 \"$DOWNLOAD_MANAGER\" download"
        cmd="$cmd --retries=\"$retries\" --timeout=\"$timeout\""
        
        if [[ -n "$quiet" ]]; then
            cmd="$cmd --quiet"
        fi
        
        if [[ -n "$verify_checksum" ]]; then
            cmd="$cmd --verify-$algorithm=\"$verify_checksum\""
        fi
        
        cmd="$cmd \"$url\" \"$output\""
        
        if eval "$cmd"; then
            return 0
        else
            echo "Python download manager failed, falling back to curl..." >&2
        fi
    fi
    
    # Fallback to traditional curl
    if command -v curl >/dev/null 2>&1; then
        local curl_opts="-fL"
        if [[ -n "$quiet" ]]; then
            curl_opts="$curl_opts -s"
        fi
        
        if curl $curl_opts --connect-timeout "$timeout" "$url" -o "$output"; then
            # Verify checksum if provided
            if [[ -n "$verify_checksum" ]] && command -v python3 >/dev/null 2>&1; then
                python3 "$DOWNLOAD_MANAGER" verify "$output" "$verify_checksum" --algorithm="$algorithm"
                return $?
            fi
            return 0
        else
            return 1
        fi
    else
        echo "Error: Neither Python 3 nor curl is available for downloads" >&2
        return 1
    fi
}

# Download with automatic checksum verification for known file types
# Usage: secure_download <url> <output_file> [expected_checksum] [algorithm]
secure_download() {
    local url="$1"
    local output="$2"
    local checksum="$3"
    local algorithm="${4:-sha256}"
    
    if [[ -n "$checksum" ]]; then
        enhanced_curl "$url" "$output" "--verify-$algorithm" "$checksum"
    else
        enhanced_curl "$url" "$output"
    fi
}

# Batch download function
# Usage: batch_download <urls_file>
batch_download() {
    local urls_file="$1"
    
    if check_python3 >/dev/null 2>&1; then
        python3 "$DOWNLOAD_MANAGER" batch-download "$urls_file"
    else
        echo "Error: Python 3 required for batch downloads" >&2
        return 1
    fi
}

# Get download information
# Usage: get_download_info <url>
get_download_info() {
    local url="$1"
    
    if check_python3 >/dev/null 2>&1; then
        python3 "$DOWNLOAD_MANAGER" get-info "$url"
    else
        echo "Error: Python 3 required for download info" >&2
        return 1
    fi
}

# Main function for command-line usage
main() {
    case "${1:-}" in
        curl)
            shift
            enhanced_curl "$@"
            ;;
        secure)
            shift
            secure_download "$@"
            ;;
        batch)
            shift
            batch_download "$@"
            ;;
        info)
            shift
            get_download_info "$@"
            ;;
        check)
            check_python3
            ;;
        *)
            echo "Download Manager Shell Wrapper"
            echo ""
            echo "Usage:"
            echo "  $0 curl <url> <output> [options]     - Enhanced curl replacement"
            echo "  $0 secure <url> <output> [checksum] [algorithm] - Secure download with verification"  
            echo "  $0 batch <urls_file>                 - Batch download from file"
            echo "  $0 info <url>                        - Get download information"
            echo "  $0 check                             - Check if dependencies are available"
            echo ""
            echo "Options for curl command:"
            echo "  --verify-<algorithm> <checksum>      - Verify checksum after download"
            echo "  --retries=<number>                   - Number of retries (default: 3)"
            echo "  --timeout=<seconds>                  - Timeout per attempt (default: 30)"
            echo "  --quiet                              - Suppress progress output"
            ;;
    esac
}

# Allow script to be sourced for function usage or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi