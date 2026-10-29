import Foundation

/// Explicit bounded diagnostic of only the configured dictation button.
/// No controller, audio capture, shortcut output, or other-key logging.
enum DictationButtonProbe {
    static func run(to url:URL,duration:TimeInterval=20)throws {
        let config=try ConfigurationStore().loadCurrentRemote()
        guard let usage=config.bindings.first(where:{$0.action == .dictate && $0.usage != nil})?.usage else { throw JustVibeRemoteError.message("Learn the dictation button before checking its timing.") }
        let input=RemoteInput(),start=ProcessInfo.processInfo.systemUptime
        var raw=[[String:Any]](),edges=[[String:Any]]()
        func event(_ down:Bool,_ lag:Double?)->[String:Any] {
            var result:[String:Any]=["down":down,"atMs":(ProcessInfo.processInfo.systemUptime-start)*1000]
            if let lag { result["deliveryMs"]=lag };return result
        }
        func persist(_ phase:String)throws {
            let report:[String:Any]=["phase":phase,"durationSeconds":duration,"rawButtonValues":raw,"deliveredEdges":edges]
            try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:url,options:.atomic)
        }
        input.onButtonValue={ source,down,lag in guard source==usage,raw.count<32 else{return};raw.append(event(down,lag)) }
        input.onDeliveredEdge={ source,down,lag in guard source==usage,edges.count<32 else{return};edges.append(event(down,lag)) }
        try input.start(config.profile);defer { input.stop() }
        try persist("ready")
        let end=Date().addingTimeInterval(duration)
        while Date()<end { RunLoop.main.run(until:min(end,Date().addingTimeInterval(0.05))) }
        try persist("complete")
    }
}
