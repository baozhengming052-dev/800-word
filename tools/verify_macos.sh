#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p tmp/verification
export MACOSX_DEPLOYMENT_TARGET=13.0
swiftc Words800App/Models.swift Words800App/LearningEngine.swift tests/LearningEngineTests.swift -o tmp/verification/learning-tests
tmp/verification/learning-tests Words800App/Resources/library.json
