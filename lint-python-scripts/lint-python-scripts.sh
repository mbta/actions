#!/usr/bin/env bash

# lint python scripts in bin/

set -e

# lint python scripts
python_scripts="$(grep -rIl '^#!.*python' ./bin)" \
    || echo "No python scripts found in ./bin."
for script in ${python_scripts}; do
    echo "Linting ${script}..."
    flake8 "${script}"
done
