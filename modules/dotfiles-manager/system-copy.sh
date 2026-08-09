#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 4 ]; then
    echo "Usage: $0 MODULE MAPPING IMMUTABLE_SOURCE DESTINATION" >&2
    exit 2
fi

module_name=$1
mapping_name=$2
source_path=$3
destination=$4

if [ ! -f "$source_path" ]; then
    echo "Error: immutable source missing for ${module_name}.${mapping_name}: $source_path" >&2
    exit 1
fi

mkdir -p -- "$(dirname "$destination")"
cp --remove-destination -- "$source_path" "$destination"
echo "Copied privileged ${module_name}.${mapping_name}: $source_path -> $destination"
