#!/bin/sh
# Builds the JSON Schema sample programs with Free Pascal into build/samples.
set -e
cd "$(dirname "$0")"
mkdir -p build/samples
for src in schema/samples/Sample*.pas; do
  fpc -Mdelphi -Fu. -Fuschema -FUbuild/samples -FEbuild/samples "$src"
done
echo "Run from schema/samples, e.g.:  cd schema/samples && ../../build/samples/SampleSchemaBasics"
