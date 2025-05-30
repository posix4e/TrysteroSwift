#!/bin/bash

# Validation script for TrysteroSwift interop test setup
# This script checks if all dependencies and configurations are correct

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Validation functions
validate_node_environment() {
    log_info "Validating Node.js environment..."
    
    if ! command -v node &> /dev/null; then
        log_error "Node.js is not installed"
        return 1
    fi
    
    NODE_VERSION=$(node --version)
    log_success "Node.js version: $NODE_VERSION"
    
    if ! command -v npm &> /dev/null; then
        log_error "npm is not installed"
        return 1
    fi
    
    NPM_VERSION=$(npm --version)
    log_success "npm version: $NPM_VERSION"
    
    return 0
}

validate_swift_environment() {
    log_info "Validating Swift environment..."
    
    if ! command -v swift &> /dev/null; then
        log_error "Swift is not installed"
        return 1
    fi
    
    SWIFT_VERSION=$(swift --version | head -1)
    log_success "Swift version: $SWIFT_VERSION"
    
    # Check if we can build the package
    cd "$PROJECT_ROOT"
    if swift package resolve > /dev/null 2>&1; then
        log_success "Swift package dependencies resolved"
    else
        log_error "Failed to resolve Swift package dependencies"
        return 1
    fi
    
    return 0
}

validate_package_json() {
    log_info "Validating package.json..."
    
    cd "$SCRIPT_DIR"
    
    if [ ! -f "package.json" ]; then
        log_error "package.json not found"
        return 1
    fi
    
    # Check if package.json is valid JSON
    if ! node -e "JSON.parse(require('fs').readFileSync('package.json', 'utf8'))" > /dev/null 2>&1; then
        log_error "package.json is not valid JSON"
        return 1
    fi
    
    log_success "package.json is valid"
    
    # Check required dependencies
    if ! node -e "
        const pkg = JSON.parse(require('fs').readFileSync('package.json', 'utf8'));
        if (!pkg.dependencies || !pkg.dependencies.trystero) {
            process.exit(1);
        }
    " > /dev/null 2>&1; then
        log_error "Missing required dependency: trystero"
        return 1
    fi
    
    log_success "Required dependencies are listed"
    return 0
}

validate_test_files() {
    log_info "Validating test files..."
    
    # Check Node.js test harness
    if [ ! -f "$SCRIPT_DIR/trystero-node.js" ]; then
        log_error "Node.js test harness not found: trystero-node.js"
        return 1
    fi
    
    # Check if Node.js file is executable
    if ! node -c "$SCRIPT_DIR/trystero-node.js" > /dev/null 2>&1; then
        log_error "Node.js test harness has syntax errors"
        return 1
    fi
    
    log_success "Node.js test harness is valid"
    
    # Check Swift test file
    if [ ! -f "$PROJECT_ROOT/Tests/TrysteroSwiftTests/InteropTests.swift" ]; then
        log_error "Swift interop tests not found: InteropTests.swift"
        return 1
    fi
    
    log_success "Swift interop tests found"
    
    # Check test runner script
    if [ ! -f "$SCRIPT_DIR/run-interop-tests.sh" ]; then
        log_error "Test runner script not found: run-interop-tests.sh"
        return 1
    fi
    
    if [ ! -x "$SCRIPT_DIR/run-interop-tests.sh" ]; then
        log_warning "Test runner script is not executable, fixing..."
        chmod +x "$SCRIPT_DIR/run-interop-tests.sh"
    fi
    
    log_success "Test runner script is ready"
    return 0
}

validate_network_connectivity() {
    log_info "Validating network connectivity to Nostr relays..."
    
    RELAYS=("relay.damus.io" "nos.lol")
    
    for relay in "${RELAYS[@]}"; do
        if command -v nc &> /dev/null; then
            if timeout 5 nc -z "$relay" 443 > /dev/null 2>&1; then
                log_success "Can reach relay: $relay"
            else
                log_warning "Cannot reach relay: $relay (might be temporary)"
            fi
        elif command -v curl &> /dev/null; then
            if timeout 5 curl -s "https://$relay" > /dev/null 2>&1; then
                log_success "Can reach relay: $relay"
            else
                log_warning "Cannot reach relay: $relay (might be temporary)"
            fi
        else
            log_warning "Cannot test relay connectivity (no nc or curl available)"
            break
        fi
    done
    
    return 0
}

validate_ci_environment() {
    log_info "Validating CI environment..."
    
    if [ "$CI" = "true" ]; then
        log_info "Running in CI environment"
        
        # Check GitHub Actions specific environment
        if [ ! -z "$GITHUB_ACTIONS" ]; then
            log_success "GitHub Actions environment detected"
            log_info "Runner OS: ${RUNNER_OS:-unknown}"
            log_info "GitHub Workspace: ${GITHUB_WORKSPACE:-unknown}"
        fi
        
        # Check available resources
        if command -v nproc &> /dev/null; then
            CPU_COUNT=$(nproc)
            log_info "Available CPUs: $CPU_COUNT"
        fi
        
        if command -v free &> /dev/null; then
            MEMORY_INFO=$(free -h | grep '^Mem:' | awk '{print $2}')
            log_info "Available memory: $MEMORY_INFO"
        fi
    else
        log_info "Running in local environment"
    fi
    
    return 0
}

# Main validation
main() {
    log_info "Starting TrysteroSwift interop test validation..."
    log_info "Script directory: $SCRIPT_DIR"
    log_info "Project root: $PROJECT_ROOT"
    
    local errors=0
    
    validate_ci_environment || ((errors++))
    validate_node_environment || ((errors++))
    validate_swift_environment || ((errors++))
    validate_package_json || ((errors++))
    validate_test_files || ((errors++))
    validate_network_connectivity || ((errors++))
    
    echo ""
    echo "=========================================="
    if [ $errors -eq 0 ]; then
        log_success "All validations passed! Environment is ready for interop tests."
        echo "=========================================="
        return 0
    else
        log_error "$errors validation(s) failed. Please fix the issues above."
        echo "=========================================="
        return 1
    fi
}

# Run validation
main "$@"