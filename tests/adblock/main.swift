import Foundation
import WebKit
let rules = try JSONSerialization.jsonObject(with: Data(AdBlockRules.rules.utf8)) as! [[String: Any]]
func blocked(_ url: String, on host: String = "music.youtube.com", type: String = "image") -> Bool {
 rules.contains { rule in
  let trigger = rule["trigger"] as! [String: Any]
  guard (trigger["if-domain"] as! [String]).contains(host),
        (trigger["resource-type"] as! [String]).contains(type) else { return false }
  let regex = try! NSRegularExpression(pattern: trigger["url-filter"] as! String, options: .caseInsensitive)
  return regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil
 }
}
func check(_ valid: Bool, _ message: String) { if !valid { fatalError(message) } }
check(blocked("https://googleads.g.doubleclick.net/pagead/ads"), "nested ad domain")
check(blocked("https://pagead2.googlesyndication.com/pagead/js/ads.js"), "syndication script")
check(blocked("https://www.youtube.com/pagead/adview"), "first-party ad path")
check(blocked("https://music.youtube.com/api/stats/ads?x=1"), "ad telemetry path")
check(!blocked("https://rr1---sn.googlevideo.com/videoplayback?id=example"), "music stream must remain allowed")
check(!blocked("https://music.youtube.com/youtubei/v1/player"), "player API must remain allowed")
check(!blocked("https://accounts.google.com/ServiceLogin"), "authentication must remain allowed")
check(!blocked("https://doubleclick.net.evil.example/a"), "anchor domain boundary")
check(!blocked("https://googleads.g.doubleclick.net/pagead/ads", on: "accounts.google.com"), "scope excludes auth documents")
for type in ["script", "raw", "media", "document"] {
 check(!blocked("https://googleads.g.doubleclick.net/pagead/ads", type: type), "ad bootstrap must remain allowed: \(type)")
 check(!blocked("https://music.youtube.com/api/stats/ads?x=1", type: type), "ad telemetry must remain allowed: \(type)")
}
print("17 ad-block scope/playback checks passed")
let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ytm-rule-test-" + UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let store = WKContentRuleListStore(url: directory)!
store.compileContentRuleList(forIdentifier: "ytm.test.rules", encodedContentRuleList: AdBlockRules.rules) { list, error in
 guard list != nil, error == nil else { print("WebKit compilation failed: \(String(describing: error))"); exit(1) }
 print("Actual WebKit rule compilation passed"); exit(0)
}
DispatchQueue.main.asyncAfter(deadline: .now()+25) { print("WebKit compilation timed out"); exit(2) }
RunLoop.main.run()
