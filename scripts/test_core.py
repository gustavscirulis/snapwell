#!/usr/bin/env python3
"""Run production model/HTTP/filesystem tests without an app host or testmanagerd."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / '.context' / 'core-tests'
SOURCES = [
    'macos/Snapwell/Models/MediaItem.swift',
    'macos/Snapwell/Models/Space.swift',
    'macos/Snapwell/Models/SpaceMembership.swift',
    'macos/Snapwell/Models/AnalysisResult.swift',
    'macos/Snapwell/Services/AIAnalysisService.swift',
    'macos/Snapwell/Services/ModelDiscoveryService.swift',
    'macos/Snapwell/Services/OllamaClient.swift',
    'macos/Snapwell/Services/KeychainService.swift',
    'ios/Snapwell/Services/ShareImportService.swift',
    'ios/Snapwell/Services/LocalToiCloudMigrationService.swift',
    'macos/Snapwell/Services/MetadataSidecarService.swift',
    'macos/Snapwell/Services/MediaStorageService.swift',
    'Shared/Sync/ICloudFile.swift',
    'Shared/Sync/DownloadRequester.swift',
    'Shared/AutomationEnvironment.swift',
    'Shared/AutomationFixtures.swift',
    'Shared/AnalysisRecovery.swift',
    'Shared/ShareStagingStore.swift',
]
TESTS = [
    'macos/SnapwellTests/Helpers/TestTags.swift',
    'Tests/Compatibility/CloudProviderHTTPTests.swift',
    'Tests/Compatibility/PersistenceIntegrationTests.swift',
    'Tests/Compatibility/ShareStagingTests.swift',
    'ios/SnapwellTests/ShareHandoffIntegrationTests.swift',
    'ios/SnapwellTests/LocalMigrationIntegrationTests.swift',
]


def prepare():
    for directory, files in [('Sources/Snapwell', SOURCES), ('Tests/CoreTests', TESTS)]:
        destination = PACKAGE / directory
        destination.mkdir(parents=True, exist_ok=True)
        # Only maintain this runner's generated source links, never source files.
        for existing in destination.glob('*.swift'):
            if existing.is_symlink():
                existing.unlink()
        for name in files:
            (destination / Path(name).name).symlink_to(ROOT / name)
    (PACKAGE / 'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SnapwellCoreTests", platforms: [.macOS(.v15)], targets: [
    .target(name: "Snapwell", swiftSettings: [.define("SNAPWELL_AUTOMATION")]),
    .testTarget(name: "CoreTests", dependencies: ["Snapwell"])
])
''')


if __name__ == '__main__':
    prepare()
    sys.exit(subprocess.call(['swift', 'test', '--disable-sandbox', '--package-path', str(PACKAGE),
                             '-Xswiftc', '-disable-sandbox', *sys.argv[1:]], cwd=ROOT))
