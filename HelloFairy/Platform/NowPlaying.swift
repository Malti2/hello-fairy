import Foundation
import MediaPlayer
import UIKit

/// liest den laufenden titel der Apple-Music-app (Titel + Cover) und meldet aenderungen
@MainActor
final class NowPlayingWatcher {
    typealias Handler = (UIImage?, String?) -> Void

    private let player = MPMusicPlayerController.systemMusicPlayer
    private var observers: [NSObjectProtocol] = []
    private var handler: Handler?
    private(set) var denied = false

    func start(_ handler: @escaping Handler) async {
        self.handler = handler
        let status = await MPMediaLibrary.requestAuthorization()
        guard status == .authorized else {
            denied = true
            return
        }
        player.beginGeneratingPlaybackNotifications()
        let nc = NotificationCenter.default
        for name in [Notification.Name.MPMusicPlayerControllerNowPlayingItemDidChange,
                     Notification.Name.MPMusicPlayerControllerPlaybackStateDidChange] {
            observers.append(nc.addObserver(forName: name, object: player, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            })
        }
        update()
    }

    func stop() {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
        player.endGeneratingPlaybackNotifications()
        handler = nil
    }

    private func update() {
        let playing = player.playbackState == .playing || player.playbackState == .interrupted
        guard playing, let item = player.nowPlayingItem else {
            handler?(nil, nil)
            return
        }
        let art = item.artwork?.image(at: CGSize(width: 240, height: 240))
        let title = [item.title, item.artist].compactMap { $0 }.joined(separator: " - ")
        handler?(art, title.isEmpty ? nil : title)
    }
}
