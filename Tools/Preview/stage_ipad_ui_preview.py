from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[2]


def replace_once(path, old, new):
    target = root / path
    source = target.read_text()
    if source.count(old) != 1:
        raise ValueError(f"Expected one matching fixture insertion point in {path}")
    target.write_text(source.replace(old, new))


shutil.copyfile(
    Path(__file__).with_name("IPadUIPreviewFixture.swift"),
    root / "MeloX/App/IPadUIPreviewFixture.swift",
)
replace_once(
    "MeloX/App/MeloXApp.swift",
    "        let settings = AppSettings()",
    """        let settings = AppSettings()
        if IPadUIPreviewFixture.enabled {
            IPadUIPreviewFixture.prepare(settings)
        }""",
)
replace_once(
    "MeloX/App/MeloXApp.swift",
    "ContentView(initialTab: settings.launchTab)",
    "ContentView(initialTab: IPadUIPreviewFixture.enabled ? .home : settings.launchTab)",
)
replace_once(
    "MeloX/App/ContentView.swift",
    "        case .home:\n            HomeView()",
    """        case .home:
            if IPadUIPreviewFixture.enabled {
                IPadUIPreviewFixture.screen
            } else {
                HomeView()
            }""",
)
replace_once(
    "MeloX/Core/Playback/Session/PlayerStore.swift",
    """        applyVolumeControlMode()

        await loadCurrentSong(
            autoplay: false,
            startAt: progress
        )""",
    """        applyVolumeControlMode()

        if IPadUIPreviewFixture.enabled { return }
        await loadCurrentSong(
            autoplay: false,
            startAt: progress
        )""",
)
replace_once(
    "MeloX/Core/Networking/NeteaseAPI+UserPlayRecords.swift",
    '        let path = "/api/v1/play/record"',
    '''        if IPadUIPreviewFixture.enabled {
            return IPadUIPreviewFixture.records(for: period)
        }

        let path = "/api/v1/play/record"''',
)
replace_once(
    "MeloX/Features/Account/UserListeningRankView.swift",
    "    @State private var selectedPeriod = UserPlayRecordPeriod.week",
    "    @State private var selectedPeriod = IPadUIPreviewFixture.initialPeriod",
)
replace_once(
    "MeloX/Features/Search/SearchDiscoveryView.swift",
    "            guard recommendations.isEmpty else { return }",
    """            if IPadUIPreviewFixture.enabled {
                phase = .loaded
                return
            }
            guard recommendations.isEmpty else { return }""",
)
replace_once(
    "MeloX/Shared/Media/ArtworkImage.swift",
    """            LazyImage(
                request: imageRequest(for: proxy.size),
                transaction: Transaction(animation: imageLoadAnimation)
            ) { state in
                content(image: state.image, hasError: state.error != nil)
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height
                    )
            }
            .onDisappear(.lowerPriority)""",
    """            if let url, url.scheme == "melox-preview" {
                IPadUIPreviewFixture.artwork(for: url)
            } else {
                LazyImage(
                    request: imageRequest(for: proxy.size),
                    transaction: Transaction(animation: imageLoadAnimation)
                ) { state in
                    content(image: state.image, hasError: state.error != nil)
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height
                        )
                }
                .onDisappear(.lowerPriority)
            }""",
)
