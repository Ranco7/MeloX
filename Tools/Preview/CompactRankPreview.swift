import SwiftUI
import UIKit

@main
struct CompactRankPreview: App {
    @State private var api = NeteaseAPI()
    @State private var player = PlayerStore()
    @State private var path = [1]

    var body: some Scene {
        WindowGroup {
            Group {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    NavigationSplitView {
                        List {
                            Label("首页", systemImage: "house")
                            Label("音乐", systemImage: "music.note")
                            Label("播客", systemImage: "dot.radiowaves.left.and.right")
                            Label("发现", systemImage: "safari")
                            Label("音乐库", systemImage: "music.note.list")
                            Label("搜索", systemImage: "magnifyingglass")
                        }
                        .listStyle(.sidebar)
                        .navigationSplitViewColumnWidth(min: 220, ideal: 246, max: 260)
                    } detail: {
                        rank
                    }
                    .navigationSplitViewStyle(.balanced)
                } else {
                    rank
                }
            }
            .environment(api)
            .environment(player)
            .environment(\.locale, Locale(identifier: "zh-Hans"))
            .tint(.red)
            .preferredColorScheme(.dark)
            .task {
                guard UIDevice.current.userInterfaceIdiom == .pad else { return }
                try? await Task.sleep(for: .milliseconds(300))
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first?
                    .requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
            }
        }
    }

    private var rank: some View {
        NavigationStack(path: $path) {
            Color.clear
                .navigationDestination(for: Int.self) { userID in
                    UserListeningRankView(userID: userID)
                        .dynamicTypeSize(
                            ProcessInfo.processInfo.arguments.contains("--large-text")
                                ? .accessibility2 : .large
                        )
                }
        }
    }
}

nonisolated struct Song: Codable, Hashable {
    let id: Int
    let name: String
    let artist: String
    let length: String
}

@Observable
final class NeteaseAPI {
    func userPlayRecords(userID: Int, period: UserPlayRecordPeriod) async throws -> [UserPlayRecord] {
        let titles = ["月面电台", "一颗卫星的晚安", "海风穿过房间", "Write Me a Map", "下雪以前", "A Quiet Orbit", "睡个好觉", "1314", "Yours Again", "最后一班夜车", "Bittersweet Chocolate"]
        let artists = ["柚子乐队", "Mono / 纸飞机", "晚潮", "November Lanterns", "灰色云朵", "Kite Harbor", "小小星球", "未寄出的信", "Echo Garden", "山谷 / 天青", "Rainlight"]
        let durations = ["2:28", "3:28", "2:00", "3:38", "5:03", "1:49", "1:24", "3:34", "2:45", "3:03", "4:00"]
        let plays = [1_976, 248, 98, 93, 86, 23, 17, 6, 5, 4, 3]
        let order = period == .week ? Array(titles.indices) : [3, 0, 6, 1, 4, 7, 5, 2, 8, 9, 10]
        return order.enumerated().map { rank, index in
            UserPlayRecord(
                song: Song(id: index + 1, name: titles[index], artist: artists[index], length: durations[index]),
                playCount: period == .week ? plays[index] : 4_020 - rank * 357,
                score: nil
            )
        }
    }
}

@Observable
final class PlayerStore {
    private(set) var lastSong: Song?

    func play(_ song: Song, in queue: [Song]) async {
        lastSong = song
    }

    func playAll(_ queue: [Song]) async {
        lastSong = queue.first
    }
}

enum LoadingPhase: Equatable {
    case loading
    case loaded
    case failed(String)
}

enum L10n {
    static let locale = Locale(identifier: "zh-Hans")

    static func string(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func format(_ key: String, _ count: Int) -> String {
        String(format: string(key), locale: locale, count)
    }
}

struct ConnectionUnavailableView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(message, systemImage: "wifi.slash")
        } actions: {
            Button("ui.common.retry", action: retry)
        }
    }
}

struct TrackRowView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var indexWidth: CGFloat = 26

    let song: Song
    var index: Int?
    var showsArtwork = false
    var secondaryMetadata: String?

    var body: some View {
        HStack(spacing: 12) {
            if let index {
                Text((index + 1).formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: indexWidth, alignment: .trailing)
            }
            if showsArtwork {
                cover
                    .frame(width: 44, height: 44)
                    .clipShape(.rect(cornerRadius: 6))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(song.name).lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                Text([song.artist, secondaryMetadata].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(song.length)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
    }

    private var cover: some View {
        let colors: [Color] = [.teal, .purple, .blue, .orange, .cyan, .indigo, .gray, .mint]
        let symbols = ["moon.stars.fill", "sparkles", "water.waves", "mountain.2.fill", "snowflake", "circle.hexagongrid.fill", "music.note", "leaf.fill"]
        let index = (song.id - 1) % colors.count
        return LinearGradient(colors: [colors[index], colors[index].opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                Image(systemName: symbols[index])
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)
            }
    }
}
