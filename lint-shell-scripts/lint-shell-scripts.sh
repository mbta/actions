#!/usr/bin/env bash

# lint shell scripts in bin/ and .github/scripts/

set -e

# lint bash scripts
bash_scripts="$(grep -rIl '^#!.*bash' ./bin)" \
    || echo "No shell scripts found in ./bin."
for script in ${bash_scripts}; do
    echo "Linting ${script}..."
    shellcheck "${script}"
done

# lint action scripts
action_scripts="$(grep -rIl '^#!.*bash' .github/scripts)" \
    || echo "No shell scripts found in .github/scripts."
for script in ${action_scripts}; do
    echo "Linting ${script}..."
    shellcheck "${script}"
done
