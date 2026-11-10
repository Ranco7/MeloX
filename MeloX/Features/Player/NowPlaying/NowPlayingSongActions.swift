import SwiftUI

struct NowPlayingSongActions: View {
    @Environment(\.openMusicRoute) private var openMusicRoute
    @Environment(AppSettings.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    @Environment(FloatingLyricsController.self) private var floatingLyrics
    @Environment(ListenTogetherStore.self) private var listenTogether

    let song: Song
    var showsFavoriteButton = true
    var usesCompactMenu = false
    var offersAirPlayMenu = false

    @State private var presentedSheet: NowPlayingSongSheet?
    var body: some View {
        HStack(spacing: 10) {
            if showsFavoriteButton, !song.isPodcastProgram {
                favoriteButton
            }
            songMenu
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .airPlay:
                HStack {
                    Text("AirPlay")
                    Spacer()
                    NowPlayingAirPlayControl().frame(width: 44, height: 44)
                }
                .padding(24)
                .presentationDetents([.height(160)])
                .presentationDragIndicator(.visible)
            case .addToPlaylist(let selectedSong):
                AddToPlaylistSheet(song: selectedSong)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case .comments(let selectedSong):
                SongCommentsSheet(song: selectedSong)
            case .songWiki(let selectedSong):
                SongWikiSheet(song: selectedSong)
            case .listenTogether:
                ListenTogetherView()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case .sleepTimer:
                PlaybackSleepTimerSheet()
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            case .beatNetDebug:
                BeatNetDebugSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
    private var favoriteButton: some View {
        Button {
            library.toggle(song: song)
        } label: {
            Image(
                systemName: library.contains(song: song)
                    ? "star.fill"
                    : "star"
            )
            .font(.title3.weight(.medium))
            .frame(width: 44, height: 44)
            .background(.white.opacity(0.13), in: .circle)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            library.contains(song: song)
                ? L10n.string("ui.common.unfavorite")
                : L10n.string("ui.common.favorite")
        )
    }
    private var songMenu: some View {
        Menu {
            lyricsSourceMenu

            if offersAirPlayMenu {
                Button { presentedSheet = .airPlay } label: {
                    Label("AirPlay", systemImage: "airplay.audio")
                }
            }

            Button {
                floatingLyrics.toggle()
            } label: {
                Label(
                    L10n.string(floatingLyrics.isActive ? "ui.floating_lyrics.close" : "ui.floating_lyrics.open"),
                    systemImage: floatingLyrics.isActive ? "pip.exit" : "pip.enter"
                )
            }
            .disabled(!floatingLyrics.isActive && !floatingLyrics.isPossible)

            Divider()
            Button {
                presentedSheet = .sleepTimer
            } label: {
                Label(
                    player.sleepTimer.isActive
                        ? L10n.string("ui.sleep_timer.active")
                        : L10n.string("ui.sleep_timer.title"),
                    systemImage: "timer"
                )
            }

            Divider()
            if let podcast = song.podcastMetadata {
                Button {
                    player.addToPlaybackQueue(song)
                } label: {
                    Label(
                        "ui.player.add_to_queue",
                        systemImage: "text.badge.plus"
                    )
                }
                if settings.isContentFeatureEnabled(.podcasts) {
                    Button {
                        openMusicRoute(
                            .podcast(podcast.podcastSummary)
                        )
                    } label: {
                        Label(
                            L10n.format("ui.podcasts.go_to", podcast.radioName),
                            systemImage: "mic"
                        )
                    }
                }
            } else {
                ControlGroup {
                    Button {
                        presentedSheet = .addToPlaylist(song)
                    } label: {
                        Label(
                            "ui.playlists.add_to",
                            systemImage: "plus.circle"
                        )
                    }
                    Button {
                        library.toggle(song: song)
                    } label: {
                        Label(
                            library.contains(song: song)
                                ? L10n.string("ui.common.unfavorite")
                                : L10n.string("ui.common.favorite"),
                            systemImage: library.contains(song: song)
                                ? "star.fill"
                                : "star"
                        )
                    }
                    Menu {
                        NeteaseShareMenuContent(resource: .song(song))
                    } label: {
                        Label("ui.common.share", systemImage: "square.and.arrow.up")
                    }
                }
                Button {
                    presentedSheet = .comments(song)
                } label: {
                    Label(
                        "ui.comments.view",
                        systemImage: "bubble.left.and.bubble.right"
                    )
                }
                Button {
                    presentedSheet = .songWiki(song)
                } label: {
                    Label(
                        "ui.song.wiki.title",
                        systemImage: "book.pages"
                    )
                }
                Button {
                    presentedSheet = .listenTogether
                } label: {
                    Label(
                        listenTogether.isInRoom
                            ? L10n.string("ui.listen_together.room")
                            : L10n.string("ui.listen_together.start"),
                        systemImage: "person.2.wave.2"
                    )
                }

                Divider()
                Button {
                    player.addToPlaybackQueue(song)
                } label: {
                    Label(
                        "ui.player.add_to_queue",
                        systemImage: "text.badge.plus"
                    )
                }

                Divider()
                if let album = song.album {
                    Button {
                        openMusicRoute(.album(album))
                    } label: {
                        Label(
                            L10n.format("ui.album.go_to", album.name),
                            systemImage: "music.note.list"
                        )
                    }
                }
                if let artist = song.artists.first, song.artists.count == 1 {
                    Button {
                        openMusicRoute(.artist(artist.id))
                    } label: {
                        Label(
                            L10n.format("ui.artist.go_to", artist.name),
                            systemImage: "music.microphone"
                        )
                    }
                } else if !song.artists.isEmpty {
                    Menu {
                        ForEach(song.artists) { artist in
                            Button {
                                openMusicRoute(.artist(artist.id))
                            } label: {
                                Text(artist.name)
                            }
                        }
                    } label: {
                        Label("ui.artist.go_to_generic", systemImage: "music.microphone")
                    }
                }
                if settings.beatNetDebugEnabled {
                    Divider()
                    Button {
                        presentedSheet = .beatNetDebug
                    } label: {
                        Label(
                            "ui.beatnet.debug.title",
                            systemImage: "waveform.path.ecg"
                        )
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3.weight(.semibold))
                .foregroundStyle(usesCompactMenu ? Color.primary : .white)
                .frame(width: 44, height: 44)
                .background(usesCompactMenu ? Color.clear : .white.opacity(0.15), in: .circle)
                .contentShape(.circle)
        }
        // Menu item icons follow the app's red tint in both the full player
        // and the mini player; the label keeps its own colour above.
        .tint(.red)
        .menuOrder(.fixed)
        .accessibilityLabel("ui.common.more")
    }

    private var lyricsSourceMenu: some View {
        Menu {
            Picker(
                "ui.settings.lyrics.content.default_source",
                selection: Binding(
                    get: { settings.lyricsSourcePreference },
                    set: { settings.lyricsSourcePreference = $0 }
                )
            ) {
                ForEach(LyricSourcePreference.allCases) { preference in
                    Text(preference.title).tag(preference)
                }
            }
        } label: {
            Label(
                "ui.settings.lyrics.content.default_source",
                systemImage: "text.quote"
            )
        }
        .accessibilityValue(settings.lyricsSourcePreference.title)
    }
}
private enum NowPlayingSongSheet: Identifiable {
    case airPlay
    case addToPlaylist(Song)
    case comments(Song)
    case songWiki(Song)
    case listenTogether
    case sleepTimer
    case beatNetDebug
    var id: String {
        switch self {
        case .airPlay: "airPlay"
        case .addToPlaylist(let song):
            "add-to-playlist-\(song.id)"
        case .comments(let song):
            "comments-\(song.id)"
        case .songWiki(let song):
            "song-wiki-\(song.id)"
        case .listenTogether:
            "listen-together"
        case .sleepTimer:
            "sleep-timer"
        case .beatNetDebug:
            "beatnet-debug"
        }
    }
}
