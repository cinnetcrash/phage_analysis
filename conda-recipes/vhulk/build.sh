#!/bin/bash
set -euo pipefail

# Install vHULK.py into $PREFIX/bin so it's on PATH
install -m 755 vHULK.py "$PREFIX/bin/vHULK.py"

# Placeholder database directory — actual DB downloaded by user at runtime
mkdir -p "$PREFIX/opt/vhulk/database"

echo "vHULK installed. Download the database with:"
echo "  cd \$CONDA_PREFIX/opt/vhulk && tar -xzf database_Aug_2022.tar.gz"
echo "  # or follow: https://github.com/LaboratorioBioinformatica/vHULK#installation"
