//
//  Copyright (c) SRG SSR. All rights reserved.
//
//  License information is available from the LICENSE file.
//

import AVFoundation
import os

private let kContentKeySession = AVContentKeySession(keySystem: .fairPlayStreaming)
private let kContentKeySessionQueue = DispatchQueue(label: "ch.srgssr.player.content_key_session")

enum Resource {
    case simple(url: URL, options: [String : Any])
    case custom(url: URL, delegate: AVAssetResourceLoaderDelegate)
    case encrypted(url: URL, delegate: AVContentKeySessionDelegate)

    private static let logger = Logger(category: "Resource")

    private func asset(for url: URL, options: [String : Any], with configuration: PlayerConfiguration) -> AVURLAsset {
        var options = options ?? [:]
        options[AVURLAssetAllowsConstrainedNetworkAccessKey] = configuration.allowsConstrainedNetworkAccess
        return AVURLAsset(url: url, options: options)
    }

    func playerItem(configuration: PlayerConfiguration, limits: PlayerLimits) -> AVPlayerItem {
        let item = unlimitedPlayerItem(configuration: configuration)
        limits.apply(to: item)
        return item
    }

    private func unlimitedPlayerItem(configuration: PlayerConfiguration) -> AVPlayerItem {
        switch self {
        case let .simple(url: url, options: options):
            return AVPlayerItem(asset: asset(for: url, options: options, with: configuration))
        case let .custom(url: url, delegate: delegate):
            return ResourceLoadedPlayerItem(
                asset: asset(for: url,
                             options: [:],
                             with: configuration),
                resourceLoaderDelegate: delegate
            )
        case let .encrypted(url: url, delegate: delegate):
#if targetEnvironment(simulator)
            Self.logger.error("FairPlay-encrypted assets cannot be played in the simulator")
            return AVPlayerItem(asset: asset(for: url, options: [:], with: configuration))
#else
            let asset = asset(for: url, options: [:], with: configuration)
            kContentKeySession.setDelegate(delegate, queue: kContentKeySessionQueue)
            kContentKeySession.addContentKeyRecipient(asset)
            kContentKeySession.processContentKeyRequest(withIdentifier: nil, initializationData: nil)
            return AVPlayerItem(asset: asset)
#endif
        }
    }
}

extension Resource: PlaybackResource {
    func contains(url: URL) -> Bool {
        switch self {
        case let .custom(url: customUrl, _) where customUrl == url:
            true
        default:
            false
        }
    }
}

extension Resource {
    static let loading = Self.custom(url: .loading, delegate: LoadingResourceLoaderDelegate())

    static func failing(error: Error) -> Self {
        .custom(url: .failing, delegate: FailedResourceLoaderDelegate(error: error))
    }
}

extension Resource: Equatable {
    static func == (lhs: Resource, rhs: Resource) -> Bool {
        switch (lhs, rhs) {
        case let (.simple(url: lhsUrl, _), .simple(url: rhsUrl, _)):
            return lhsUrl == rhsUrl
        case let (.custom(url: lhsUrl, delegate: lhsDelegate), .custom(url: rhsUrl, delegate: rhsDelegate)):
            return lhsUrl == rhsUrl && lhsDelegate === rhsDelegate
        case let (.encrypted(url: lhsUrl, delegate: lhsDelegate), .encrypted(url: rhsUrl, delegate: rhsDelegate)):
            return lhsUrl == rhsUrl && lhsDelegate === rhsDelegate
        default:
            return false
        }
    }
}
