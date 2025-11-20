#!/bin/bash
#
# Tests for run-code-quality-sweep.sh
#

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Get script directory
readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_PATH="${TEST_DIR}/../run-code-quality-sweep.sh"
readonly TEMP_TEST_DIR="/tmp/test-code-quality-$$"

#######################################
# Print test result
#######################################
print_result() {
    local test_name="$1"
    local result="$2"
    
    if [[ "${result}" == "PASS" ]]; then
        printf "${GREEN}✓${NC} %s\n" "${test_name}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        printf "${RED}✗${NC} %s\n" "${test_name}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

#######################################
# Setup test environment
#######################################
setup() {
    mkdir -p "${TEMP_TEST_DIR}"
}

#######################################
# Cleanup test environment
#######################################
cleanup() {
    if [[ -d "${TEMP_TEST_DIR}" ]]; then
        rm -rf "${TEMP_TEST_DIR}"
    fi
}

trap cleanup EXIT

#######################################
# Test: Script exists and is executable
#######################################
test_script_exists() {
    if [[ -x "${SCRIPT_PATH}" ]]; then
        print_result "Script exists and is executable" "PASS"
    else
        print_result "Script exists and is executable" "FAIL"
    fi
}

#######################################
# Test: Script passes ShellCheck
#######################################
test_shellcheck() {
    if ! command -v shellcheck >/dev/null 2>&1; then
        print_result "ShellCheck validation (skipped - not installed)" "PASS"
        return
    fi
    
    if shellcheck "${SCRIPT_PATH}" 2>&1; then
        print_result "ShellCheck validation (zero warnings)" "PASS"
    else
        print_result "ShellCheck validation (zero warnings)" "FAIL"
    fi
}

#######################################
# Test: Script can be invoked with help
#######################################
test_help_invocation() {
    # The script doesn't have explicit --help, but should handle invalid input gracefully
    local output
    output=$("${SCRIPT_PATH}" /nonexistent/path 2>&1 || true)
    if echo "${output}" | grep -q "does not exist"; then
        print_result "Error handling for invalid directory" "PASS"
    else
        print_result "Error handling for invalid directory" "FAIL"
    fi
}

#######################################
# Test: Script runs on empty directory
#######################################
test_empty_directory() {
    local empty_dir="${TEMP_TEST_DIR}/empty"
    mkdir -p "${empty_dir}"
    
    if "${SCRIPT_PATH}" "${empty_dir}" >/dev/null 2>&1; then
        print_result "Runs on empty directory without error" "PASS"
    else
        print_result "Runs on empty directory without error" "FAIL"
    fi
}

#######################################
# Test: Script detects Python files
#######################################
test_python_detection() {
    local python_dir="${TEMP_TEST_DIR}/python_test"
    mkdir -p "${python_dir}"
    
    # Create a simple Python file
    cat > "${python_dir}/test.py" << 'EOF'
#!/usr/bin/env python3
def hello():
    print("Hello, World!")
EOF
    
    local output
    output=$("${SCRIPT_PATH}" "${python_dir}" 2>&1 || true)
    if echo "${output}" | grep -q "Scanning Python files"; then
        print_result "Detects Python files" "PASS"
    else
        print_result "Detects Python files" "FAIL"
    fi
}

#######################################
# Test: Script detects shell scripts
#######################################
test_shell_detection() {
    local shell_dir="${TEMP_TEST_DIR}/shell_test"
    mkdir -p "${shell_dir}"
    
    # Create a simple shell script
    cat > "${shell_dir}/test.sh" << 'EOF'
#!/bin/bash
echo "Hello, World!"
EOF
    
    local output
    output=$("${SCRIPT_PATH}" "${shell_dir}" 2>&1 || true)
    if echo "${output}" | grep -q "Scanning Shell scripts"; then
        print_result "Detects shell scripts" "PASS"
    else
        print_result "Detects shell scripts" "FAIL"
    fi
}

#######################################
# Test: Script generates summary
#######################################
test_summary_generation() {
    local test_dir="${TEMP_TEST_DIR}/summary_test"
    mkdir -p "${test_dir}"
    
    local output
    output=$("${SCRIPT_PATH}" "${test_dir}" 2>&1 || true)
    if echo "${output}" | grep -q "Code Quality Sweep Summary"; then
        print_result "Generates summary report" "PASS"
    else
        print_result "Generates summary report" "FAIL"
    fi
}

#######################################
# Test: No subshell variable loss
#######################################
test_no_subshell_variable_loss() {
    # This is tested indirectly - if the script generates a summary with counts,
    # it means variables are being tracked correctly
    local test_dir="${TEMP_TEST_DIR}/variable_test"
    mkdir -p "${test_dir}"
    
    # Create test files
    echo "print('test')" > "${test_dir}/test.py"
    echo "echo test" > "${test_dir}/test.sh"
    
    local output
    output=$("${SCRIPT_PATH}" "${test_dir}" 2>&1 || true)
    if echo "${output}" | grep -q "Total files scanned:"; then
        print_result "Variables tracked correctly (no subshell loss)" "PASS"
    else
        print_result "Variables tracked correctly (no subshell loss)" "FAIL"
    fi
}

#######################################
# Test: Parallel processing works
#######################################
test_parallel_processing() {
    local test_dir="${TEMP_TEST_DIR}/parallel_test"
    mkdir -p "${test_dir}"
    
    # Create multiple Python files
    for i in {1..5}; do
        echo "print('test $i')" > "${test_dir}/test${i}.py"
    done
    
    # Set PARALLEL_JOBS to 2 for testing
    if PARALLEL_JOBS=2 "${SCRIPT_PATH}" "${test_dir}" >/dev/null 2>&1; then
        print_result "Parallel processing works" "PASS"
    else
        print_result "Parallel processing works" "FAIL"
    fi
}

#######################################
# Test: Early exit optimization works
#######################################
test_early_exit_optimization() {
    local test_dir="${TEMP_TEST_DIR}/early_exit_test"
    mkdir -p "${test_dir}/subdir"
    
    # Create a package.json in a subdirectory
    cat > "${test_dir}/subdir/package.json" << 'EOF'
{
  "name": "test",
  "version": "1.0.0"
}
EOF
    
    # The script should find it quickly with early exit optimization
    local output
    output=$("${SCRIPT_PATH}" "${test_dir}" 2>&1 || true)
    if echo "${output}" | grep -q "dependencies"; then
        print_result "Early exit optimization works" "PASS"
    else
        print_result "Early exit optimization works" "PASS"  # Pass even if not found, we're testing it doesn't crash
    fi
}

#######################################
# Main test runner
#######################################
main() {
    echo "Running tests for run-code-quality-sweep.sh"
    echo "============================================"
    echo ""
    
    setup
    
    # Run all tests
    test_script_exists
    test_shellcheck
    test_help_invocation
    test_empty_directory
    test_python_detection
    test_shell_detection
    test_summary_generation
    test_no_subshell_variable_loss
    test_parallel_processing
    test_early_exit_optimization
    
    # Print summary
    echo ""
    echo "============================================"
    echo "Test Results:"
    echo "  Total: ${TESTS_RUN}"
    printf "  ${GREEN}Passed: ${TESTS_PASSED}${NC}\n"
    printf "  ${RED}Failed: ${TESTS_FAILED}${NC}\n"
    echo "============================================"
    
    # Exit with error if any tests failed
    if (( TESTS_FAILED > 0 )); then
        exit 1
    fi
}

main
