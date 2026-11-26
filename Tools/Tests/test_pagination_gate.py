"""Pagination footer page-request gate; logic only, no SwiftUI rendering claims."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

GATES = [
    "MeloX/Shared/Components/MusicCollectionPageRequestGate.swift",
    "MeloXDesktop/Shared/MusicCollectionPageRequestGate.swift",
]
FOOTERS = [
    "MeloX/Shared/Components/MusicCollectionPaginationFooter.swift",
    "MeloXDesktop/Shared/DesktopCollectionPaginationFooter.swift",
]

HARNESS = r"""
import Foundation

func check(_ name: String, _ condition: Bool) {
    if !condition {
        print("FAIL: " + name)
        exit(1)
    }
}

@main struct PaginationGateChecks {
@MainActor static func main() {
// The regression: a page publishes its new offset before it stops loading.
// The footer sees the new token while `isLoading` is still true.
var gate = MusicCollectionPageRequestGate()
check("first page request", gate.shouldRequest(token: 0, isLoading: false, hasFailure: false))
check("in-flight page is not requested twice", !gate.shouldRequest(token: 0, isLoading: true, hasFailure: false))
check("same token never repeats", !gate.shouldRequest(token: 0, isLoading: false, hasFailure: false))

// Token advanced during the request; the guarded pass must not consume it.
check("token published mid-load is deferred", !gate.shouldRequest(token: 100, isLoading: true, hasFailure: false))
// ...and then retried once loading settles, instead of spinning forever.
check("deferred token is requested when loading settles", gate.shouldRequest(token: 100, isLoading: false, hasFailure: false))
check("requested token is not repeated", !gate.shouldRequest(token: 100, isLoading: false, hasFailure: false))

// Failures surface a retry button; auto-loading must not fight it.
check("failure blocks auto request", !gate.shouldRequest(token: 200, isLoading: false, hasFailure: true))
check("failure clears and request resumes", gate.shouldRequest(token: 200, isLoading: false, hasFailure: false))

// A footer without a token (list bottom) must not ask for anything.
var idle = MusicCollectionPageRequestGate()
check("nil token never requests", !idle.shouldRequest(token: nil, isLoading: false, hasFailure: false))
check("nil token does not consume a later token", idle.shouldRequest(token: 7, isLoading: false, hasFailure: false))

// Repeated settle notifications must not loop.
var settle = MusicCollectionPageRequestGate()
check("first settle request", settle.shouldRequest(token: 31, isLoading: false, hasFailure: false))
for _ in 0..<5 {
    check("repeated settle is a no-op", !settle.shouldRequest(token: 31, isLoading: false, hasFailure: false))
}

// reset() (it exists for pull-to-refresh style flows) re-arms the gate.
settle.reset()
check("reset re-arms the same token", settle.shouldRequest(token: 31, isLoading: false, hasFailure: false))

print("PASS: pagination gate defers a mid-load token, retries on settle, and never loops")
}
}
"""


def read(relative):
    return (ROOT / relative).read_text()


class PaginationFooterTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("swiftc"), "Swift compiler unavailable")
    def test_gate_defers_mid_load_token_and_retries(self):
        for gate in GATES:
            with self.subTest(gate=gate), tempfile.TemporaryDirectory() as directory:
                source = Path(directory) / "main.swift"
                source.write_text(read(gate) + HARNESS)
                executable = Path(directory) / "gate"
                compiled = subprocess.run(
                    ["swiftc", "-parse-as-library", str(source), "-o", str(executable)],
                    capture_output=True, text=True,
                )
                self.assertEqual(compiled.returncode, 0, compiled.stderr)
                result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                print(result.stdout.strip())

    def test_both_gates_stay_identical(self):
        a, b = (read(gate) for gate in GATES)
        self.assertEqual(a, b, "the iOS and macOS gate implementations drifted apart")

    def test_footers_retry_when_loading_settles(self):
        for footer in FOOTERS:
            with self.subTest(footer=footer):
                source = read(footer)
                self.assertIn("MusicCollectionPageRequestGate", source)
                # A token published during a load must be retried on settle,
                # otherwise the footer spins forever on a page nobody asked for.
                self.assertIn(".onChange(of: isLoading)", source)
                self.assertIn("shouldRequest(", source)

    def test_ios_footer_no_longer_gates_without_retry(self):
        source = read(FOOTERS[0])
        self.assertNotIn("guard !isLoading else { return }", source)


if __name__ == "__main__":
    unittest.main()
