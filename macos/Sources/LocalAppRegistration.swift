import Foundation

/// User-added apps use the same declarative shortcut contract as other plugins.
struct LocalAppRegistration {
    let url:URL
    let bundleID:String
    let name:String

    init(url:URL) throws {
        let resolved=url.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.isFileURL, resolved.pathExtension.lowercased() == "app",
              let bundle=Bundle(url:resolved),
              bundle.object(forInfoDictionaryKey:"CFBundlePackageType") as? String == "APPL",
              let identity=bundle.bundleIdentifier, !identity.isEmpty else {
            throw JustVibeRemoteError.message("Choose a Mac application (.app) from Finder or your Applications folder.")
        }
        self.url=resolved;bundleID=identity
        name=(bundle.object(forInfoDictionaryKey:"CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey:"CFBundleName") as? String)
            ?? resolved.deletingPathExtension().lastPathComponent
    }

    func manifest(dictationShortcut:String?) throws -> PluginManifest {
        var actions:[String:PluginAction]=[
            "focus":PluginAction(operation:"focus",shortcuts:nil),
            "send":PluginAction(operation:"tap-shortcut",shortcuts:["macos":"RETURN"]),
            "backspace":PluginAction(operation:"tap-shortcut",shortcuts:["macos":"BACKSPACE"]),
            "escape":PluginAction(operation:"tap-shortcut",shortcuts:["macos":"ESC"]),
        ]
        if let shortcut=dictationShortcut {
            let value=shortcut.trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
            try PluginManifest.validateShortcut(value,platform:"macos")
            actions["dictate"]=PluginAction(operation:"hold-shortcut",shortcuts:["macos":value])
        }
        let manifest=PluginManifest(schemaVersion:1,apiVersion:1,id:"local.justviberemote.app." + UUID().uuidString.lowercased(),version:"1.0.0",name:name,author:"Added on this Mac",kind:"app",platforms:["macos"],capabilities:["target.focus","input.shortcuts"],device:nil,
            app:AppPlugin(adapter:"shortcuts",targets:["macos":PluginTarget(bundleIds:[bundleID],names:[])],actions:actions))
        try manifest.validate()
        return manifest
    }

    static func selecting(_ plugin:PluginManifest,url:URL,config:Configuration,catalog:PluginCatalog) throws -> Configuration {
        let configured=config.appPluginID == plugin.id || config.appMappings[AppRouting.key(config.devicePluginID,plugin.id)] != nil || config.bindingSets[AppRouting.key(config.devicePluginID,plugin.id)] != nil
        var next=try PluginSelection.select(config,catalog:catalog,deviceID:config.devicePluginID,appID:plugin.id)
        next.targetAppPath=url.path
        if plugin.id.hasPrefix("local.justviberemote.app."),!configured {
            next.bindings=next.bindings.map { binding in var item=binding;item.action = .native;return item }
        }
        return next
    }

    static func install(_ manifest:PluginManifest,in directory:URL) throws {
        try manifest.validate()
        let fm=FileManager.default
        try fm.createDirectory(at:directory,withIntermediateDirectories:true)
        let staging=directory.appendingPathComponent(".adding-" + UUID().uuidString)
        try fm.createDirectory(at:staging,withIntermediateDirectories:false)
        defer { try? fm.removeItem(at:staging) }
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(manifest).write(to:staging.appendingPathComponent("plugin.json"),options:.atomic)
        // Moving a complete folder publishes it without replacing an existing package.
        try fm.moveItem(at:staging,to:directory.appendingPathComponent(manifest.id))
    }
}
