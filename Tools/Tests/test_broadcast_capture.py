"""Broadcast production-core runners plus packaging and API-use contracts.

Run: python3 -m unittest Tools.Tests.test_broadcast_capture -v
Swift behavior checks are explicitly skipped if a Swift compiler is unavailable.
"""
import copy
import importlib.util
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("verify_broadcast_bundle", ROOT / "Tools/verify_broadcast_bundle.py")
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


def read(path):
    return (ROOT / path).read_text()


CORE = ["MeloXBroadcastShared/BroadcastPCM.swift", "MeloXBroadcastShared/BroadcastSession.swift", "MeloXBroadcastShared/BroadcastMailbox.swift"]


class PackagingChecks(unittest.TestCase):
    def fixture(self, root, app_id):
        app = root / "Payload/MeloX.app"
        extension = app / "PlugIns/MeloXBroadcastUpload.appex"
        extension.mkdir(parents=True)
        group = "group." + app_id + ".recognition"
        main = {"CFBundleIdentifier": app_id, "MeloXBroadcastExtensionID": app_id + ".BroadcastUpload",
                "MeloXBroadcastAppGroup": group, "CFBundleVersion": "9110401", "CFBundleShortVersionString": "2.0"}
        ext = {"CFBundleIdentifier": app_id + ".BroadcastUpload", "MeloXBroadcastAppGroup": group,
               "CFBundleVersion": "9110401", "CFBundleShortVersionString": "2.0", "CFBundleExecutable": "MeloXBroadcastUpload",
               "NSExtension": {"NSExtensionPointIdentifier": verifier.POINT,
                               "NSExtensionPrincipalClass": "MeloXBroadcastUpload.SampleHandler",
                               "NSExtensionAttributes": {"RPBroadcastProcessMode": verifier.MODE}}}
        (app / "Info.plist").write_bytes(plistlib.dumps(main))
        (extension / "Info.plist").write_bytes(plistlib.dumps(ext))
        (extension / "MeloXBroadcastUpload").write_bytes(b"fixture executable")
        return app, extension, ext

    def test_both_identities_and_exact_ipa_embedding(self):
        for app_id in ("moye.MeloX", "azki.moye.MeloX"):
            with self.subTest(app_id=app_id), tempfile.TemporaryDirectory(dir=ROOT) as tmp:
                root = Path(tmp)
                app, extension, info = self.fixture(root, app_id)
                ipa = root / "fixture.ipa"
                with zipfile.ZipFile(ipa, "w") as archive:
                    for path in app.rglob("*"):
                        if path.is_file():
                            archive.write(path, path.relative_to(root))
                self.assertEqual(verifier.verify(app, ipa), "group." + app_id + ".recognition")
                # A zip without the binary is not a valid embedded extension.
                with zipfile.ZipFile(ipa, "w") as archive:
                    archive.write(extension / "Info.plist", "Payload/MeloX.app/PlugIns/MeloXBroadcastUpload.appex/Info.plist")
                with self.assertRaises(AssertionError):
                    verifier.verify(app, ipa)

    def test_packaging_rejects_group_point_mode_and_binary_errors(self):
        with tempfile.TemporaryDirectory(dir=ROOT) as tmp:
            app, extension, baseline = self.fixture(Path(tmp), "moye.MeloX")
            mutations = [lambda i: i.update(MeloXBroadcastAppGroup="group.other"),
                         lambda i: i["NSExtension"].update(NSExtensionPointIdentifier="wrong"),
                         lambda i: i["NSExtension"]["NSExtensionAttributes"].update(RPBroadcastProcessMode="wrong")]
            for mutation in mutations:
                info = copy.deepcopy(baseline)
                mutation(info)
                (extension / "Info.plist").write_bytes(plistlib.dumps(info))
                with self.assertRaises(AssertionError):
                    verifier.verify(app)
            (extension / "Info.plist").write_bytes(plistlib.dumps(baseline))
            (extension / "MeloXBroadcastUpload").unlink()
            with self.assertRaises(AssertionError):
                verifier.verify(app)

    def test_target_dependency_embedding_and_shared_entitlement_contract(self):
        project = read("MeloX.xcodeproj/project.pbxproj")
        # References are checked separately: a named target alone is insufficient.
        for token in ["BC0000000000000000000001 /* MeloXBroadcastUpload.appex in Embed Foundation Extensions */,",
                      "BC0000000000000000000004 /* PBXTargetDependency */,",
                      "target = BC0000000000000000000007;", "remoteGlobalIDString = BC0000000000000000000007;",
                      'PRODUCT_BUNDLE_IDENTIFIER = "$(MELOX_APP_BUNDLE_IDENTIFIER).BroadcastUpload";',
                      'MELOX_BROADCAST_APP_GROUP = "group.$(MELOX_APP_BUNDLE_IDENTIFIER).recognition";']:
            self.assertIn(token, project)
        self.assertEqual(project.count("BC0000000000000000000008 /* MeloXBroadcastShared */,"), 2)
        for path in ["MeloX/MeloX.entitlements", "MeloXBroadcastUpload/MeloXBroadcastUpload.entitlements"]:
            groups = plistlib.loads((ROOT / path).read_bytes())["com.apple.security.application-groups"]
            self.assertIn("$(MELOX_BROADCAST_APP_GROUP)", groups)
        info = plistlib.loads((ROOT / "MeloXBroadcastUpload/Info.plist").read_bytes())
        self.assertEqual(info["NSExtension"]["NSExtensionAttributes"]["RPBroadcastProcessMode"], verifier.MODE)
        self.assertIn("verify_broadcast_bundle.py", read("build_ios_unsigned.sh"))
        self.assertIn("--ipa", read("build_ios_unsigned.sh"))
        self.assertIn("verify_broadcast_bundle.py", read(".github/workflows/unsigned-ios-ipa.yml"))
        self.assertIn("CODE_SIGNING_ALLOWED=NO", read("build_ios_unsigned.sh"))


