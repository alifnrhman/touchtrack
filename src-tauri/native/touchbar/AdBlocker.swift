import Foundation
import WebKit

// Block ad images only. Blocking ad scripts/telemetry can stall authenticated
// player initialization; video ads are handled by the isolated playback script.
enum AdBlockRules {
    static let identifier = "app.ytm.touchbar.ads.v3"
    static let rules = #"""
    [
      {
        "trigger": {
          "url-filter": "^https?://([a-z0-9-]+\\.)*doubleclick\\.net(:[0-9]+)?/",
          "resource-type": ["image"],
          "if-domain": [
            "music.youtube.com"
          ]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([a-z0-9-]+\\.)*googlesyndication\\.com(:[0-9]+)?/",
          "resource-type": ["image"],
          "if-domain": [
            "music.youtube.com"
          ]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([a-z0-9-]+\\.)*googleadservices\\.com(:[0-9]+)?/",
          "resource-type": ["image"],
          "if-domain": [
            "music.youtube.com"
          ]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([a-z0-9-]+\\.)*youtube\\.com/pagead/",
          "resource-type": ["image"],
          "if-domain": [
            "music.youtube.com"
          ]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([a-z0-9-]+\\.)*youtube\\.com/api/stats/ads[/?]",
          "resource-type": ["image"],
          "if-domain": [
            "music.youtube.com"
          ]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([a-z0-9-]+\\.)*youtube\\.com/api/stats/ads$",
          "resource-type": ["image"],
          "if-domain": [
            "music.youtube.com"
          ]
        },
        "action": {
          "type": "block"
        }
      }
    ]
    """#
}

// Runs in an isolated world: only DOM access is needed, not YouTube's page globals.
enum AdPlaybackScript {
    static let source = #"""
    (() => {
      if (location.origin !== 'https://music.youtube.com' || window.top !== window) return;
      const advanceAd = () => {
        const player = document.querySelector('#movie_player');
        if (!player || !player.classList.contains('ad-showing')) return;
        const skip = player.querySelector('.ytp-ad-skip-button-modern, .ytp-ad-skip-button, .ytp-skip-ad-button');
        if (skip && !skip.disabled && skip.getAttribute('aria-disabled') !== 'true') { skip.click(); return; }
        // Never seek a song, a live stream, or media whose duration is unknown.
        const media = player.querySelector('video, audio');
        if (media && !media.paused && Number.isFinite(media.duration) && media.duration > 0 && media.currentTime < media.duration) {
          try { media.currentTime = media.duration; } catch (_) {}
        }
      };
      // Polling also catches ads when the window is hidden and the DOM is quiet.
      window.setInterval(advanceAd, 500);
      document.addEventListener('loadedmetadata', advanceAd, true);
      document.addEventListener('playing', advanceAd, true);
    })();
    """#
}

@MainActor final class AdBlocker {
    private weak var web: WKWebView?
    private var compiled: WKContentRuleList?
    private var generation = 0
    private(set) var status = "Not initialized"
    var enabled: Bool { UserDefaults.standard.object(forKey: "adBlockEnabled") as? Bool ?? true }
    func attach(_ web: WKWebView, completion: @escaping () -> Void) {
        self.web = web; apply(completion: completion)
    }
    @discardableResult func toggle() -> Bool {
        let value = !enabled; UserDefaults.standard.set(value, forKey: "adBlockEnabled")
        apply { [weak self] in
            guard let web = self?.web, web.url?.scheme == "https", web.url?.host == "music.youtube.com" else { return }
            web.reload()
        }
        return value
    }
    private func apply(completion: @escaping () -> Void) {
        generation += 1; let token = generation
        updatePlaybackScript()
        if let compiled { web?.configuration.userContentController.remove(compiled) }
        guard enabled else { status = "Off"; completion(); return }
        if let compiled { web?.configuration.userContentController.add(compiled); status = "On — ad images + player ad skipping"; completion(); return }
        status = "Preparing rules…"
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: AdBlockRules.identifier, encodedContentRuleList: AdBlockRules.rules) { [weak self] list, error in
            guard let self else { completion(); return }
            guard token == self.generation else { completion(); return }
            if let list, error == nil {
                self.compiled = list
                self.web?.configuration.userContentController.add(list)
                self.status = "On — ad images + player ad skipping"
            } else { self.status = "Rules failed to compile — not blocking" }
            completion()
        }
    }
    private func updatePlaybackScript() {
        guard let content = web?.configuration.userContentController else { return }
        // WebKit has no remove-single-user-script API. Preserve the player bridge
        // and any other scripts when replacing only our script for the next reload.
        let others = content.userScripts.filter { $0.source != AdPlaybackScript.source }
        content.removeAllUserScripts()
        others.forEach { content.addUserScript($0) }
        if enabled {
            content.addUserScript(WKUserScript(source: AdPlaybackScript.source,
                injectionTime: .atDocumentStart, forMainFrameOnly: true,
                in: WKContentWorld.world(name: "ytm.adblock")))
        }
    }
    func stop() {
        generation += 1
        if let compiled { web?.configuration.userContentController.remove(compiled) }
        web = nil
    }
}
