#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
[[ -d 'build/Mac Duo.app' ]] || ./scripts/build.sh
open 'build/Mac Duo.app'