class CaptureSourceContracts(unittest.TestCase):
    def test_visible_public_picker_and_early_video_microphone_rejection(self):
        picker = read("MeloX/Features/SongRecognition/SongRecognitionBroadcastPicker.swift")
        self.assertIn("RPSystemBroadcastPickerView(frame:", picker)
        self.assertIn("preferredExtension = extensionID", picker)
        self.assertIn("showsMicrophoneButton = false", picker)
        self.assertIn("accessibilityLabel", picker)
        for forbidden in ["subviews", "sendActions", "performSelector", "isHidden", "alpha =", "RPScreenRecorder"]:
            self.assertNotIn(forbidden, picker)
        handler = read("MeloXBroadcastUpload/SampleHandler.swift")
        self.assertLess(handler.index("guard sampleBufferType == .audioApp"), handler.index("BroadcastSamplePCM.decode"))
        self.assertNotIn("async", handler)
        for forbidden in ["Netease", "WebKit", "URLSession", "AVAudioEngine", "AVAssetWriter"]:
            self.assertNotIn(forbidden, handler)
        self.assertIn("DispatchSource.makeTimerSource", handler)
        self.assertIn("finishBroadcastWithError", handler)

    def test_host_suspension_and_recovery_contract(self):
        client = read("MeloX/Features/SongRecognition/SongRecognitionBroadcastClient.swift")
        self.assertIn("actor SongRecognitionBroadcastClient", client)
        self.assertIn("guard let", client)
        self.assertIn("containerURL", client)
        self.assertNotIn("containerURL(forSecurityApplicationGroupIdentifier: group)!", client)
        store = read("MeloX/Features/SongRecognition/SongRecognitionStore.swift")
        self.assertIn("applicationState != .active", store)
        self.assertIn("resumeBroadcastIfNeeded", store)
        self.assertIn("broadcastClient.stop(request, command: .cancel)", store)
        self.assertIn("generation == currentGeneration", store)
        self.assertIn("duration.maximumDuration ?? 9", store)
        self.assertNotIn("playbackAudio", store)
        mailbox = read("MeloXBroadcastShared/BroadcastMailbox.swift")
        self.assertIn("options: .atomic", mailbox)
        self.assertNotIn("NSFileCoordinator", mailbox)
        self.assertNotIn("flock", mailbox)

    def test_pcm_is_described_by_asbd_and_copy_is_bounded(self):
        adapter = read("MeloXBroadcastUpload/BroadcastSamplePCM.swift")
        for token in ["asbd.mSampleRate", "kAudioFormatFlagIsBigEndian", "kAudioFormatFlagIsNonInterleaved",
                      "kAudioFormatFlagIsSignedInteger", "16_384", "1_048_576"]:
            self.assertIn(token, adapter)
        self.assertNotIn("timescale", adapter)

    def test_neutral_localized_privacy_and_limit_copy(self):
        keys = set()
        for language in ["en", "zh-Hans"]:
            strings = read(f"MeloXLocalization/{language}.lproj/Localizable.strings")
            lines = dict(re.findall(r'^"(ui\.recognition\.broadcast\.[^"]+)" = "(.*)";', strings, re.M))
            if keys:
                self.assertEqual(set(lines), keys)
            keys = set(lines)
            self.assertNotIn("ui.recognition.broadcast.protected", lines)
            self.assertIn("受保护" if language == "zh-Hans" else "protected", lines["ui.recognition.broadcast.silent"])
            self.assertNotIn("喵", " ".join(lines.values()))
            self.assertIn("screen" if language == "en" else "画面", lines["ui.recognition.broadcast.privacy"])

    def test_source_names_and_microphone_duration_copy_follow_preferences(self):
        for language in ["en", "zh-Hans"]:
            strings = dict(re.findall(r'^"([^\"]+)" = "(.*)";',
                read(f"MeloXLocalization/{language}.lproj/Localizable.strings"), re.M))
            self.assertEqual(strings["ui.recognition.source.microphone"], "Microphone" if language == "en" else "麦克风")
            self.assertEqual(strings["ui.recognition.source.appAudio"], "Device Audio" if language == "en" else "设备音频")
            limited = strings["ui.recognition.ready.limited"]
            continuous = strings["ui.recognition.ready.continuous"]
            self.assertEqual(limited.count("%@"), 1)
            self.assertNotIn("%@", continuous)
            for text in [limited, continuous]:
                self.assertIn("MeloX", text)
                self.assertNotIn("iPhone", text)
                self.assertNotIn("Melox", text)
                self.assertNotRegex(text, r"[369]\s*(?:秒|seconds)")
                self.assertIn("your device" if language == "en" else "设备", text)
                self.assertIn("fingerprint generated on your device" if language == "en" else "设备端生成的音频指纹", text)
                self.assertIn("NetEase Cloud Music" if language == "en" else "网易云音乐", text)
            self.assertIn("stops on a match" if language == "en" else "识别后立即停止", limited)
            self.assertIn("until you stop" if language == "en" else "直到你停止", continuous)
            self.assertEqual(strings["ui.recognition.capture.limited"].count("%@"), 1)
            for seconds in [3, 6, 9]:
                rendered = limited.replace("%@", f"{seconds} seconds" if language == "en" else f"{seconds} 秒")
                self.assertIn(str(seconds), rendered)
        view = read("MeloX/Features/SongRecognition/SongRecognitionView.swift")
        self.assertIn('L10n.format("ui.recognition.ready.limited", duration.title)', view)
        preferences = read("MeloX/Core/Settings/Recognition/SongRecognitionPreferences.swift")
        self.assertIn("case balanced = 6", preferences)
        self.assertIn("duration = .balanced", preferences)

    def test_static_device_copy_is_accurate_and_wraps_without_protection_warning(self):
        for language in ["en", "zh-Hans"]:
            strings = dict(re.findall(r'^"([^\"]+)" = "(.*)";',
                read(f"MeloXLocalization/{language}.lproj/Localizable.strings"), re.M))
            detail = strings["ui.recognition.source.appAudio.detail"]
            waiting = strings["ui.recognition.broadcast.instructions"]
            privacy = strings["ui.recognition.broadcast.privacy"]
            for text in [detail, waiting]:
                self.assertIn("screen broadcast" if language == "en" else "屏幕广播", text.lower())
                self.assertIn("red system indicator" if language == "en" else "红色系统指示", text)
                self.assertIn("ends automatically" if language == "en" else "自动结束", text)
                self.assertIn("return to MeloX" if language == "en" else "返回 MeloX", text.replace("Return", "return"))
            self.assertIn("device audio only" if language == "en" else "仅处理设备音频", detail)
            self.assertIn("No screen data is saved or sent" if language == "en" else "画面不保存、不发送", privacy)
            for key in ["ui.recognition.source.appAudio.detail", "ui.recognition.capture.limited",
                        "ui.recognition.capture.continuous", "ui.recognition.capture_permission_message",
                        "ui.recognition.broadcast.instructions", "ui.recognition.broadcast.privacy"]:
                for word in ["DRM", "protected", "Apple Music", "受保护", "保护音频"]:
                    self.assertNotIn(word, strings[key])
        view = read("MeloX/Features/SongRecognition/SongRecognitionView.swift")
        self.assertNotIn("ui.recognition.broadcast.protected", view)
        self.assertGreaterEqual(view.count(".fixedSize(horizontal: false, vertical: true)"), 4)
        self.assertNotIn(".lineLimit(1)", view)
        self.assertNotIn(".minimumScaleFactor", view)

    def test_device_settings_footer_uses_capture_limits_and_scopes_group_requirement(self):
        settings = read("MeloX/Features/Settings/Application/ContentSettingsView.swift")
        device_footer = settings.split("if recognition.audioSource == .appAudio {", 1)[1].split("} else if", 1)[0]
        self.assertIn('Text("ui.recognition.system_audio_availability")', device_footer)
        self.assertIn('"ui.recognition.capture.continuous"', device_footer)
        self.assertIn('L10n.format("ui.recognition.capture.limited", recognition.duration.title)', device_footer)
        self.assertNotIn('"ui.settings.content.recognition.footer.continuous"', device_footer)
        self.assertNotIn('"ui.settings.content.recognition.footer.limited"', device_footer)
        self.assertIn('.fixedSize(horizontal: false, vertical: true)', settings)


class SwiftBehaviorChecks(unittest.TestCase):
    def run_swift(self, sources):
        with tempfile.TemporaryDirectory(prefix=".broadcast-checks-", dir=ROOT) as directory:
            binary = str(Path(directory) / "checks")
            subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library",
                            *[str(ROOT / source) for source in sources], "-o", binary], check=True)
            subprocess.run([binary], check=True, cwd=ROOT, timeout=30)

    @unittest.skipUnless(shutil.which("swiftc"), "Swift compiler unavailable")
    def test_portable_pcm_ring_session_mailbox_behavior(self):
        self.run_swift(CORE + ["Tests/SongRecognition/BroadcastCoreChecks.swift"])

    @unittest.skipUnless(sys.platform == "darwin" and shutil.which("swiftc"), "Requires macOS CoreMedia SDK")
    def test_real_asbd_big_endian_cmsamplebuffer(self):
        self.run_swift([CORE[0], "MeloXBroadcastUpload/BroadcastSamplePCM.swift", "Tests/SongRecognition/BroadcastSamplePCMChecks.swift"])


if __name__ == "__main__":
    unittest.main()
