#!/bin/bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
output="${MCEXP_OUTPUT_DIR:-$repo/DerivedData/MCExpDistribution}"
identity="${MCEXP_CODE_SIGN_IDENTITY:--}"
python3 scripts/assets/compile_illustrations.py --check
xcodebuild -project alt-tab-macos.xcodeproj -scheme Release -configuration Release \
  -derivedDataPath DerivedDataRelease CODE_SIGN_IDENTITY="$identity" \
  'OTHER_CODE_SIGN_FLAGS=--timestamp=none --deep' CURRENT_PROJECT_VERSION=11.10.1 \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=MCEXP_PINNED_BUILD ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
python3 - "$repo" "$output" "$identity" <<'PY'
from pathlib import Path
import hashlib
import json
import os
import plistlib
import subprocess
import sys
import tempfile

repo, output = map(Path, sys.argv[1:3])
identity = sys.argv[3]
output.mkdir(parents=True, exist_ok=True)
stage = Path(tempfile.mkdtemp(prefix='package-', dir=output)) / 'AltTab MCExp 11.10.1'
stage.mkdir()
app = stage / 'AltTab.app'
source = repo / 'DerivedDataRelease/Build/Products/Release/AltTab.app'
subprocess.run(['ditto', str(source), str(app)], check=True)
binary = app / 'Contents/MacOS/AltTab'
lines = subprocess.check_output(['otool', '-l', str(binary)], text=True).splitlines()
for index, line in enumerate(lines):
    if 'cmd LC_RPATH' not in line:
        continue
    for entry in lines[index + 1:index + 5]:
        if 'path ' not in entry:
            continue
        path = entry.strip().split('path ', 1)[1].rsplit(' (offset', 1)[0]
        if str(repo / 'DerivedDataRelease') in path:
            subprocess.run(['install_name_tool', '-delete_rpath', path, str(binary)], check=True)
        break
revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
source_url = 'https://github.com/tommasobenatti/alt-tab-macos/tree/' + revision
notice = 'AltTab MCExp personal Release\nSource: ' + source_url + '\nUpstream PR: https://github.com/lwouis/alt-tab-macos/pull/6150\nLocal signature; not Apple-notarized.\n'
(app / 'Contents/Resources/MCEXP-SOURCE.txt').write_text(notice)
(stage / 'SOURCE.txt').write_text(notice)
(stage / 'LICENCE.md').write_bytes((repo / 'LICENCE.md').read_bytes())
plist = app / 'Contents/Info.plist'
metadata = plistlib.loads(plist.read_bytes())
metadata['MCExpSourceRevision'] = revision
metadata['MCExpPinnedBuild'] = True
plist.write_bytes(plistlib.dumps(metadata, fmt=plistlib.FMT_BINARY))
subprocess.run(['codesign', '--force', '--sign', identity, '--timestamp=none', '--options', 'runtime', '--entitlements', str(repo / 'alt_tab_macos.entitlements'), str(app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
archive = output / 'AltTab-MCExp-11.10.1-arm64.zip'
temporary_archive = output / (stage.parent.name + '.zip')
subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(stage), str(temporary_archive)], check=True)
os.replace(temporary_archive, archive)
receipt = {
    'version': metadata['CFBundleVersion'], 'source_revision': revision, 'source_url': source_url,
    'architecture': 'arm64', 'configuration': 'Release', 'pinned_background_updates': True,
    'signing': 'local ad-hoc' if identity == '-' else identity, 'notarized': False,
    'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
    'archive_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
    'app': str(app), 'archive': str(archive),
}
(output / 'build-receipt.json').write_text(json.dumps(receipt, indent=2))
(output / 'SHA256SUMS').write_text(receipt['archive_sha256'] + '  ' + archive.name + '\n')
print(json.dumps(receipt))
PY
