#!/bin/bash
# Standalone checks only: no device capture, signing, simulator, or network.
set -euo pipefail
cd "$(dirname "$0")/../.."
CHECK_BUILD_DIR="${BROADCAST_CHECK_BUILD_DIR:-build/BroadcastChecks}"
mkdir -p "$CHECK_BUILD_DIR"
CORE=(MeloXBroadcastShared/BroadcastPCM.swift MeloXBroadcastShared/BroadcastSession.swift MeloXBroadcastShared/BroadcastMailbox.swift)
xcrun swiftc -swift-version 5 -parse-as-library "${CORE[@]}" \
  Tests/SongRecognition/BroadcastCoreChecks.swift -o "$CHECK_BUILD_DIR/core"
"$CHECK_BUILD_DIR/core"
xcrun swiftc -swift-version 5 -parse-as-library MeloXBroadcastShared/BroadcastPCM.swift \
  MeloXBroadcastUpload/BroadcastSamplePCM.swift Tests/SongRecognition/BroadcastSamplePCMChecks.swift \
  -o "$CHECK_BUILD_DIR/sample-pcm"
"$CHECK_BUILD_DIR/sample-pcm"
xcrun swiftc -swift-version 5 -parse-as-library "${CORE[@]}" \
  MeloX/Core/Settings/Recognition/SongRecognitionAudioSource.swift \
  MeloX/Core/Settings/Recognition/SongRecognitionPreferences.swift \
  MeloX/Core/Models/Networking/AudioMatchResponse.swift \
  MeloX/Features/SongRecognition/SongRecognitionRecording.swift \
  MeloX/Features/SongRecognition/SongRecognitionResult.swift \
  MeloX/Features/SongRecognition/SongRecognitionBroadcastClient.swift \
  MeloX/Features/SongRecognition/SongRecognitionStore.swift \
  Tests/SongRecognition/RecognitionStateChecks.swift -o "$CHECK_BUILD_DIR/state"
"$CHECK_BUILD_DIR/state"
xcrun swiftc -swift-version 5 -parse-as-library \
  MeloX/Features/SongRecognition/SongRecognitionSampleBuffer.swift \
  MeloX/Features/SongRecognition/SongRecognitionCapturedAudioBuffer.swift \
  Tests/SongRecognition/CapturedAudioBufferChecks.swift -o "$CHECK_BUILD_DIR/captured-audio"
"$CHECK_BUILD_DIR/captured-audio"
