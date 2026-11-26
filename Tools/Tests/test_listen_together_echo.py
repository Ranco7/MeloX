"""Listen-together echo recognition; logic only, no device or network claims."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

STORES = [
    "MeloX/Core/Playback/Session/ListenTogetherStore.swift",
    "MeloXDesktop/Core/Playback/Session/ListenTogetherStore.swift",
]
EVENTS = [
    "MeloX/Core/Playback/Session/ListenTogetherStore+PlayerEvents.swift",
    "MeloXDesktop/Core/Playback/Session/ListenTogetherStore+PlayerEvents.swift",
]
SYNCS = [
    "MeloX/Core/Playback/Session/ListenTogetherStore+Synchronization.swift",
    "MeloXDesktop/Core/Playback/Session/ListenTogetherStore+Synchronization.swift",
]
FOOTERS = [
    "MeloX/Features/ListenTogether/ListenTogetherSyncStatusView.swift",
    "MeloXDesktop/Features/ListenTogether/DesktopListenTogetherView.swift",
]

HARNESS = r"""
import Foundation

func check(_ name: String, _ condition: Bool) {
    if !condition {
        print("FAIL: " + name)
        exit(1)
    }
}

// Mirrors the store's echo rule: anything at or below the highest sequence
// this device submitted is our own echo, never a remote command.
func originatesLocally(
    commandSequence: Int64,
    commandUserID: String,
    localUserID: String,
    highestSubmitted: Int64
) -> Bool {
    guard commandSequence > 0, commandUserID == localUserID else { return false }
    return commandSequence <= highestSubmitted
}

@main struct EchoChecks {
@MainActor static func main() {
// A long room runs hundreds of commands. A fixed window of remembered
// sequences forgets the oldest ones; the monotonic high-water mark does not.
var highest: Int64 = 0
for _ in 1...200 {
    highest += 1
}
check(
    "the oldest own echo is still recognised after 200 commands",
    originatesLocally(
        commandSequence: 1, commandUserID: "1",
        localUserID: "1", highestSubmitted: highest
    )
)
check(
    "a fixed-length window would have forgotten it",
    1 < highest - 16
)

// Another member's command is always applied.
check(
    "a remote command is never treated as an echo",
    !originatesLocally(
        commandSequence: 3, commandUserID: "2",
        localUserID: "1", highestSubmitted: highest
    )
)
// A member command that reuses our sequence numbers is still remote.
check(
    "sequence collision across members is not an echo",
    !originatesLocally(
        commandSequence: highest, commandUserID: "2",
        localUserID: "1", highestSubmitted: highest
    )
)
// A zero sequence carries no identity and must never be swallowed.
check(
    "sequence zero is never an echo",
    !originatesLocally(
        commandSequence: 0, commandUserID: "1",
        localUserID: "1", highestSubmitted: highest
    )
)

// Rejoining resets the counter, so the mark must reset with it.
highest = 0
check(
    "a fresh session does not swallow the first remote command",
    !originatesLocally(
        commandSequence: 1, commandUserID: "2",
        localUserID: "1", highestSubmitted: highest
    )
)

print("PASS: echo recognition stays monotonic across a long room and resets on rejoin")
}
}
"""


def read(relative):
    return (ROOT / relative).read_text()


class EchoRecognitionTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("swiftc"), "Swift compiler unavailable")
    def test_monotonic_high_water_mark_survives_long_rooms(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "main.swift"
            source.write_text(HARNESS)
            executable = Path(directory) / "echo"
            compiled = subprocess.run(
                ["swiftc", "-parse-as-library", str(source), "-o", str(executable)],
                capture_output=True, text=True,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            print(result.stdout.strip())

    def test_both_platforms_use_the_monotonic_mark(self):
        for store in STORES:
            with self.subTest(store=store):
                source = read(store)
                self.assertIn("lastLocallyReportedCommandSequence: Int64 = 0", source)
                self.assertNotIn("locallyReportedCommandSequences", source)
                # A rejoin must reset the mark, or the next room's low
                # sequences would be read as our own echoes.
                self.assertIn("lastLocallyReportedCommandSequence = 0", source)

    def test_commands_are_recorded_before_the_request(self):
        for events in EVENTS:
            with self.subTest(events=events):
                source = read(events)
                send = source.split("private func sendCommand(", 1)[1]
                record = send.index("lastLocallyReportedCommandSequence = max")
                request = send.index("api.reportListenTogetherCommand(")
                self.assertLess(
                    record, request,
                    "the sequence must be recorded before the request so a lost "
                    "reply cannot turn our own echo into a remote seek",
                )

    def test_forced_sync_waits_instead_of_being_dropped(self):
        for sync in SYNCS:
            with self.subTest(sync=sync):
                source = read(sync)
                self.assertIn("func synchronizeFromServer(initial: Bool, force: Bool = false)", source)
                forced = source.split("if force {", 1)[1].split("guard synchronizingSession", 1)[0]
                self.assertIn("while synchronizingSession == session", forced)
                self.assertIn("transportReportTask != nil", forced)

    def test_forced_sync_still_ignores_local_echo(self):
        for sync in SYNCS:
            with self.subTest(sync=sync):
                source = read(sync)
                self.assertIn("!commandOriginatedLocally(command)", source)
                self.assertIn("force || commandChanged", source)

    def test_forced_sync_never_rewinds_from_a_stale_anchor(self):
        for sync in SYNCS:
            with self.subTest(sync=sync):
                source = read(sync)
                self.assertIn("hasTrustworthyAnchor", source)
                self.assertIn("player.estimatedProgress()", source)

    def test_sync_button_reports_progress_to_the_user(self):
        for footer in FOOTERS:
            with self.subTest(footer=footer):
                source = read(footer)
                self.assertIn("isRefreshing", source)
                self.assertIn("ui.listen_together.playback_synchronized", source)
                self.assertIn("lastSyncDate", source)

    def test_audio_interruption_is_not_broadcast_as_user_pause(self):
        # An interruption is the system taking audio away. Reporting it as a
        # transport command pauses every other member for a phone call.
        player = read("MeloX/Core/Playback/Session/PlayerStore.swift")
        began = player.split("private func handleAudioInterruptionBegan(", 1)[1]
        began = began.split("private func handleAudioInterruptionEnded(", 1)[0]
        ended = player.split("private func handleAudioInterruptionEnded(", 1)[1]
        ended = ended.split("\n    private func ", 1)[0]
        self.assertNotIn(
            "onListenTogetherTransport?(", began,
            "an audio interruption must not be broadcast as a room pause",
        )
        self.assertNotIn(
            "onListenTogetherTransport?(", ended,
            "resuming after an interruption is the system returning audio, "
            "not this device telling the room to play",
        )
        self.assertIn("shouldResumeAfterInterruption", began)
        self.assertIn("engine.pause()", began)

    def test_audio_route_loss_is_still_treated_as_a_local_stop(self):
        # Losing the output route (unplugging headphones) is also local; it
        # must not leave the room believing this member paused on purpose.
        player = read("MeloX/Core/Playback/Session/PlayerStore.swift")
        began = player.split("private func handleAudioInterruptionBegan(", 1)[1]
        began = began.split("private func handleAudioInterruptionEnded(", 1)[0]
        self.assertIn("routeDisconnected", began)


if __name__ == "__main__":
    unittest.main()
