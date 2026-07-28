#!/usr/bin/env bash
# Reshape a syncit-packed bundle directory (task-slug subdirs, e.g.
# install-kubernetes-cri-o-packages-via-dnf/*.rpm, pull-*-images/*.tar) into
# the flat layout tasks/offline_package_prep.yml expects:
#   <bundle>/rpms/*.rpm
#   <bundle>/images/*.tar
#
# Usage: ./normalize_offline_bundle.sh <bundle_dir>
set -euo pipefail

bundle_dir="${1:?Usage: $0 <bundle_dir>}"
[[ -d "$bundle_dir" ]] || { echo "[ERROR] Not a directory: $bundle_dir" >&2; exit 1; }

mkdir -p "$bundle_dir/rpms" "$bundle_dir/images"

find "$bundle_dir" -type f -name '*.rpm' -not -path "$bundle_dir/rpms/*" -exec mv -n {} "$bundle_dir/rpms/" \;
find "$bundle_dir" -type f -name '*.tar' -not -path "$bundle_dir/images/*" -exec mv -n {} "$bundle_dir/images/" \;

# Drop the now-empty syncit task-slug dirs (repodata, manifest.json, etc. -
# nothing in them is needed once the files above have been moved out).
find "$bundle_dir" -mindepth 1 -maxdepth 1 -type d -not -name rpms -not -name images -exec rm -rf {} +

echo "rpms:   $(find "$bundle_dir/rpms" -name '*.rpm' | wc -l) file(s)"
echo "images: $(find "$bundle_dir/images" -name '*.tar' | wc -l) file(s)"
