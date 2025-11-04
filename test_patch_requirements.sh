#!/bin/bash

# Test suite for patch_requirements.sh
# This script tests the core functionality without requiring GitHub access

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Function to print colored text
print_color() {
    local color=$1
    shift
    echo -e "${color}$@${NC}"
}

# Test result functions
test_pass() {
    ((TESTS_PASSED++))
    print_color "$GREEN" "  ✓ PASS: $1"
}

test_fail() {
    ((TESTS_FAILED++))
    print_color "$RED" "  ✗ FAIL: $1"
}

print_test_header() {
    echo
    print_color "$CYAN$BOLD" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_color "$CYAN$BOLD" "TEST: $1"
    print_color "$CYAN$BOLD" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Version comparison function (copied from main script)
version_lt() {
    # Remove any characters after the version number
    local v1=$(echo "$1" | sed 's/[^0-9.].*$//')
    local v2=$(echo "$2" | sed 's/[^0-9.].*$//')
    
    # Compare versions
    if [ "$(printf '%s\n' "$v1" "$v2" | sort -V | head -n1)" = "$v1" ] && [ "$v1" != "$v2" ]; then
        return 0  # v1 < v2
    else
        return 1  # v1 >= v2
    fi
}

# Test 1: Version Comparison Tests
test_version_comparisons() {
    print_test_header "Version Comparison Tests"
    ((TESTS_RUN++))
    
    # Test: 1.0.0 < 2.0.0
    if version_lt "1.0.0" "2.0.0"; then
        test_pass "1.0.0 < 2.0.0"
    else
        test_fail "1.0.0 < 2.0.0"
    fi
    
    # Test: 2.0.0 NOT < 1.0.0
    if ! version_lt "2.0.0" "1.0.0"; then
        test_pass "2.0.0 NOT < 1.0.0"
    else
        test_fail "2.0.0 NOT < 1.0.0"
    fi
    
    # Test: 1.9.0 < 1.10.0 (important for semantic versioning)
    if version_lt "1.9.0" "1.10.0"; then
        test_pass "1.9.0 < 1.10.0 (semantic versioning)"
    else
        test_fail "1.9.0 < 1.10.0 (semantic versioning)"
    fi
    
    # Test: 1.0.0 NOT < 1.0.0 (equal versions)
    if ! version_lt "1.0.0" "1.0.0"; then
        test_pass "1.0.0 NOT < 1.0.0 (equal versions)"
    else
        test_fail "1.0.0 NOT < 1.0.0 (equal versions)"
    fi
    
    # Test: 0.120.4 < 0.121.0
    if version_lt "0.120.4" "0.121.0"; then
        test_pass "0.120.4 < 0.121.0"
    else
        test_fail "0.120.4 < 0.121.0"
    fi
    
    # Test: 1.0.0 < 1.0.1
    if version_lt "1.0.0" "1.0.1"; then
        test_pass "1.0.0 < 1.0.1 (patch version)"
    else
        test_fail "1.0.0 < 1.0.1 (patch version)"
    fi
    
    # Test: 1.0.1 NOT < 1.0.0
    if ! version_lt "1.0.1" "1.0.0"; then
        test_pass "1.0.1 NOT < 1.0.0 (no downgrade)"
    else
        test_fail "1.0.1 NOT < 1.0.0 (no downgrade)"
    fi
    
    # Test: 2.5.1 NOT < 2.5.0
    if ! version_lt "2.5.1" "2.5.0"; then
        test_pass "2.5.1 NOT < 2.5.0 (no downgrade)"
    else
        test_fail "2.5.1 NOT < 2.5.0 (no downgrade)"
    fi
}

# Test 2: Package File Parsing
test_package_file_parsing() {
    print_test_header "Package File Parsing Tests"
    ((TESTS_RUN++))
    
    # Create a temporary test packages file
    local test_file=$(mktemp)
    
    cat > "$test_file" << 'EOF'
# This is a comment
fastapi, 0.120.4
starlette, 0.49.1

# Another comment
   requests,  2.28.0   
# Empty lines above and below should be ignored

uvicorn,0.30.0
EOF
    
    # Parse the file
    local packages=()
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -z "$line" ] || [[ "$line" =~ ^# ]]; then
            continue
        fi
        
        # Parse package and version
        if [[ "$line" =~ ^([^,]+),(.+)$ ]]; then
            local pkg=$(echo "${BASH_REMATCH[1]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            local ver=$(echo "${BASH_REMATCH[2]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            if [ -n "$pkg" ] && [ -n "$ver" ]; then
                packages+=("$pkg:$ver")
            fi
        fi
    done < "$test_file"
    
    # Test: Should parse 4 packages
    if [ ${#packages[@]} -eq 4 ]; then
        test_pass "Parsed correct number of packages (4)"
    else
        test_fail "Parsed correct number of packages (expected 4, got ${#packages[@]})"
    fi
    
    # Test: First package should be fastapi:0.120.4
    if [ "${packages[0]}" = "fastapi:0.120.4" ]; then
        test_pass "First package parsed correctly (fastapi:0.120.4)"
    else
        test_fail "First package parsed correctly (got ${packages[0]})"
    fi
    
    # Test: Third package should handle whitespace (requests:2.28.0)
    if [ "${packages[2]}" = "requests:2.28.0" ]; then
        test_pass "Whitespace handling works (requests:2.28.0)"
    else
        test_fail "Whitespace handling works (got ${packages[2]})"
    fi
    
    # Test: Fourth package should handle no spaces (uvicorn:0.30.0)
    if [ "${packages[3]}" = "uvicorn:0.30.0" ]; then
        test_pass "No-space format works (uvicorn:0.30.0)"
    else
        test_fail "No-space format works (got ${packages[3]})"
    fi
    
    rm -f "$test_file"
}

# Test 3: Requirements.txt Pattern Matching
test_requirements_pattern_matching() {
    print_test_header "Requirements.txt Pattern Matching Tests"
    ((TESTS_RUN++))
    
    # Create a temporary requirements.txt file
    local req_file=$(mktemp)
    
    cat > "$req_file" << 'EOF'
fastapi==0.120.4
starlette==0.49.1
requests == 2.28.0
uvicorn==0.30.0
python-multipart==0.0.9
EOF
    
    # Test: Exact package match for 'fastapi'
    if grep -q "^fastapi[[:space:]]*[=]" "$req_file"; then
        test_pass "Exact match found for 'fastapi'"
    else
        test_fail "Exact match found for 'fastapi'"
    fi
    
    # Test: Should NOT match partial package name
    if ! grep -q "^fast[[:space:]]*[=]" "$req_file"; then
        test_pass "Partial match rejected for 'fast'"
    else
        test_fail "Partial match rejected for 'fast'"
    fi
    
    # Test: Extract version from fastapi line
    local current_line=$(grep -E "^fastapi[[:space:]]*[=]" "$req_file")
    local current_version=$(echo "$current_line" | sed -E "s/^fastapi[[:space:]]*==?//" | tr -d '[:space:]')
    if [ "$current_version" = "0.120.4" ]; then
        test_pass "Version extraction works (0.120.4)"
    else
        test_fail "Version extraction works (got '$current_version')"
    fi
    
    # Test: Extract version with spaces (requests)
    current_line=$(grep -E "^requests[[:space:]]*[=]" "$req_file")
    current_version=$(echo "$current_line" | sed -E "s/^requests[[:space:]]*==?//" | tr -d '[:space:]')
    if [ "$current_version" = "2.28.0" ]; then
        test_pass "Version extraction with spaces works (2.28.0)"
    else
        test_fail "Version extraction with spaces works (got '$current_version')"
    fi
    
    # Test: Package with hyphen (python-multipart)
    if grep -q "^python-multipart[[:space:]]*[=]" "$req_file"; then
        test_pass "Package name with hyphen matched (python-multipart)"
    else
        test_fail "Package name with hyphen matched (python-multipart)"
    fi
    
    rm -f "$req_file"
}

# Test 4: Version Update Logic
test_version_update_logic() {
    print_test_header "Version Update Logic Tests"
    ((TESTS_RUN++))
    
    # Scenario 1: Should upgrade (1.0.0 -> 2.0.0)
    local current="1.0.0"
    local target="2.0.0"
    if version_lt "$current" "$target"; then
        test_pass "Should upgrade: $current -> $target"
    else
        test_fail "Should upgrade: $current -> $target"
    fi
    
    # Scenario 2: Should skip (already at target)
    current="2.0.0"
    target="2.0.0"
    if [ "$current" = "$target" ]; then
        test_pass "Should skip: already at target ($current)"
    else
        test_fail "Should skip: already at target ($current)"
    fi
    
    # Scenario 3: Should prevent downgrade (3.0.0 -> 2.0.0)
    current="3.0.0"
    target="2.0.0"
    if ! version_lt "$current" "$target"; then
        test_pass "Should prevent downgrade: $current -> $target"
    else
        test_fail "Should prevent downgrade: $current -> $target"
    fi
    
    # Scenario 4: Should upgrade with minimum version check
    current="1.5.0"
    target="2.0.0"
    local min_version="1.2.0"
    if version_lt "$current" "$target" && ! version_lt "$current" "$min_version"; then
        test_pass "Should upgrade with min version check: $current -> $target (min: $min_version)"
    else
        test_fail "Should upgrade with min version check: $current -> $target (min: $min_version)"
    fi
    
    # Scenario 5: Should skip (below minimum version)
    current="1.0.0"
    target="2.0.0"
    min_version="1.5.0"
    if version_lt "$current" "$min_version"; then
        test_pass "Should skip: below minimum version ($current < $min_version)"
    else
        test_fail "Should skip: below minimum version ($current < $min_version)"
    fi
}

# Test 5: Sed Replace Command Tests
test_sed_replace() {
    print_test_header "Sed Replace Command Tests"
    ((TESTS_RUN++))
    
    # Create a temporary requirements.txt
    local req_file=$(mktemp)
    
    cat > "$req_file" << 'EOF'
fastapi==0.120.4
starlette==0.49.1
requests == 2.28.0
uvicorn==0.30.0
EOF
    
    # Test: Update fastapi version
    sed -i.bak -E "s/^(fastapi)[[:space:]]*==?[[:space:]]*[^[:space:]]+[[:space:]]*$/\1==0.121.0/" "$req_file"
    
    local new_line=$(grep -E "^fastapi[[:space:]]*[=]" "$req_file")
    if echo "$new_line" | grep -q "^fastapi==0.121.0$"; then
        test_pass "Sed replacement works for fastapi"
    else
        test_fail "Sed replacement works for fastapi (got: $new_line)"
    fi
    
    # Test: Update requests version (with spaces)
    sed -i.bak -E "s/^(requests)[[:space:]]*==?[[:space:]]*[^[:space:]]+[[:space:]]*$/\1==2.29.0/" "$req_file"
    
    new_line=$(grep -E "^requests[[:space:]]*[=]" "$req_file")
    if echo "$new_line" | grep -q "^requests==2.29.0$"; then
        test_pass "Sed replacement works for requests (with original spaces)"
    else
        test_fail "Sed replacement works for requests (got: $new_line)"
    fi
    
    rm -f "$req_file" "$req_file.bak"
}

# Test 6: Edge Cases
test_edge_cases() {
    print_test_header "Edge Case Tests"
    ((TESTS_RUN++))
    
    # Test: Very long version numbers
    if version_lt "1.2.3.4.5" "1.2.3.4.6"; then
        test_pass "Handles long version numbers"
    else
        test_fail "Handles long version numbers"
    fi
    
    # Test: Single digit versions
    if version_lt "1" "2"; then
        test_pass "Handles single digit versions"
    else
        test_fail "Handles single digit versions"
    fi
    
    # Test: Version with leading zeros
    if version_lt "0.0.1" "0.0.2"; then
        test_pass "Handles versions with leading zeros"
    else
        test_fail "Handles versions with leading zeros"
    fi
    
    # Test: Large version numbers
    if version_lt "999.999.999" "1000.0.0"; then
        test_pass "Handles large version numbers"
    else
        test_fail "Handles large version numbers"
    fi
}

# Test 7: Invalid Package File Handling
test_invalid_package_file() {
    print_test_header "Invalid Package File Handling Tests"
    ((TESTS_RUN++))
    
    # Create a test file with invalid entries
    local test_file=$(mktemp)
    
    cat > "$test_file" << 'EOF'
# Valid entries
fastapi, 0.120.4
# Invalid entries below
no-comma-here
,missing-package
package-only,
a,1.0.0
# 'a' is too short (< 2 chars) and should be rejected in actual script
EOF
    
    local packages=()
    local valid_count=0
    
    while IFS= read -r line || [ -n "$line" ]; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -z "$line" ] || [[ "$line" =~ ^# ]]; then
            continue
        fi
        
        if [[ "$line" =~ ^([^,]+),(.+)$ ]]; then
            local pkg=$(echo "${BASH_REMATCH[1]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            local ver=$(echo "${BASH_REMATCH[2]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            if [ -n "$pkg" ] && [ -n "$ver" ] && [ ${#pkg} -ge 2 ]; then
                packages+=("$pkg:$ver")
                ((valid_count++))
            fi
        fi
    done < "$test_file"
    
    # Should only parse 1 valid entry (fastapi)
    # 'a' is too short and is filtered out by length validation
    if [ $valid_count -eq 1 ]; then
        test_pass "Correctly parsed valid entries and filtered short names (1)"
    else
        test_fail "Correctly parsed valid entries and filtered short names (expected 1, got $valid_count)"
    fi
    
    rm -f "$test_file"
}

# Run all tests
print_color "$WHITE$BOLD" "╔════════════════════════════════════════════════════╗"
print_color "$WHITE$BOLD" "║   PATCH REQUIREMENTS SCRIPT - TEST SUITE          ║"
print_color "$WHITE$BOLD" "╚════════════════════════════════════════════════════╝"

test_version_comparisons
test_package_file_parsing
test_requirements_pattern_matching
test_version_update_logic
test_sed_replace
test_edge_cases
test_invalid_package_file

# Print summary
echo
print_color "$WHITE$BOLD" "╔════════════════════════════════════════════════════╗"
print_color "$WHITE$BOLD" "║   TEST SUMMARY                                     ║"
print_color "$WHITE$BOLD" "╚════════════════════════════════════════════════════╝"
echo
print_color "$BLUE" "Total Test Suites Run: $TESTS_RUN"
print_color "$GREEN" "Test Cases Passed: $TESTS_PASSED"
print_color "$RED" "Test Cases Failed: $TESTS_FAILED"
echo

if [ $TESTS_FAILED -eq 0 ]; then
    print_color "$GREEN$BOLD" "✓ ALL TESTS PASSED!"
    exit 0
else
    print_color "$RED$BOLD" "✗ SOME TESTS FAILED!"
    exit 1
fi
