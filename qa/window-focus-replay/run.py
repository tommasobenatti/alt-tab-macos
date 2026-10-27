#!/usr/bin/env python3
from pathlib import Path
import argparse
import os
import re
import subprocess
import tempfile

parser = argparse.ArgumentParser(description='Replay AltTab focus records against owned SDL, AppKit and WebKit windows.')
parser.add_argument('--baseline', action='store_true', help='Replay unmodified 11.10.1; failure is expected.')
parser.add_argument('--sdl-library', type=Path)
parser.add_argument('--sdl-include', type=Path)
parser.add_argument('--keep-build', action='store_true', help='Keep the bridge for the optional Electron replay.')
args = parser.parse_args()
folder = Path(__file__).resolve().parent
repo = folder.parents[1]
prefix = None
if args.sdl_library is None or args.sdl_include is None:
    prefix = Path(subprocess.check_output(['brew', '--prefix', 'sdl3'], text=True).strip())
library = (args.sdl_library or prefix / 'lib/libSDL3.dylib').resolve()
include = args.sdl_include or prefix / 'include'
if not library.is_file() or not (include / 'SDL3/SDL.h').is_file():
    parser.error('SDL3 library or headers were not found. Install sdl3 or provide both paths.')
source_path = 'src/macos/api-wrappers/SkyLight.framework.swift'
if args.baseline:
    source = subprocess.check_output(['git', 'show', 'c500294:' + source_path], cwd=repo, text=True)
    event = re.search(r'private enum MakeKeyWindowEvent \{.*?^\}', source, re.S | re.M).group(0)
else:
    source = (repo / source_path).read_text()
    event = (repo / 'src/macos/api-wrappers/WindowFocusEvent.swift').read_text()
emitter = re.search(r'^func makeKeyWindow\(.*?^\}', source, re.S | re.M).group(0)
bridge = '''import Cocoa
import Carbon
@_silgen_name("GetProcessForPID") @discardableResult
func GetPsnForPid(_ pid: Int32, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> Int32
@_silgen_name("SLPSPostEventRecordTo") @discardableResult
func SLPSPostEventRecordTo(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ bytes: UnsafeMutablePointer<UInt8>) -> CGError
@_silgen_name("_SLPSSetFrontProcessWithOptions") @discardableResult
func SetFront(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ wid: UInt32, _ mode: UInt32) -> CGError
''' + event + '\n' + emitter + '''
@_cdecl("postProductionFocus")
public func postProductionFocus(_ pid: Int32, _ wid: UInt32, _ unused: Int32) {
    var psn = ProcessSerialNumber()
    GetPsnForPid(pid, &psn)
    SetFront(&psn, wid, 0x200)
    makeKeyWindow(&psn, wid)
}
@_cdecl("postFocusRelease")
public func postFocusRelease(_ pid: Int32, _ wid: UInt32) {
    var psn = ProcessSerialNumber()
    GetPsnForPid(pid, &psn)
    var window = wid
    var point = CGPoint(x: 300_000, y: 300_000)
    var bytes = [UInt8](repeating: 0, count: 0x100)
    bytes[0x04] = 0xf8
    bytes[0x3a] = 0x10
    memcpy(&bytes[0x3c], &window, MemoryLayout<CGWindowID>.size)
    memcpy(&bytes[0x20], &point, MemoryLayout<CGPoint>.size)
    bytes[0x08] = 0x02
    SLPSPostEventRecordTo(&psn, &bytes)
}
'''
build = Path(tempfile.mkdtemp(prefix='alttab-focus-replay-'))
environment = os.environ.copy()
environment['MACOSX_DEPLOYMENT_TARGET'] = '12.0'
try:
    (build / 'Bridge.swift').write_text(bridge)
    (build / 'libSDL3.0.dylib').symlink_to(library)
    subprocess.run(['swiftc', '-swift-version', '5', '-emit-library', str(build / 'Bridge.swift'), '-o', str(build / 'libGeneralProbeBridge.dylib'), '-F', '/System/Library/PrivateFrameworks', '-framework', 'SkyLight'], check=True, env=environment)
    subprocess.run(['clang', '-fobjc-arc', str(folder / 'native.m'), '-I' + str(include), '-L' + str(build), '-lGeneralProbeBridge', str(library), '-framework', 'Cocoa', '-framework', 'WebKit', '-Wl,-rpath,' + str(build), '-Wl,-rpath,' + str(library.parent), '-o', str(build / 'replay')], check=True, env=environment)
    result = subprocess.run([str(build / 'replay')], env=environment)
    print('Bridge directory:', build, flush=True)
    raise SystemExit(result.returncode)
finally:
    if not args.keep_build:
        import shutil
        shutil.rmtree(build)
