#!/usr/bin/env python3
"""Validate the built .appex and (optionally) its exact IPA metadata.

This checks packaging only. An unsigned IPA cannot grant App Group permissions.
"""
import argparse
import plistlib
import zipfile
from pathlib import Path

EXTENSION = "MeloXBroadcastUpload.appex"
POINT = "com.apple.broadcast-services-upload"
MODE = "RPBroadcastProcessModeSampleBuffer"


def verify(app, ipa=None, metadata=None):
    app = Path(app)
    extension = app / "PlugIns" / EXTENSION
    main_info = plistlib.loads((app / "Info.plist").read_bytes())
    extension_info = plistlib.loads((extension / "Info.plist").read_bytes())
    app_id = main_info["CFBundleIdentifier"]
    expected_id = app_id + ".BroadcastUpload"
    group = "group." + app_id + ".recognition"
    assert extension_info["CFBundleIdentifier"] == expected_id, "Broadcast extension bundle ID mismatch"
    assert main_info["MeloXBroadcastExtensionID"] == expected_id, "Picker extension ID mismatch"
    assert main_info["MeloXBroadcastAppGroup"] == group, "Host App Group mismatch"
    assert extension_info["MeloXBroadcastAppGroup"] == group, "Extension App Group mismatch"
    config = extension_info["NSExtension"]
    assert config["NSExtensionPointIdentifier"] == POINT, "Wrong extension point"
    assert config["NSExtensionAttributes"]["RPBroadcastProcessMode"] == MODE, "Wrong process mode"
    assert config["NSExtensionPrincipalClass"].endswith(".SampleHandler"), "Wrong sample handler"
    assert (extension / extension_info["CFBundleExecutable"]).is_file(), "Missing extension executable"
    for key in ("CFBundleShortVersionString", "CFBundleVersion"):
        assert main_info[key] == extension_info[key], "App/extension version mismatch"
    if metadata:
        Path(metadata).write_bytes(plistlib.dumps({
            "AppBundleIdentifier": app_id,
            "ExtensionBundleIdentifier": expected_id,
            "RequiredApplicationGroupsForBothTargets": [group],
            "Note": "Requirements only. Both signatures and provisioning profiles must permit this group. Unsigned metadata grants no permissions.",
        }))
    if ipa:
        with zipfile.ZipFile(ipa) as archive:
            prefix = "Payload/MeloX.app/PlugIns/" + EXTENSION + "/"
            packed = plistlib.loads(archive.read(prefix + "Info.plist"))
            assert packed == extension_info, "IPA contains different extension metadata"
            assert prefix + packed["CFBundleExecutable"] in archive.namelist(), "IPA missing extension executable"
            packed_app = plistlib.loads(archive.read("Payload/MeloX.app/Info.plist"))
            assert packed_app == main_info, "IPA contains different host metadata"
    return group


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app")
    parser.add_argument("--ipa")
    parser.add_argument("--metadata")
    args = parser.parse_args()
    group = verify(args.app, args.ipa, args.metadata)
    print("Broadcast packaging verified; required App Group:", group)


if __name__ == "__main__":
    main()
