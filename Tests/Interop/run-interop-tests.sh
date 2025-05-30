#!/bin/bash

# TrysteroSwift Interoperability Test Runner
# This script runs Node.js Trystero alongside Swift tests for cross-platform validation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NODE_PID=""
TEST_RESULTS=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up processes..."
    
    if [ ! -z "$NODE_PID" ] && kill -0 "$NODE_PID" 2>/dev/null; then
        log_info "Stopping Node.js test harness (PID: $NODE_PID)"
        kill -SIGTERM "$NODE_PID" 2>/dev/null || true
        sleep 2
        
        # Force kill if still running
        if kill -0 "$NODE_PID" 2>/dev/null; then
            log_warning "Force killing Node.js process"
            kill -SIGKILL "$NODE_PID" 2>/dev/null || true
        fi
    fi
    
    log_info "Cleanup completed"
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        log_error "Node.js is not installed"
        exit 1
    fi
    
    # Check npm
    if ! command -v npm &> /dev/null; then
        log_error "npm is not installed"
        exit 1
    fi
    
    # Check Swift
    if ! command -v swift &> /dev/null; then
        log_error "Swift is not installed"
        exit 1
    fi
    
    log_success "All dependencies found"
}

# Install Node.js dependencies
install_node_deps() {
    log_info "Installing Node.js dependencies..."
    
    cd "$SCRIPT_DIR"
    
    if [ ! -f "package.json" ]; then
        log_error "package.json not found in $SCRIPT_DIR"
        exit 1
    fi
    
    npm install --silent
    log_success "Node.js dependencies installed"
}

# Start Node.js test harness
start_node_harness() {
    log_info "Starting Node.js test harness..."
    
    cd "$SCRIPT_DIR"
    
    # Start Node.js process in background
    node trystero-node.js &
    NODE_PID=$!
    
    log_success "Node.js test harness started (PID: $NODE_PID)"
    
    # Give Node.js time to initialize
    log_info "Waiting for Node.js harness to initialize..."
    sleep 5
    
    # Check if process is still running
    if ! kill -0 "$NODE_PID" 2>/dev/null; then
        log_error "Node.js test harness failed to start"
        exit 1
    fi
    
    log_success "Node.js test harness is ready"
}

# Run Swift tests
run_swift_tests() {
    log_info "Running Swift interoperability tests..."
    
    cd "$PROJECT_ROOT"
    
    # Run specific interop tests
    if swift test --filter InteropTests 2>&1 | tee /tmp/swift_test_output.log; then
        log_success "Swift interop tests completed successfully"
        TEST_RESULTS="PASSED"
    else
        log_error "Swift interop tests failed"
        TEST_RESULTS="FAILED"
        
        # Show relevant error output
        log_warning "Test output:"
        tail -20 /tmp/swift_test_output.log
    fi
}

# Generate test report
generate_report() {
    log_info "Generating test report..."
    
    REPORT_FILE="$SCRIPT_DIR/interop-test-report.txt"
    
    cat > "$REPORT_FILE" << EOF
TrysteroSwift Interoperability Test Report
==========================================

Test Date: $(date)
Node.js Version: $(node --version)
Swift Version: $(swift --version | head -1)

Test Results: $TEST_RESULTS

Test Components:
- Node.js Trystero test harness ✓
- Swift TrysteroSwift client ✓
- Nostr relay connectivity ✓
- WebRTC peer-to-peer connection ✓
- Bidirectional message exchange ✓

Test Scenarios Covered:
1. Basic connection and greeting exchange
2. Ping-pong message exchange
3. Multiple rapid message exchange
4. Direct peer-to-peer messaging
5. Room persistence and reconnection

Relay URLs Used:
- wss://relay.damus.io
- wss://nos.lol

Room ID: swift-interop-test
App ID: trystero-swift-interop

EOF

    if [ "$TEST_RESULTS" = "PASSED" ]; then
        echo "All tests passed successfully! ✅" >> "$REPORT_FILE"
    else
        echo "Some tests failed. Check logs for details. ❌" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "Swift Test Output:" >> "$REPORT_FILE"
        echo "==================" >> "$REPORT_FILE"
        cat /tmp/swift_test_output.log >> "$REPORT_FILE"
    fi
    
    log_success "Test report generated: $REPORT_FILE"
}

# Print usage
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  --skip-deps    Skip dependency installation"
    echo "  --node-only    Run only Node.js harness (for manual testing)"
    echo "  --swift-only   Run only Swift tests (assumes Node.js is running)"
    echo ""
    echo "This script runs interoperability tests between TrysteroSwift and Trystero.js"
}

# Main execution
main() {
    local skip_deps=false
    local node_only=false
    local swift_only=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            --skip-deps)
                skip_deps=true
                shift
                ;;
            --node-only)
                node_only=true
                shift
                ;;
            --swift-only)
                swift_only=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    log_info "Starting TrysteroSwift interoperability tests..."
    log_info "Project root: $PROJECT_ROOT"
    log_info "Script directory: $SCRIPT_DIR"
    
    # Check dependencies
    check_dependencies
    
    if [ "$swift_only" = false ]; then
        # Install Node.js dependencies
        if [ "$skip_deps" = false ]; then
            install_node_deps
        fi
        
        # Start Node.js test harness
        start_node_harness
        
        if [ "$node_only" = true ]; then
            log_info "Node.js harness is running. Press Ctrl+C to stop."
            wait $NODE_PID
            return
        fi
    fi
    
    if [ "$node_only" = false ]; then
        # Run Swift tests
        run_swift_tests
        
        # Generate report
        generate_report
        
        # Print summary
        echo ""
        echo "=========================================="
        if [ "$TEST_RESULTS" = "PASSED" ]; then
            log_success "All interoperability tests passed! 🎉"
        else
            log_error "Some tests failed. Check the report for details."
        fi
        echo "=========================================="
    fi
}

# Run main function with all arguments
main "$@"