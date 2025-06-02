#!/bin/bash

# Test runner script for TrysteroSwift interoperability tests

echo "🧪 TrysteroSwift Interoperability Test Suite"
echo "==========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    echo -e "${YELLOW}📦 Installing dependencies...${NC}"
    npm install
    echo ""
fi

# Kill any existing relay
echo -e "${YELLOW}🔄 Cleaning up any existing relay processes...${NC}"
pkill -f "node test-relay.js" 2>/dev/null || true
sleep 1

# Start the relay in background
echo -e "${GREEN}🚀 Starting local Nostr relay on ws://localhost:7447...${NC}"
npm run test-relay &
RELAY_PID=$!
sleep 2

# Function to cleanup on exit
cleanup() {
    echo ""
    echo -e "${YELLOW}🧹 Cleaning up...${NC}"
    kill $RELAY_PID 2>/dev/null || true
    pkill -f "node test-relay.js" 2>/dev/null || true
}
trap cleanup EXIT

# Check if relay is running
if ! ps -p $RELAY_PID > /dev/null; then
    echo -e "${RED}❌ Failed to start relay${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Relay is running (PID: $RELAY_PID)${NC}"
echo ""

# Menu
echo "Select a test to run:"
echo "1) Basic interop test (test.js)"
echo "2) Debug test with verbose logging"
echo "3) Interactive chat demo"
echo "4) Swift integration test"
echo "5) Run all tests"
echo ""

read -p "Enter choice (1-5): " choice

case $choice in
    1)
        echo ""
        echo -e "${YELLOW}🧪 Running basic interop test...${NC}"
        node test.js
        ;;
    2)
        echo ""
        echo -e "${YELLOW}🔍 Running debug test...${NC}"
        DEBUG='*' node debug-test.js
        ;;
    3)
        echo ""
        echo -e "${YELLOW}💬 Starting chat demo...${NC}"
        echo "Open another terminal and run: npm run chat"
        node chat.js
        ;;
    4)
        echo ""
        echo -e "${YELLOW}🦉 Running Swift integration test...${NC}"
        cd ../.. && swift test --filter IntegrationTest
        ;;
    5)
        echo ""
        echo -e "${YELLOW}🏃 Running all tests...${NC}"
        echo ""
        
        # Run basic test
        echo -e "${YELLOW}Test 1: Basic interop${NC}"
        if node test.js; then
            echo -e "${GREEN}✅ Basic test passed${NC}"
        else
            echo -e "${RED}❌ Basic test failed${NC}"
        fi
        echo ""
        
        # Run Swift test if available
        echo -e "${YELLOW}Test 2: Swift integration${NC}"
        cd ../.. 
        if swift test --filter IntegrationTest 2>/dev/null; then
            echo -e "${GREEN}✅ Swift test passed${NC}"
        else
            echo -e "${YELLOW}⚠️  Swift test not available or failed${NC}"
        fi
        cd Tests/Interop
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}🏁 Test complete!${NC}"