import SwiftUI
import UIKit

@main
struct CompactRankPreview: App {
    @State private var api = NeteaseAPI()
    @State private var player = PlayerStore()
    @State private var library = LibraryStore()
    @State private var downloads = DownloadStore()
    @State private var path = [1]

    var body: some Scene {
        WindowGroup {
            Group {
                if ProcessInfo.processInfo.arguments.contains("--compact") {
                    rank
                        .environment(\.horizontalSizeClass, .compact)
                        .frame(width: 390)
                        .clipped()
                } else if UIDevice.current.userInterfaceIdiom == .pad {
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
            .environment(library)
            .environment(downloads)
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
                                ? .accessibility3 : .large
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

    var artistText: String { artist }
    var durationMS: Int { 1 }
    var durationText: String { length }
    var isPodcastProgram: Bool { false }
    var album: PreviewAlbum? {
        PreviewAlbum(artworkURL: id == 7 ? nil : URL(string: "melox-preview://cover/\(id)"))
    }
}

nonisolated struct PreviewAlbum {
    let artworkURL: URL?
}

@Observable
final class NeteaseAPI {
    func userPlayRecords(userID: Int, period: UserPlayRecordPeriod) async throws -> [UserPlayRecord] {
        let titles = ["月面电台", "一颗卫星的晚安", "海风穿过房间", "Write Me a Map", "下雪以前", "A Quiet Orbit", "睡个好觉", "1314", "Yours Again", "最后一班夜车", "Bittersweet Chocolate"]
        let artists = ["柚子乐队 / November Lanterns / 玻璃海岸乐团", "Mono / 纸飞机", "晚潮", "November Lanterns", "灰色云朵", "Kite Harbor", "小小星球", "未寄出的信", "Echo Garden", "山谷 / 天青", "Rainlight"]
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

    func playNext(_ song: Song) async {
        lastSong = song
    }
}

@Observable
final class LibraryStore {
    func contains(song: Song) -> Bool { false }
    func toggle(song: Song) {}
}

@Observable
final class DownloadStore {
    func isDownloading(songID: Int) -> Bool { false }
    func contains(songID: Int) -> Bool { songID == 2 }
    func cancel(songID: Int) {}
    func remove(songID: Int) {}
    func start(_ song: Song, quality: MusicQuality) {}
}

enum MusicQuality: String, CaseIterable, Identifiable {
    case standard
    var id: String { rawValue }
    var title: String { "标准" }
}

enum AppFeatureAvailability {
    static let downloads = true
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

    static func format(_ key: String, _ values: CVarArg...) -> String {
        String(format: string(key), locale: locale, arguments: values)
    }

    static func integer(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    static func joined(_ values: [String], separatorKey: String) -> String {
        values.joined(separator: string(separatorKey))
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

struct ArtworkImage: View {
    let url: URL?
    let cornerRadius: CGFloat
    var body: some View {
        let colors: [Color] = [.teal, .purple, .blue, .orange, .cyan, .indigo, .gray, .mint]
        let symbols = ["moon.stars.fill", "sparkles", "water.waves", "mountain.2.fill", "snowflake", "circle.hexagongrid.fill", "music.note", "leaf.fill"]
        let id = url.flatMap { Int($0.lastPathComponent) } ?? 7
        let index = (id - 1) % colors.count
        return LinearGradient(colors: [colors[index], colors[index].opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                Image(systemName: symbols[index])
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
    }
}

enum MusicRoute {
    case song(Song)
}

struct OpenMusicRouteAction {
    func callAsFunction(_ route: MusicRoute) {}
}

private struct OpenMusicRouteActionKey: EnvironmentKey {
    static let defaultValue = OpenMusicRouteAction()
}

extension EnvironmentValues {
    var openMusicRoute: OpenMusicRouteAction {
        self[OpenMusicRouteActionKey.self]
    }
}

extension View {
    func musicMatchedTransitionSource(for route: MusicRoute) -> some View { self }
}

struct SongCommentsSheet: View {
    let song: Song
    var body: some View { Text(song.name) }
}

struct AddToPlaylistSheet: View {
    let song: Song
    var body: some View { Text(song.name) }
}

struct NeteaseShareMenuContent: View {
    let resource: MusicRoute
    var body: some View { Button("分享") {} }
}
