#!/usr/bin/env bash

# Confirm that Tofu configuration is valid and properly formatted.
# If arguments are passed, they are assumed to be paths to modules to be
# checked. Otherwise all root and child modules are checked. In the latter
# case it is assumed that this script is being run from the root of the repo.
# Validation checks can be skipped by setting CHECK_SYNTAX=false.

# global var to enable/disable syntax checks with `tofu validate`
CHECK_SYNTAX="${CHECK_SYNTAX:-true}"

# tofu must be installed
echo -n "Checking for tofu binary... "
if ! which tofu; then
    >&2 echo "No tofu binary could be found"
    exit 1
fi

function check_syntax() {
    # initialize the module, run `tofu validate`, and exit nonzero if errors are discovered
    echo "Checking syntax..."
    tofu init -backend=false
    if ! tofu validate; then
        >&2 echo "tofu configuration is not valid."
        exit 1
    fi
}

function check_format() {
    # run `tofu fmt` and exit nonzero if errors are discovered
    echo "Checking formatting..."
    if ! tofu fmt -check; then
        >&2 echo "Tofu format is unclean. Run 'tofu fmt' and push the changes."
        exit 1
    fi
    echo "Configuration format is correct."
}

function get_terraform_root_modules() {
    # generate a list of all root modules in this repo
    # this function assumes the script is being run at the root of the repo
    if [ ! -d "terraform" ]; then
        >&2 echo "Error: This script must be run from the root of the repo when run with no arguments."
        exit 1
    fi
    # list all root modules (omitting 'modules' directory)
    for dir in terraform/*/; do
        if [ "$dir" != "terraform/modules/" ]; then
            echo "$dir"
        fi
    done
}

function run_module_checks() {
    # given a directory, descend into that directory and run format and (optionally) syntax checks
    start_time=$(date +%s)
    echo ""
    echo "=========================================================="
    echo "=== Checking ${1} ==="
    echo "=========================================================="
    pushd "${1}" >/dev/null || return
    if [ "${CHECK_SYNTAX}" == true ]; then
        echo "Running syntax check for ${1}"
        check_syntax
        echo "Finished syntax check for ${1}"
    fi
    echo "Running format check for ${1}"
    check_format
    echo "Finished format check for ${1}"

    echo ""
    end_time=$(date +%s)
    total_time=$((end_time - start_time))
    echo "Module check on ${1} took: $total_time seconds"

    popd >/dev/null || return
}

# get paths from arguments if passed, otherwise check all root and child modules
if [ "$#" -gt 0 ]; then
    for tf_dir in "$@"; do
        run_module_checks "${tf_dir}"
    done
else
    start_time=$(date +%s)
    echo "Begin run_module_checks"

    while IFS='' read -r tf_dir; do
        run_module_checks "${tf_dir}";
    done < <(get_terraform_root_modules)

    end_time=$(date +%s)
    total_time=$((end_time - start_time))
    echo "Module validation took: $total_time seconds"
fi
