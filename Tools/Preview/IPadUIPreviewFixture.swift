import SwiftUI
import UIKit

enum IPadUIPreviewFixture {
    static var enabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--melox-ui-preview")
    }

    static var initialPeriod: UserPlayRecordPeriod {
        ProcessInfo.processInfo.arguments.contains("--preview-all") ? .allTime : .week
    }

    @ViewBuilder
    static var screen: some View {
        let arguments = ProcessInfo.processInfo.arguments

        Group {
            if arguments.contains("--preview-recognition") {
                SongRecognitionView()
            } else if arguments.contains("--preview-search") {
                SearchDiscoveryView()
                    .navigationTitle("ui.navigation.search")
            } else {
                UserListeningRankView(userID: 1)
                    .dynamicTypeSize(arguments.contains("--preview-large-text") ? .accessibility2 : .large)
            }
        }
        .task {
            guard UIDevice.current.userInterfaceIdiom == .pad else { return }
            try? await Task.sleep(for: .milliseconds(350))
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
            scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { error in
                print("Preview rotation: \(error)")
            }
        }
    }

    private static let sampleTracks: [(String, String, Int, Int)] = [
        ("月面电台", "柚子乐队", 1_976, 148),
        ("一颗卫星的晚安", "Mono / 纸飞机", 248, 208),
        ("海风穿过房间", "晚潮", 98, 120),
        ("Write Me a Map", "November Lanterns", 93, 218),
        ("下雪以前", "灰色云朵", 86, 303),
        ("A Quiet Orbit", "Kite Harbor", 23, 109),
        ("睡个好觉", "小小星球", 17, 84),
        ("1314", "未寄出的信 / 玻璃花房", 6, 214),
        ("Yours Again", "Echo Garden", 5, 165),
        ("最后一班夜车", "山谷 / 天青 / 雨林邮局", 4, 183),
        ("Bittersweet Chocolate", "Rainlight", 3, 240),
        ("星球的背面", "浮空灯塔", 2, 229),
    ]

    static func records(for period: UserPlayRecordPeriod) -> [UserPlayRecord] {
        let order = period == .week ? Array(sampleTracks.indices) : [3, 0, 6, 1, 4, 7, 5, 2, 8, 9, 10, 11]
        return order.enumerated().map { rank, index in
            let (title, artist, plays, seconds) = sampleTracks[index]
            let id = index + 1
            return UserPlayRecord(
                song: Song(
                    id: id,
                    name: title,
                    artists: [Artist(id: id, name: artist)],
                    album: Album(
                        id: id,
                        name: title,
                        picURL: index == 6 ? nil : "melox-preview://artwork/\(index)"
                    ),
                    durationMS: seconds * 1_000
                ),
                playCount: period == .week ? plays : 4_020 - rank * 357,
                score: nil
            )
        }
    }

    static func prepare(_ settings: AppSettings) {
        settings.hasCompletedOnboarding = true
        settings.appearance = .dark
        settings.setAppLanguage(.simplifiedChinese)
        UserDefaults.standard.set(Bundle.main.appReleaseVersion, forKey: "appReleaseNotes.lastPresentedVersion")
        PlaybackPersistence().save(
            PlaybackSnapshot(
                queue: records(for: .week).map(\.song),
                currentIndex: 0,
                progress: 36,
                repeatMode: "off",
                isShuffled: false,
                shuffledOrder: [],
                volume: 0.6,
                historySourceID: nil,
                heartModeEnabled: nil,
                autoplayEnabled: nil,
                autoMixEnabled: nil,
                queueModeIndicator: nil
            )
        )
    }

    static func artwork(for url: URL) -> some View {
        let index = Int(url.lastPathComponent) ?? 0
        let palettes: [(Color, Color, String)] = [
            (.teal, .indigo, "moon.stars.fill"),
            (.orange, .pink, "sparkles"),
            (.cyan, .blue, "water.waves"),
            (.brown, .orange, "mountain.2.fill"),
            (.blue, .gray, "snowflake"),
            (.pink, .purple, "circle.hexagongrid.fill"),
            (.indigo, .purple, "moon.zzz.fill"),
            (.green, .teal, "leaf.fill"),
        ]
        let (start, end, symbol) = palettes[index % palettes.count]
        return GeometryReader { geometry in
            LinearGradient(colors: [start, end.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: min(geometry.size.width, geometry.size.height) * 0.45, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
        }
    }
}
