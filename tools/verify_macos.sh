#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p tmp/verification
export MACOSX_DEPLOYMENT_TARGET=13.0
swiftc Words800App/Models.swift Words800App/LearningEngine.swift tests/LearningEngineTests.swift -o tmp/verification/learning-tests
tmp/verification/learning-tests Words800App/Resources/library.json
swiftc Words800App/Models.swift Words800App/LearningEngine.swift Words800App/SyncMergeEngine.swift tests/SyncMergeEngineTests.swift -o tmp/verification/sync-merge-tests
tmp/verification/sync-merge-tests Words800App/Resources/library.json
swiftc Words800App/Models.swift Words800App/LearningEngine.swift Words800App/SyncMergeEngine.swift Words800App/SyncExchange.swift tests/SyncExchangeTests.swift -o tmp/verification/sync-exchange-tests
tmp/verification/sync-exchange-tests
swiftc Words800App/AdaptiveLayout.swift tests/AdaptiveLayoutTests.swift -o tmp/verification/adaptive-layout-tests
tmp/verification/adaptive-layout-tests
swiftc Words800App/NearbySecurity.swift tests/NearbySecurityTests.swift -o tmp/verification/nearby-security-tests
tmp/verification/nearby-security-tests
