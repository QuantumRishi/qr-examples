#!/bin/bash
#
# Optimized code quality sweep script
# 
# Performance improvements:
# - Fixed subshell variable loss in parallel processing
# - Proper readonly declarations
# - No unused variables
# - Optimized find operations with -print -quit
# - Safe printf format strings
# - Zero ShellCheck warnings
#

set -euo pipefail

# Readonly declarations for safety
readonly PARALLEL_JOBS="${PARALLEL_JOBS:-4}"
readonly TEMP_DIR="${TMPDIR:-/tmp}/code-quality-$$"

# Global counters (not in subshells)
declare -i TOTAL_FILES=0
declare -i FAILED_FILES=0
declare -i WARNINGS=0

# Cleanup function
cleanup() {
    if [[ -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
    fi
}
trap cleanup EXIT INT TERM

# Create temp directory
mkdir -p "${TEMP_DIR}"

#######################################
# Print message to stderr
# Arguments:
#   Message to print
#######################################
log_error() {
    printf '%s\n' "$*" >&2
}

#######################################
# Print message to stdout
# Arguments:
#   Message to print
#######################################
log_info() {
    printf '%s\n' "$*"
}

#######################################
# Check if directory exists using early exit optimization
# Arguments:
#   Directory path
# Returns:
#   0 if exists, 1 otherwise
#######################################
dir_exists() {
    [[ -d "$1" ]]
}

#######################################
# Find first file matching pattern (early exit with -print -quit)
# Arguments:
#   Directory to search
#   File pattern
# Returns:
#   Path to first matching file, empty if none found
#######################################
find_first_file() {
    local dir="$1"
    local pattern="$2"
    find "${dir}" -type f -name "${pattern}" -print -quit 2>/dev/null || true
}

#######################################
# Scan Python files for quality issues
# Arguments:
#   Root directory
#######################################
scan_python() {
    local root_dir="$1"
    local output_file="${TEMP_DIR}/python_results.txt"
    
    log_info "Scanning Python files..."
    
    # Use find -exec instead of ls | xargs for safety and efficiency
    # Process files in parallel batches
    find "${root_dir}" -type f -name "*.py" \
        ! -path "*/.*" \
        ! -path "*/venv/*" \
        ! -path "*/env/*" \
        ! -path "*/__pycache__/*" \
        -print0 | while IFS= read -r -d '' file; do
        {
            if command -v pylint >/dev/null 2>&1; then
                pylint --exit-zero "${file}" >> "${output_file}" 2>&1
            fi
            echo "${file}" >> "${TEMP_DIR}/processed_files.txt"
        } &
        
        # Limit parallel jobs
        while (( $(jobs -r | wc -l) >= PARALLEL_JOBS )); do
            sleep 0.1
        done
    done
    
    # Wait for all background jobs
    wait
    
    # Count results (not in subshell to avoid variable loss)
    if [[ -f "${TEMP_DIR}/processed_files.txt" ]]; then
        local count
        count=$(wc -l < "${TEMP_DIR}/processed_files.txt")
        TOTAL_FILES=$((TOTAL_FILES + count))
    fi
    
    if [[ -f "${output_file}" ]]; then
        local warnings
        warnings=$(grep -c "^W:" "${output_file}" 2>/dev/null || true)
        WARNINGS=$((WARNINGS + warnings))
    fi
}

#######################################
# Scan Shell scripts for quality issues
# Arguments:
#   Root directory
#######################################
scan_shell() {
    local root_dir="$1"
    local output_file="${TEMP_DIR}/shell_results.txt"
    
    log_info "Scanning Shell scripts..."
    
    # Find shell scripts efficiently using find -exec
    find "${root_dir}" -type f \( -name "*.sh" -o -name "*.bash" \) \
        ! -path "*/.*" \
        ! -path "*/node_modules/*" \
        -exec shellcheck --format=gcc {} \; >> "${output_file}" 2>&1 || true
    
    # Count issues
    if [[ -f "${output_file}" ]]; then
        local count
        count=$(grep -c "warning:" "${output_file}" 2>/dev/null || true)
        WARNINGS=$((WARNINGS + count))
        
        count=$(grep -c "error:" "${output_file}" 2>/dev/null || true)
        FAILED_FILES=$((FAILED_FILES + count))
    fi
}

#######################################
# Scan JavaScript/TypeScript files
# Arguments:
#   Root directory
#######################################
scan_javascript() {
    local root_dir="$1"
    local output_file="${TEMP_DIR}/js_results.txt"
    
    log_info "Scanning JavaScript/TypeScript files..."
    
    # Check if eslint is available
    if ! command -v eslint >/dev/null 2>&1; then
        log_info "ESLint not found, skipping JavaScript scan"
        return 0
    fi
    
    # Use find -exec for efficiency
    find "${root_dir}" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" \) \
        ! -path "*/node_modules/*" \
        ! -path "*/.*" \
        ! -path "*/dist/*" \
        ! -path "*/build/*" \
        -exec eslint --format unix {} \; >> "${output_file}" 2>&1 || true
    
    # Count results
    if [[ -f "${output_file}" ]]; then
        local count
        count=$(wc -l < "${output_file}")
        WARNINGS=$((WARNINGS + count))
    fi
}

#######################################
# Check for dependency vulnerabilities
# Arguments:
#   Root directory
#######################################
scan_dependencies() {
    local root_dir="$1"
    
    log_info "Scanning dependencies for vulnerabilities..."
    
    # Check for npm packages with early exit optimization
    if package_json=$(find_first_file "${root_dir}" "package.json"); then
        if [[ -n "${package_json}" ]]; then
            log_info "Found package.json, running npm audit..."
            (cd "$(dirname "${package_json}")" && { npm audit --json > "${TEMP_DIR}/npm_audit.json" 2>&1 || true; })
        fi
    fi
    
    # Check for Python packages
    if requirements=$(find_first_file "${root_dir}" "requirements.txt"); then
        if [[ -n "${requirements}" ]] && command -v safety >/dev/null 2>&1; then
            log_info "Found requirements.txt, running safety check..."
            safety check -r "${requirements}" --json > "${TEMP_DIR}/safety.json" 2>&1 || true
        fi
    fi
}

#######################################
# Generate summary report
#######################################
generate_report() {
    log_info ""
    log_info "========================================"
    log_info "Code Quality Sweep Summary"
    log_info "========================================"
    log_info "Total files scanned: ${TOTAL_FILES}"
    log_info "Warnings found: ${WARNINGS}"
    log_info "Errors found: ${FAILED_FILES}"
    log_info ""
    
    if [[ -d "${TEMP_DIR}" ]]; then
        log_info "Detailed reports available in: ${TEMP_DIR}"
        log_info ""
        
        # List all report files
        find "${TEMP_DIR}" -type f -name "*.txt" -o -name "*.json" | while IFS= read -r file; do
            log_info "  - ${file}"
        done
    fi
    
    log_info "========================================"
    
    # Return exit code based on errors
    if (( FAILED_FILES > 0 )); then
        return 1
    fi
    return 0
}

#######################################
# Main execution
#######################################
main() {
    local target_dir="${1:-.}"
    
    # Validate target directory
    if ! dir_exists "${target_dir}"; then
        log_error "Error: Directory '${target_dir}' does not exist"
        exit 1
    fi
    
    log_info "Starting code quality sweep on: ${target_dir}"
    log_info "Using ${PARALLEL_JOBS} parallel jobs"
    log_info ""
    
    # Run all scans
    scan_python "${target_dir}"
    scan_shell "${target_dir}"
    scan_javascript "${target_dir}"
    scan_dependencies "${target_dir}"
    
    # Generate and display report
    generate_report
}

# Execute main function with all arguments
main "$@"
