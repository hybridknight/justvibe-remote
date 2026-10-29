import Foundation

/// User settings belong to the device/app pair, not to the selected editor view.
struct AppMapping: Codable {
    var bindings: [Binding]
    var shortcut: String
    var shortcutConfirmed: Bool
    var voiceMode: String
    var targetAppPath: String
    var dictationTested: Bool
    init(_ config: Configuration) {
        bindings = config.bindings; shortcut = config.shortcut; shortcutConfirmed = config.shortcutConfirmed
        voiceMode = config.voiceMode; targetAppPath = config.targetAppPath; dictationTested = config.dictationTested
    }
    func apply(to config: Configuration) -> Configuration {
        var next = config
        next.bindings = bindings; next.shortcut = shortcut; next.shortcutConfirmed = shortcutConfirmed
        next.voiceMode = voiceMode; next.targetAppPath = targetAppPath; next.dictationTested = dictationTested
        return next
    }
}
struct ForegroundApp {
    var bundleID: String = ""
    var name: String = ""
    var path: String = ""
    var instance: String = ""
}
enum AppRouting {
    /// Shared controls operate on the current foreground app; they never launch
    /// an app or guess an app-specific dictation shortcut.
    static let sharedActions=AppPlugin(adapter:"shortcuts",targets:[:],actions:[
        "send":PluginAction(operation:"tap-shortcut",shortcuts:["macos":"RETURN"]),
        "backspace":PluginAction(operation:"tap-shortcut",shortcuts:["macos":"BACKSPACE"]),
        "escape":PluginAction(operation:"tap-shortcut",shortcuts:["macos":"ESC"]),
    ])
    static func key(_ deviceID: String, _ appID: String) -> String { deviceID + "|" + appID }
    static func outputPlugin(_ route:Configuration,apps:[PluginManifest])->AppPlugin? {
        guard let plugin=route.appPluginID == Configuration.noSpecificAppID ? sharedActions:apps.first(where:{$0.id == route.appPluginID})?.app else { return nil }
        guard route.usesSystemDictation else { return plugin }
        var actions=plugin.actions
        actions["dictate"]=PluginAction(operation:"toggle-shortcut",shortcuts:["macos":route.shortcut])
        return AppPlugin(adapter:plugin.adapter,targets:plugin.targets,actions:actions)
    }
    /// Exact path wins, then bundle ID, then name. Equal matches are ambiguous and do nothing.
    static func resolve(_ config: Configuration, apps: [PluginManifest], foreground: ForegroundApp?, platform: String = "macos") -> Configuration? {
        if !config.followActiveApp {
            let base=config.appPluginID == Configuration.noSpecificAppID ? sharedRoute(config,foreground:foreground):config
            return systemRoute(config,base:base,apps:apps,foreground:foreground,platform:platform)
        }
        guard let foreground else { return nil }
        var matches: [(Int, Configuration)] = []
        for plugin in apps {
            let key = key(config.devicePluginID, plugin.id)
            guard plugin.id == config.appPluginID || config.appMappings[key] != nil || config.bindingSets[key] != nil else { continue }
            var candidate = config
            candidate.appPluginID = plugin.id
            if plugin.id != config.appPluginID {
                if let saved = config.appMappings[key] { candidate = saved.apply(to: candidate) }
                else {
                    candidate.bindings = config.bindingSets[key]!
                    candidate.shortcut = (try? plugin.app?.shortcut(.dictate)) ?? ""
                    candidate.shortcutConfirmed = false; candidate.targetAppPath = ""; candidate.dictationTested = false
                }
            }
            candidate.bindings = candidate.bindings.map { binding in
                var result = binding
                if plugin.app?.supports(result.action) != true { result.action = .native }
                return result
            }
            guard let target = plugin.app?.targets[platform] else { continue }
            var score = 0
            if !candidate.targetAppPath.isEmpty {
                if !foreground.path.isEmpty && URL(fileURLWithPath: candidate.targetAppPath).standardizedFileURL.path == URL(fileURLWithPath: foreground.path).standardizedFileURL.path { score = 3 }
            } else if !foreground.bundleID.isEmpty && target.bundleIds.contains(foreground.bundleID) { score = 2 }
            else if !foreground.name.isEmpty && target.names.contains(foreground.name) { score = 1 }
            if score > 0 { matches.append((score, candidate)) }
        }
        guard let best = matches.map({ $0.0 }).max() else { return systemRoute(config,base:sharedRoute(config,foreground:foreground),apps:apps,foreground:foreground,platform:platform) }
        let winners = matches.filter { $0.0 == best }
        // Ambiguous app identities remain inactive, including universal dictation.
        return winners.count == 1 ? systemRoute(config,base:winners[0].1,apps:apps,foreground:foreground,platform:platform):nil
    }
    private static func systemRoute(_ config:Configuration,base:Configuration?,apps:[PluginManifest],foreground:ForegroundApp?,platform:String)->Configuration? {
        guard platform == "macos",let setting=config.systemDictation[config.devicePluginID],setting.enabled,
              (try? setting.validate()) != nil,let foreground else { return base }
        // Learned hardware identity is shared across app profiles. Never guess a usage.
        guard let physical=config.bindings.first(where:{$0.controlID == setting.controlID}),let usage=physical.usage else { return base }
        var route=base
        if let candidate=route,candidate.appPluginID != Configuration.noSpecificAppID {
            let target=apps.first(where:{$0.id == candidate.appPluginID})?.app?.targets[platform]
            let matches = !candidate.targetAppPath.isEmpty
                ? URL(fileURLWithPath:candidate.targetAppPath).standardizedFileURL.path == URL(fileURLWithPath:foreground.path).standardizedFileURL.path
                : (target?.bundleIds.contains(foreground.bundleID) == true || target?.names.contains(foreground.name) == true)
            if !matches { route=sharedRoute(config,foreground:foreground) }
        }
        if setting.mode == .fallback,let candidate=route,
           candidate.appPluginID != Configuration.noSpecificAppID,candidate.shortcutConfirmed,!candidate.shortcut.isEmpty,
           candidate.bindings.contains(where:{$0.controlID == setting.controlID && $0.action == .dictate}),
           outputPlugin(candidate,apps:apps)?.supports(.dictate) == true { return candidate }
        if route == nil {
            var shared=config;shared.appPluginID=Configuration.noSpecificAppID
            shared.bindings=shared.bindings.map { var item=$0;item.action = .native;return item }
            route=shared
        }
        var result=route!
        guard let index=result.bindings.firstIndex(where:{$0.controlID == setting.controlID}) else { return base }
        result.bindings[index].usage=usage;result.bindings[index].action = .dictate
        result.shortcut=setting.shortcutDescription;result.shortcutConfirmed=setting.confirmed;result.voiceMode="toggle"
        result.targetAppPath="";result.dictationTested=false
        result.usesSystemDictation=true;result.systemDictationTargetPID=Int32(foreground.instance)
        return result
    }
    /// App profiles take precedence over shared controls. Selecting the shared
    /// profile in the editor does not disable foreground-app detection.
    private static func sharedRoute(_ config:Configuration,foreground:ForegroundApp?)->Configuration? {
        guard foreground != nil else { return nil }
        var shared=config
        let sharedKey=key(config.devicePluginID,Configuration.noSpecificAppID)
        if config.appPluginID != Configuration.noSpecificAppID {
            if let saved=config.appMappings[sharedKey] { shared=saved.apply(to:shared) }
            else if let bindings=config.bindingSets[sharedKey] { shared.bindings=bindings }
            else { return nil }
        }
        shared.appPluginID=Configuration.noSpecificAppID
        shared.targetAppPath="";shared.shortcut="";shared.shortcutConfirmed=false;shared.dictationTested=false
        shared.bindings=shared.bindings.map { binding in
            var item=binding
            if !sharedActions.supports(item.action) { item.action = .native }
            return item
        }
        return shared
    }

}
