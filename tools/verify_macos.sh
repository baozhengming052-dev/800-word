#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p tmp/verification
export MACOSX_DEPLOYMENT_TARGET=13.0
core=(Words800App/Models.swift Words800App/PersonalLibrary.swift Words800App/SnapshotCodec.swift Words800App/LearningEngine.swift)
swiftc "${core[@]}" tests/PersonalLibraryTests.swift -o tmp/verification/personal-library-tests
tmp/verification/personal-library-tests Words800App/Resources/library.json
swiftc "${core[@]}" Words800App/SnapshotStore.swift tests/SnapshotStoreTests.swift -o tmp/verification/snapshot-store-tests
tmp/verification/snapshot-store-tests
swiftc "${core[@]}" tests/LearningEngineTests.swift -o tmp/verification/learning-tests
tmp/verification/learning-tests Words800App/Resources/library.json
swiftc "${core[@]}" Words800App/SyncMergeEngine.swift tests/SyncMergeEngineTests.swift -o tmp/verification/sync-merge-tests
tmp/verification/sync-merge-tests Words800App/Resources/library.json
swiftc "${core[@]}" Words800App/SyncMergeEngine.swift tests/RichNotesTests.swift -o tmp/verification/rich-notes-tests
tmp/verification/rich-notes-tests Words800App/Resources/library.json
swiftc "${core[@]}" Words800App/SyncMergeEngine.swift tests/PersonalSyncTests.swift -o tmp/verification/personal-sync-tests
tmp/verification/personal-sync-tests Words800App/Resources/library.json
swiftc "${core[@]}" Words800App/SyncMergeEngine.swift Words800App/PersonalTransactions.swift tests/PersonalTransactionTests.swift -o tmp/verification/personal-transaction-tests
tmp/verification/personal-transaction-tests
swiftc "${core[@]}" Words800App/SyncMergeEngine.swift Words800App/SyncExchange.swift tests/SyncExchangeTests.swift -o tmp/verification/sync-exchange-tests
tmp/verification/sync-exchange-tests
swiftc Words800App/AdaptiveLayout.swift tests/AdaptiveLayoutTests.swift -o tmp/verification/adaptive-layout-tests
tmp/verification/adaptive-layout-tests
swiftc Words800App/NearbySecurity.swift tests/NearbySecurityTests.swift -o tmp/verification/nearby-security-tests
tmp/verification/nearby-security-tests
