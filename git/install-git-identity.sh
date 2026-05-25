#!/usr/bin/env bash
# Set global git author identity (all repos on this machine).
# Run: bash git/install-git-identity.sh

set -euo pipefail

git config --global user.name 'j4ck3'
git config --global user.email 'jacobhallgren@live.se'

echo 'Global git identity:'
git config --global --get user.name
git config --global --get user.email
