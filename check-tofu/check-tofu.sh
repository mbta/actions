#!/usr/bin/env bash

# Confirm that Tofu configuration is valid and properly formatted.
# If arguments are passed, they are assumed to be paths to modules to be
# checked. Otherwise all root and child modules are checked. In the latter
# case it is assumed that this script is being run from the root of the repo.
# Validation checks can be skipped by setting CHECK_SYNTAX=false.
# This script handles environment setup (Scalr credentials, Cache dirs)
# before running validation checks.

# Global Defaults
CHECK_SYNTAX="${CHECK_SYNTAX:-true}"
TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-/tmp/.terraform-cache}"
SCALR_HOSTNAME="${SCALR_HOSTNAME:-mbta.scalr.io}"

function setup_environment() {
    echo "Configuring Environment..."

    # Setup Scalr Credentials
    if [[ -n "$SCALR_TOKEN" ]]; then
        echo "Configuring Scalr credentials for $SCALR_HOSTNAME..."
        cat <<EOF > "$HOME/.terraformrc"
credentials "$SCALR_HOSTNAME" {
  token = "$SCALR_TOKEN"
}
EOF
    else
        echo "WARNING: SCALR_TOKEN not set. Remote module downloads may fail."
    fi

    # Setup Cache Directory
    if [[ ! -d "$TF_PLUGIN_CACHE_DIR" ]]; then
        echo "Creating Tofu plugin cache directory at $TF_PLUGIN_CACHE_DIR"
        mkdir -p "$TF_PLUGIN_CACHE_DIR"
    fi
    export TF_PLUGIN_CACHE_DIR="$TF_PLUGIN_CACHE_DIR"
}

function check_binary() {
    echo -n "Checking for tofu binary... "
    if ! command -v tofu &> /dev/null; then
        echo "No tofu binary found."
        # Attempt to use ASDF if present (replaces explicit ASDF steps if run locally/CI)
        if [ -f ".tool-versions" ] && command -v asdf &> /dev/null; then
            echo "Attempting to install via asdf..."
            asdf install tofu
            asdf reshim
        else
            >&2 echo "Error: Tofu not found and cannot be installed automatically."
            exit 1
        fi
    else
        echo "Found $(tofu --version)"
    fi
}

function check_syntax() {
    echo "Checking syntax..."
    # initialize the module, run `tofu validate`
    # We use -backend=false to avoid remote state locking during checks
    tofu init -backend=false > /dev/null
    if ! tofu validate; then
        >&2 echo "tofu configuration is not valid."
        exit 1
    fi
}

function check_format() {
    echo "Checking formatting..."
    if ! tofu fmt -check; then
        >&2 echo "Tofu format is unclean. Run 'tofu fmt' and push the changes."
        exit 1
    fi
    echo "Configuration format is correct."
}

function get_terraform_root_modules() {
    if [ ! -d "terraform" ]; then
        >&2 echo "Error: This script must be run from the root of the repo."
        exit 1
    fi
    for dir in terraform/*/; do
        if [ "$dir" != "terraform/modules/" ]; then
            echo "$dir"
        fi
    done
}

function run_module_checks() {
    local dir="$1"
    local start_time
    start_time=$(date +%s)

    echo ""
    echo "=========================================================="
    echo "=== Checking ${dir} ==="
    echo "=========================================================="

    pushd "${dir}" >/dev/null || return

    if [ "${CHECK_SYNTAX}" == true ]; then
        echo "Running syntax check for ${dir}"
        check_syntax
        echo "Finished syntax check for ${dir}"
    fi

    echo "Running format check for ${dir}"
    check_format
    echo "Finished format check for ${dir}"

    local end_time
    end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    echo "Module check on ${dir} took: $total_time seconds"

    popd >/dev/null || return
}

# --- Main Execution ---

setup_environment
check_binary

# Check if arguments provided (directories), otherwise check all/changed
if [ "$#" -gt 0 ]; then
    for tf_dir in "$@"; do
        run_module_checks "${tf_dir}"
    done
else
    start_time=$(date +%s)

    # If CHANGED_DIRS env var is set (from CI), use it, otherwise scan all
    if [[ -n "$CHANGED_DIRS" ]]; then
        echo "Detected changed directories from environment: $CHANGED_DIRS"
        for tf_dir in $CHANGED_DIRS; do
            run_module_checks "${tf_dir}"
        done
    else
        echo "No specific directories provided, scanning all root modules..."
        while IFS='' read -r tf_dir; do
            run_module_checks "${tf_dir}";
        done < <(get_terraform_root_modules)
    fi

    end_time=$(date +%s)
    total_time=$((end_time - start_time))
    echo "Total validation time: $total_time seconds"
fi
