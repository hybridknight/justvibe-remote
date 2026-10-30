using System.Text.Json;
using JustVibeRemote.Core;

int passed = 0;
void Check(bool value, string label) { if (!value) throw new Exception("FAIL: " + label); passed++; }
void Throws(Action action, string label) { try { action(); } catch { passed++; return; } throw new Exception("FAIL: " + label); }
var remoteMic=new MicrophonePreference("remote.uid","Remote USB mic",true);
Check(MicrophonePolicy.Issue(null,[],[])==null,"legacy dictation unchanged before microphone setup");
Check(MicrophonePolicy.Issue(remoteMic,["remote.uid"],["remote.uid"])==null,"selected present default mic passes");
Check(MicrophonePolicy.Issue(remoteMic,[],["remote.uid"])!=null,"disconnected selected mic blocks dictation");
Check(MicrophonePolicy.Issue(remoteMic,["remote.uid"],["built.in"])!=null,"another default mic blocks dictation");
Check(MicrophonePolicy.Issue(remoteMic,["remote.uid"],[])!=null,"unknown system input fails closed");
Check(MicrophonePolicy.Issue(remoteMic,["remote.uid"],["remote.uid","other"])!=null,"different communications input fails closed");
Check(MicrophonePolicy.Issue(remoteMic,["remote.uid"],["remote.uid","remote.uid","remote.uid"])==null,"all matching Windows roles pass");
Check(MicrophonePolicy.Issue(new("","",true),[""],[""])!=null,"empty microphone identity cannot pass");
Check(MicrophonePolicy.Issue(new("missing","",false),[],[])==null,"user can disable system-input safeguard");
var clip=new PCMPreview(8000);clip.Append(new byte[8]);Check(clip.Level==0,"silence has no signal");
clip.Append(new byte[]{0,128});Check(clip.Level==1,"full-scale negative sample measured safely");
clip.Append(new byte[]{255,127});Check(clip.Level>0.99&&clip.Level<=1,"positive peak remains in range");
var bounded=new PCMPreview(8000);bounded.Append(new byte[100000]);Check(bounded.Full&&bounded.Count==40000,"local preview capped at five seconds");
bounded.Append(new byte[20]);Check(bounded.Count==40000,"late audio cannot grow a finished clip");
var wave=clip.Wave();Check(System.Text.Encoding.ASCII.GetString(wave,0,4)=="RIFF"&&System.Text.Encoding.ASCII.GetString(wave,8,4)=="WAVE","preview emits WAV container");
Check(wave.Length==44+clip.Count*2&&wave[22]==1&&wave[34]==16,"WAV correct size, mono channels and PCM16");
Check(wave[52]==0&&wave[53]==128&&wave[54]==255&&wave[55]==127,"WAV retains signed PCM in little endian");
var setup = new SetupProgress(false,false,false,true,false,false,false);
Check(setup.Step==SetupStep.InputPermission,"input approval first");
setup=setup with{InputAllowed=true};Check(setup.Step==SetupStep.ShortcutPermission,"shortcut approval before connection");
setup=setup with{ShortcutsAllowed=true};Check(setup.Step==SetupStep.Receiver,"receiver before learning");
setup=setup with{ReceiverConnected=true};Check(setup.Step==SetupStep.Microphone,"physical microphone link required");
setup=setup with{MicrophoneLinked=true};Check(setup.Step==SetupStep.Shortcut,"unverified shortcut requires confirmation");
setup=setup with{ShortcutConfirmed=true};Check(setup.Step==SetupStep.Test,"confirmed shortcut still needs live test");
setup=setup with{TestConfirmed=true};Check(setup.Step==SetupStep.Ready,"explicit test confirmation completes setup");
setup=setup with{ReceiverConnected=false};Check(setup.Step==SetupStep.Receiver,"completed setup detects disconnected receiver");
setup=setup with{ReceiverConnected=true,NeedsDictation=false,MicrophoneLinked=false,ShortcutConfirmed=false,TestConfirmed=false};Check(setup.Step==SetupStep.Ready,"non-dictation app skips voice setup");
var root = args.Length > 0 ? Path.GetFullPath(args[0]) : Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../../"));
var profile = PluginManifest.Decode(File.ReadAllBytes(Path.Combine(root, "plugins/bundled/org.justviberemote.device.xingwei-usb/plugin.json"))).Device!.Profile;
Check(ReceiverDecoder.Matches(@"HID#VID_1915&PID_1025&MI_03#receiver", profile), "exact receiver accepted");
Check(!ReceiverDecoder.Matches(@"HID#VID_1915&PID_10250#receiver", profile), "longer PID rejected");
Check(!ReceiverDecoder.Matches(@"HID#VID_1915&PID_1026#receiver", profile), "other receiver rejected");
Check(!ReceiverDecoder.Matches("keyboard", profile), "ordinary keyboard ignored");
Check(ReceiverDecoder.Matches(@"\\?\HID#{00001124-0000-1000-8000-00805f9b34fb}_VID&00021915_PID&1025#remote", profile), "Bluetooth USB-authority identity accepted");
Check(ReceiverDecoder.Matches(@"HID#remote_VID&00011915_PID&1025#remote", profile), "Bluetooth SIG-authority identity accepted");
Check(!ReceiverDecoder.Matches(@"HID#remote_VID&00031915_PID&1025#remote", profile), "unknown Bluetooth vendor authority rejected");
Check(!ReceiverDecoder.Matches(@"HID#remote_VID&00021915_PID&10250#remote", profile), "longer Bluetooth PID rejected");
Check(!ReceiverDecoder.Matches(@"HID#remote_VID&00021916_PID&1025#remote", profile), "other Bluetooth remote ignored");
Check(!ReceiverDecoder.Matches(@"HID#NOTVID_1915&PID_1025#remote", profile), "identity token must have a boundary");
var visual = PluginManifest.Decode(File.ReadAllBytes(Path.Combine(root,"plugins/bundled/org.justviberemote.device.xingwei-usb/plugin.json"))).Device!.Layout!;
Check(visual.Buttons.Count==18,"photo layout includes all visible front-face controls");
Check(visual.Buttons.All(b=>b.Usage==null),"photo geometry does not invent HID signals");
Check(visual.Buttons.First(b=>b.Id=="top-right").Hint!=null,"unclear photo symbol is documented");
var learned=new Binding("Old microphone label",new Usage(12,0x221),ActionKind.Dictate,"microphone");
var migrated=visual.Bindings([learned]);
Check(migrated[0].Usage==learned.Usage && migrated[0].Name=="Microphone","stable ID survives label changes");
var legacy=new Binding("Spare old control",new Usage(7,0x3D),ActionKind.Escape);
Check(visual.Bindings([learned,legacy]).Contains(legacy),"unmatched legacy bindings remain accessible");
Check(visual.Bindings([learned with{Name="Microphone",ControlID=null}])[0].Usage==learned.Usage,"legacy names migrate to stable IDs");
Throws(()=>visual.Bindings(Enumerable.Range(0,64).Select(i=>new Binding($"Legacy {i}",null,ActionKind.Native))),"overflow never silently drops old controls");
var decoder = new ReceiverDecoder(profile);
var down = decoder.Reports(1, [2, 0x21, 2], 3, 1).ToArray();
Check(down.Length == 1 && down[0] == (new Usage(12, 0x221), true), "consumer press decoded");
Check(!decoder.Reports(1, [2, 0x21, 2], 3, 1).Any(), "duplicate reports ignored");
Check(decoder.Keyboard(2, 0x26, true).Single() == (new Usage(7, 0x52), true), "keyboard interface decoded");
Check(decoder.Reports(1, [2, 0, 0], 3, 1).Single() == (new Usage(12, 0x221), false), "consumer release decoded");
Check(!decoder.Keyboard(2, 0x26, true).Any(), "other interface does not release keyboard");
Check(decoder.Keyboard(2, 0x26, false).Single().Down == false, "keyboard release decoded");
Check(decoder.Reports(1, [2, 0xE9, 0, 2, 0, 0], 3, 2).Count() == 2, "batched reports preserve edges");
Check(!decoder.Reports(1, [2, 0x21], 3, 1).Any(), "truncated report ignored");
Check(!decoder.Reports(1, [8, 0x21, 2], 3, 1).Any(), "vendor report ignored");
Check(!decoder.Reports(1, [2, 0x21, 2], 3, int.MaxValue).Any(), "overflow count rejected");
Check(ReceiverDecoder.FromVirtualKey(0x44) == new Usage(7, 7), "keyboard HID letter mapping");
Check(ReceiverDecoder.FromVirtualKey(0x31) == new Usage(7, 0x1E) && ReceiverDecoder.FromVirtualKey(0x30) == new Usage(7, 0x27), "remote number keys match HID usages");
Check(ReceiverDecoder.FromVirtualKey(0x61) == new Usage(7, 0x59) && ReceiverDecoder.FromVirtualKey(0x60) == new Usage(7, 0x62), "remote keypad keys match HID usages");
Check(ReceiverDecoder.FromVirtualKey(0x7C) == new Usage(7, 0x68) && ReceiverDecoder.FromVirtualKey(0x87) == new Usage(7, 0x73), "extended remote function keys supported");
Check(ReceiverDecoder.FromVirtualKey(0xB3) == new Usage(12, 0xCD) && ReceiverDecoder.FromVirtualKey(0xAD) == new Usage(12, 0xE2), "keyboard media playback and mute normalized to consumer usages");
Check(!new Usage(1, 0x30).IsButton && !new Usage(0xFF01, 0x14).IsButton, "pointer and vendor data not learned");
var descriptorDecoder = new ReceiverDecoder(profile);
Check(descriptorDecoder.Buttons(1, 0, 12, [0xE9, 0xEA]).Count() == 2, "unnumbered descriptor report accepts simultaneous buttons");
Check(!descriptorDecoder.Buttons(1, 9, 12, []).Any(), "unrelated report cannot release held controls");
Check(!descriptorDecoder.Buttons(2, 0, 12, [0xE9]).Any(), "same usage from another interface does not duplicate press");
Check(descriptorDecoder.Buttons(1, 0, 12, []).Single() == (new Usage(12, 0xEA), false), "overlapping usage stays held until its last interface releases");
Check(descriptorDecoder.Buttons(2, 0, 12, []).Single() == (new Usage(12, 0xE9), false), "final interface releases shared usage");
Check(!descriptorDecoder.Buttons(1, 0, 1, [0x30]).Any(), "descriptor mouse axes never become buttons");
Check(!descriptorDecoder.Buttons(1, 0, 0xFF00, [1]).Any(), "descriptor vendor usages ignored");
Check(descriptorDecoder.Buttons(1, 3, 1, [0x81]).Single().Down, "descriptor system power usage accepted");
descriptorDecoder.Clear();
Check(descriptorDecoder.Buttons(1, 3, 1, [0x81]).Single().Down, "disconnect reset allows the next press");

int parseCalls = 0;
using (var reader = new JustVibeRemote.HidReportReader(4, new() { [12] = 8 },
    (ushort page, ushort[] usages, ref uint length, byte[] report) =>
    {
        parseCalls++;
        if (report[3] == 255) return unchecked((int)0xC011000A); // Incompatible ID / parser failure.
        length = report[1];
        if (length > 0) usages[0] = report[2];
        return 0x00110000;
    }))
{
    var parsed = new ReceiverDecoder(profile);
    Check(reader.Read(parsed, 5, [9, 1, 0xE9, 0, 9, 0, 0, 0], 4, 2).SequenceEqual(new[] { (new Usage(12, 0xE9), true), (new Usage(12, 0xE9), false) }), "descriptor-driven batched reports keep press then release order");
    Check(reader.Read(parsed, 5, [0, 1, 0xEA, 0], 4, 1).Single().Down, "descriptor report ID zero supported independently of legacy layout");
    Check(!reader.Read(parsed, 5, [0, 0, 0, 255], 4, 1).Any(), "parser failure emits no release");
    Check(!reader.Read(parsed, 5, [8, 0, 0, 0], 4, 1).Any(), "another report ID does not release a held button");
    Check(reader.Read(parsed, 5, [0, 0, 0, 0], 4, 1).Single() == (new Usage(12, 0xEA), false), "successful empty report releases after parser failure");
    int before = parseCalls;
    Check(!reader.Read(parsed, 5, [9, 1, 0xE9], 3, 1).Any() && !reader.Read(parsed, 5, [9, 1, 0xE9, 0], 4, int.MaxValue).Any() && parseCalls == before, "malformed and overflowing batches never reach native parser");
    reader.Dispose();
    Check(!reader.Read(parsed, 5, [9, 1, 0xE9, 0], 4, 1).Any(), "disposed descriptor reader ignores late reports");
}
var session = new VoiceSession(); var now = DateTimeOffset.UtcNow;
Check(session.DesiredState(true, "toggle") == true, "toggle press starts");
session.Commit(true, now);
Check(session.DesiredState(false, "toggle") == null, "pulse release does not stop toggle");
Check(session.DesiredState(true, "toggle") == false, "second toggle press stops");
Check(session.DesiredState(false, "hold") == false, "hold release stops");
Check(!session.Expired(now.AddSeconds(119)) && session.Expired(now.AddSeconds(120)), "session timeout bounded");
Throws(() => (profile with { VendorId = 0 }).Validate(), "invalid VID rejected");
Throws(() => (profile with { ConsumerUsageOffset = 3 }).Validate(), "invalid report layout rejected");
var temporary = Path.Combine(Path.GetTempPath(), "JustVibeRemoteTests-" + Guid.NewGuid());
try
{
    var store = new ConfigurationStore(Path.Combine(temporary, "settings.json"));
    var config = store.Load(new Configuration { Profile = profile, Shortcut = "RALT" });
    Check(!config.ShortcutConfirmed && config.Bindings[0].Usage == null, "safe first-run state");
    Check(!config.AutoConnect&&!config.DictationTested,"connection and test require consent");
    store.Save(config);
    var oldObject=System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(store.Path))!.AsObject();
    oldObject.Remove("microphones");oldObject.Remove("followActiveApp");oldObject.Remove("appMappings");oldObject.Remove("autoConnect");oldObject.Remove("dictationTested");File.WriteAllText(store.Path,oldObject.ToJsonString());
    Check(!store.Load().AutoConnect&&!store.Load().DictationTested,"old settings retain safe setup defaults");
    Check(!store.Load().FollowActiveApp&&store.Load().AppMappings.Count==0,"old settings preserve manual routing");
    Check(config.Microphones.Count==0,"old settings do not guess an audio input");
    config=config with{Microphones=new(){[config.DevicePluginID]=remoteMic}};store.Save(config);
    Check(store.Load().Microphones[config.DevicePluginID].Id==remoteMic.Id,"selected microphone persists");
    Check(store.Load().Microphones[config.DevicePluginID].GuardDictation,"microphone safeguard preference persists");
    config=config with{AutoConnect=true,DictationTested=true};
    var bindings = config.Bindings.ToList(); bindings[0] = bindings[0] with { Usage = new Usage(12, 0x221) };
    store.Save(config with { Bindings = bindings });
    Check(store.Load().AutoConnect&&store.Load().DictationTested,"setup choices persist");
    Check(store.Load().Bindings[0].Usage == new Usage(12, 0x221), "learned button persists");
    store.Save(config with { Bindings=visual.Bindings(bindings) });
    Check(store.Load().Bindings.Count>6,"variable visual bindings survive configuration reload");
    const string legacyAppID="org.justviberemote.app.codex",currentAppID="org.justviberemote.app.chatgpt";
    var oldPair=config.DevicePluginID+"|"+legacyAppID;var newPair=config.DevicePluginID+"|"+currentAppID;
    var legacyNamespace=config with {AppPluginID=legacyAppID,BindingSets=new(){[oldPair]=bindings},AppMappings=new(){[oldPair]=AppMapping.From(config)}};
    var legacyBytes=JsonSerializer.Serialize(legacyNamespace,ConfigurationStore.Json);File.WriteAllText(store.Path,legacyBytes);
    var namespaceMigrated=store.Load();
    Check(namespaceMigrated.AppPluginID==currentAppID,"legacy selected app namespace migrates to ChatGPT");
    Check(namespaceMigrated.BindingSets.ContainsKey(newPair)&&!namespaceMigrated.BindingSets.ContainsKey(oldPair),"legacy binding-set namespace migrates without duplicates");
    Check(namespaceMigrated.AppMappings[newPair].Shortcut==config.Shortcut&&!namespaceMigrated.AppMappings.ContainsKey(oldPair),"legacy app mapping retains voice settings under the new namespace");
    Check(File.ReadAllText(store.Path)==legacyBytes,"loading migration preserves the original file");
    var conflicting=legacyNamespace with {BindingSets=new(){[oldPair]=bindings,[newPair]=config.Bindings},AppMappings=new(){[oldPair]=AppMapping.From(config),[newPair]=AppMapping.From(config with {Shortcut="CTRL+D"})}};
    var preferred=conflicting.MigrateLegacyAppNamespace();
    Check(preferred.AppMappings[newPair].Shortcut=="CTRL+D"&&ReferenceEquals(preferred.BindingSets[newPair],config.Bindings)&&preferred.Shortcut=="CTRL+D","canonical settings win namespace collisions");
    store.Save(namespaceMigrated);Check(!File.ReadAllText(store.Path).Contains(legacyAppID),"saved migration uses only the ChatGPT namespace");
    File.WriteAllText(store.Path, "invalid");
    Throws(() => store.Load(), "corrupt settings rejected");
    Check(File.ReadAllText(store.Path) == "invalid", "corrupt file preserved");
}
finally { if (Directory.Exists(temporary)) Directory.Delete(temporary, true); }
using (var document = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "plugins/tests/conformance.json"))))
{
    foreach (var test in document.RootElement.EnumerateArray())
    {
        bool valid = true;
        try { PluginManifest.Decode(System.Text.Encoding.UTF8.GetBytes(test.GetProperty("manifest").GetRawText())); } catch { valid = false; }
        Check(valid == test.GetProperty("valid").GetBoolean(), "plugin conformance: " + test.GetProperty("name").GetString());
    }
}
var pluginTemp = Path.Combine(Path.GetTempPath(), "JustVibeRemotePlugins-" + Guid.NewGuid());
try
{
    Directory.CreateDirectory(pluginTemp);
    var bundled = Path.Combine(root, "plugins/bundled");
    var catalog = new PluginCatalog(bundled, pluginTemp);
    Check(catalog.Plugins.Count == 2 && catalog.Diagnostics.Count == 0, "bundled plugins discovered");
    void Install(string folder, byte[] bytes) { var path = Path.Combine(pluginTemp, folder); Directory.CreateDirectory(path); File.WriteAllBytes(Path.Combine(path, "plugin.json"), bytes); }
    Install("override", File.ReadAllBytes(Path.Combine(bundled, "org.justviberemote.device.xingwei-usb/plugin.json")));
    catalog = new PluginCatalog(bundled, pluginTemp);
    Check(catalog.Plugins.Count == 2 && catalog.Diagnostics.Count == 1, "bundled identity cannot be overridden");
    var template = File.ReadAllBytes(Path.Combine(root, "plugins/examples/app/plugin.json"));
    Install("first", template); Install("second", template);
    catalog = new PluginCatalog(bundled, pluginTemp);
    Check(catalog.Plugins.Count == 2 && catalog.Diagnostics.Count == 2, "duplicate user IDs disabled");
    Install("broken", "bad json"u8.ToArray());
    catalog = new PluginCatalog(bundled, pluginTemp);
    Check(catalog.Plugins.Count == 2 && catalog.Diagnostics.Count == 3, "malformed plugin isolated");
    Directory.Delete(Path.Combine(pluginTemp, "second"), true);
    catalog = new PluginCatalog(bundled, pluginTemp);
    Check(catalog.Plugins.Count == 3, "third-party app plugin accepted");
    var selected = new Configuration { Profile = profile, Shortcut = "RALT", ShortcutConfirmed = true, TargetAppPath = "C:/test/Codex.exe" };
    selected.Bindings[0] = selected.Bindings[0] with { Usage = new Usage(12, 0x221) };
    var original = selected;
    selected = PluginSelection.Select(selected, catalog, selected.DevicePluginID, "com.example.justviberemote.editor");
    Check(!selected.ShortcutConfirmed && selected.TargetAppPath.Length == 0, "new app requires shortcut confirmation and fresh target override");
    Check(selected.Bindings[0].Action == ActionKind.Native, "unsupported intent becomes native");
    selected = PluginSelection.Select(selected, catalog, original.DevicePluginID, original.AppPluginID);
    Check(selected.Bindings[0].Usage == original.Bindings[0].Usage, "device/app pair bindings restored");
    Check(selected.Bindings[0].Action == ActionKind.Dictate, "saved app intent restored");
    const string editorID="com.example.justviberemote.editor";
    var perApp=original with{VoiceMode="hold",DictationTested=true};
    perApp=PluginSelection.Select(perApp,catalog,perApp.DevicePluginID,editorID);
    Check(perApp.Bindings[0].Usage==original.Bindings[0].Usage,"new app reuses physical button learning");
    var appBindings=perApp.Bindings.ToList();appBindings[0]=appBindings[0] with{Action=ActionKind.Escape};
    perApp=perApp with{Bindings=appBindings,TargetAppPath="C:/test/Editor.exe"};
    perApp=PluginSelection.Select(perApp,catalog,perApp.DevicePluginID,original.AppPluginID);
    Check(perApp.ShortcutConfirmed&&perApp.TargetAppPath==original.TargetAppPath&&perApp.VoiceMode=="hold"&&perApp.DictationTested,"returning app restores shortcut, location, voice mode and test");
    Check(perApp.Bindings[0].Action==ActionKind.Dictate,"app actions remain separate");
    perApp=perApp with{FollowActiveApp=true};
    var codexFront=new ForegroundApp(Name:"Codex",Path:original.TargetAppPath,Instance:"1");
    var editorFront=new ForegroundApp(Name:"ExampleEditor",Path:"C:/test/Editor.exe",Instance:"2");
    var editRoute=AppRouting.Resolve(perApp,catalog.Apps,editorFront);
    Check(editRoute?.Bindings[0].Action==ActionKind.Escape&&editRoute.AppPluginID==editorID,"foreground editor uses its saved button action");
    Check(AppRouting.Resolve(perApp,catalog.Apps,codexFront)?.Bindings[0].Action==ActionKind.Dictate,"foreground Codex uses its different action");
    Check(perApp.AppPluginID==original.AppPluginID&&perApp.Bindings[0].Action==ActionKind.Dictate,"routing does not change editor profile");
    Check(AppRouting.Resolve(perApp,catalog.Apps,new(Name:"Other"))==null,"unknown app keeps native actions");
    Check(AppRouting.Resolve(perApp,catalog.Apps,null)==null,"unreadable foreground keeps native actions");
    Check(AppRouting.Resolve(perApp,catalog.Apps,editorFront with{Path="C:/wrong/Editor.exe"})==null,"explicit path never falls back to names");
    Check(AppRouting.Resolve(original with{FollowActiveApp=true},catalog.Apps,editorFront)==null,"unconfigured plugins are not activated");
    Check(AppRouting.Resolve(perApp with{DevicePluginID="another.device"},catalog.Apps,editorFront)==null,"another device does not reuse app bindings");
    Check(AppRouting.Resolve(perApp with{FollowActiveApp=false},catalog.Apps,editorFront)?.AppPluginID==perApp.AppPluginID,"manual mode preserves selected target");
    var editorPlugin=catalog.Find(editorID,"app");var codexPlugin=catalog.Find(original.AppPluginID,"app");
    var names=perApp with{TargetAppPath="",AppMappings=new(perApp.AppMappings)};
    var savedEditor=names.AppMappings[AppRouting.Key(names.DevicePluginID,editorID)] with{TargetAppPath=""};
    names.AppMappings[AppRouting.Key(names.DevicePluginID,editorID)]=savedEditor;
    Check(AppRouting.Resolve(names,[codexPlugin],new(Name:"cOdEx"))!=null,"Windows process names match case insensitively");
    Check(AppRouting.Resolve(names,[editorPlugin,editorPlugin],editorFront)==null,"equal matches disable custom routing");
    var overlap=editorPlugin with{Id="com.example.justviberemote.other",App=editorPlugin.App! with{Targets=new(){["windows"]=new(){BundleIds=[],Names=["Codex"]}}}};
    names.AppMappings[AppRouting.Key(names.DevicePluginID,overlap.Id)]=savedEditor;
    Check(AppRouting.Resolve(names,[overlap,codexPlugin],new(Name:"Codex"))==null,"overlapping process names require disambiguation");
    var specific=names with{TargetAppPath=original.TargetAppPath};
    Check(AppRouting.Resolve(specific,[overlap,codexPlugin],codexFront)?.AppPluginID==original.AppPluginID,"exact app path outranks overlapping process name");
    var oldButtons=original.Bindings.ToList();oldButtons[0]=oldButtons[0] with{Usage=new Usage(12,0x222)};
    var previousVersion=original with{BindingSets=new(){[AppRouting.Key(original.DevicePluginID,editorID)]=oldButtons}};
    var restoredLegacy=PluginSelection.Select(previousVersion,catalog,previousVersion.DevicePluginID,editorID);
    Check(restoredLegacy.Bindings[0].Usage==oldButtons[0].Usage,"existing per-app learning is never overwritten by another profile");
    var reduced=editorPlugin with{App=editorPlugin.App! with{Actions=[]}};
    Check(AppRouting.Resolve(perApp,[reduced],editorFront)?.Bindings[0].Action==ActionKind.Native,"removed plugin actions revert to native");
    Check(AppRouting.Resolve(perApp with{TargetAppPath="bad\0path"},[codexPlugin],codexFront)==null,"invalid stored path fails closed");
    var roundtrip=JsonSerializer.Deserialize<Configuration>(JsonSerializer.Serialize(perApp,ConfigurationStore.Json),ConfigurationStore.Json)!;
    Check(roundtrip.FollowActiveApp&&roundtrip.AppMappings[AppRouting.Key(perApp.DevicePluginID,editorID)].Bindings[0].Action==ActionKind.Escape,"active-app settings persist");
    var legacyRoute=AppRouting.Resolve(perApp with{AppMappings=[]},catalog.Apps,new(Name:"ExampleEditor"));
    Check(legacyRoute?.Bindings[0].Action==ActionKind.Escape&&legacyRoute.ShortcutConfirmed==false,"legacy binding sets migrate without guessing shortcut consent");
    Throws(() => catalog.Find("missing.app", "app"), "missing selected plugin rejected");
    Throws(() => PluginManifest.Decode(new byte[65_537]), "manifest size bounded");
}
finally { Directory.Delete(pluginTemp, true); }
// Workspace/session parity policies stay portable: no Raw Input, output, or recording.
var ownership=new RemoteSessionOwnership();
ownership.Start("first","1915:1025");ownership.Start("second","1915:1026");
Throws(()=>ownership.Start("duplicate","1915:1025"),"duplicate receiver identities cannot run concurrently");
Check(ownership.ClaimVoice("first")&&!ownership.ClaimVoice("second"),"only one receiver owns held dictation output");
Check(!ownership.AllowsOutput("second")&&ownership.AllowsOutput("first"),"another receiver cannot type into held dictation");
ownership.ReleaseVoice("second");Check(ownership.VoiceOwner=="first","another receiver cannot release voice ownership");
ownership.Stop("first");Check(ownership.ClaimVoice("second"),"stopping the owner allows another receiver to dictate");
ownership.Stop("second");Check(ownership.AllowsOutput("first"),"stopping both receivers clears voice ownership");
var voiceConfig=new Configuration{Profile=profile,VoiceTyping=new(VoiceTypingMode.Fallback,"microphone",true)};
Check(VoiceTypingRouting.ShouldTrigger(voiceConfig,null,"microphone",true,false,false),"explicit Windows voice fallback handles unsupported apps");
Check(!VoiceTypingRouting.ShouldTrigger(voiceConfig,null,"microphone",false,false,false),"voice typing never triggers on release");
Check(!VoiceTypingRouting.ShouldTrigger(voiceConfig,null,"microphone",true,true,false),"button learning never starts voice typing");
Check(!VoiceTypingRouting.ShouldTrigger(voiceConfig,null,"microphone",true,false,true),"button test never starts voice typing");
Check(!VoiceTypingRouting.ShouldTrigger(voiceConfig,null,"other",true,false,false),"only selected physical voice control may trigger");
Check(!VoiceTypingRouting.ShouldTrigger(voiceConfig with{VoiceTyping=new()},null,"microphone",true,false,false),"Windows voice typing is opt in");
var configuredVoice=voiceConfig with{ShortcutConfirmed=true,Shortcut="CTRL+M",Bindings=[new("Mic",new Usage(12,1),ActionKind.Dictate,"microphone")]};
Check(!VoiceTypingRouting.ShouldTrigger(voiceConfig,configuredVoice,"microphone",true,false,false),"confirmed app dictation takes priority over OS fallback");
Check(VoiceTypingRouting.ShouldTrigger(voiceConfig,configuredVoice with{ShortcutConfirmed=false},"microphone",true,false,false),"unconfirmed app shortcut permits explicit fallback");
Check(VoiceTypingRouting.ShouldTrigger(voiceConfig with{VoiceTyping=new(VoiceTypingMode.Everywhere,"microphone",true)},configuredVoice,"microphone",true,false,false),"everywhere mode deliberately overrides app dictation");
Throws(()=>new VoiceTypingSettings(VoiceTypingMode.Everywhere,"microphone",false).Validate(),"voice typing confirmation required");
Throws(()=>new VoiceTypingSettings(VoiceTypingMode.Fallback,null,true).Validate(),"voice typing requires a chosen physical control");
new VoiceTypingSettings().Validate();
var workspaceTemp=Path.Combine(Path.GetTempPath(),"justvibe-workspace-"+Guid.NewGuid());
try
{
    var bundled=Path.Combine(root,"plugins","bundled");
    var workspaceCatalog=new PluginCatalog(bundled,Path.Combine(workspaceTemp,"plugins"));
    var originalConfig=new Configuration{Profile=profile,AutoConnect=true,Shortcut="CTRL+M",ShortcutConfirmed=true,Bindings=visual.Bindings()};
    var originalStore=new ConfigurationStore(Path.Combine(workspaceTemp,"settings.json"));originalStore.Save(originalConfig);
    var oldBytes=File.ReadAllBytes(originalStore.Path);
    var library=new RemoteConfigurationLibrary(workspaceTemp,originalConfig,workspaceCatalog);
    var independent=library.Load(originalConfig.DevicePluginID);
    Check(independent.Shortcut=="CTRL+M"&&independent.AutoConnect,"per-receiver migration preserves legacy voice and reconnect choices");
    Check(File.ReadAllBytes(originalStore.Path).SequenceEqual(oldBytes),"loading per-receiver workspace never overwrites legacy settings");
    var shared=PluginSelection.Select(independent,workspaceCatalog,independent.DevicePluginID,Configuration.NoSpecificAppID);
    Check(shared.Bindings.All(b=>SharedActions.Supports(b.Action)),"No specific app removes app-only actions");
    shared=shared with{Bindings=shared.Bindings.Select((b,index)=>index==0?b with{Action=ActionKind.Backspace}:b).ToList()};
    var sharedRoute=AppRouting.Resolve(shared,workspaceCatalog.Apps,new(Name:"Unconfigured",Path:"C:/Other.exe",Instance:"123"));
    Check(sharedRoute?.AppPluginID==Configuration.NoSpecificAppID&&sharedRoute.TargetInstance=="123","shared actions route only to a known foreground instance");
    Check(sharedRoute?.Bindings[0].Action==ActionKind.Backspace,"shared backspace works without an app plugin");
    Check(AppRouting.Resolve(shared,workspaceCatalog.Apps,null)==null,"unknown foreground disables shared output");
    var checkpoint=independent with{RemoteSetupCheckpoint=new(RemoteSetupStage.Shortcut,true),RemoteSetupCompleted=false,VoiceTyping=new(VoiceTypingMode.Fallback,"microphone",true),ArtworkPath="local-photo.png"};
    library.StoreFor(independent.DevicePluginID).Save(checkpoint);
    var loaded=library.Load(independent.DevicePluginID);
    Check(loaded.RemoteSetupCheckpoint==checkpoint.RemoteSetupCheckpoint&&!loaded.RemoteSetupCompleted,"setup resumes its exact saved step without claiming completion");
    Check(loaded.VoiceTyping==checkpoint.VoiceTyping&&loaded.ArtworkPath==checkpoint.ArtworkPath,"voice typing and local artwork persist per receiver");
    var restored=PluginSelection.Select(shared,workspaceCatalog,shared.DevicePluginID,independent.AppPluginID);
    Check(restored.ShortcutConfirmed&&restored.Shortcut=="CTRL+M","returning from shared controls restores confirmed app settings");
}
finally{if(Directory.Exists(workspaceTemp))Directory.Delete(workspaceTemp,true);}
var receiverMigrationTemp=Path.Combine(Path.GetTempPath(),"justvibe-receiver-migration-"+Guid.NewGuid());
try
{
    var pluginDirectory=Path.Combine(receiverMigrationTemp,"plugins");
    var catalog=new PluginCatalog(Path.Combine(root,"plugins","bundled"),pluginDirectory);
    var source=catalog.Devices.First();
    var second=source with{Id="com.example.justvibe.second",Name="Synthetic second receiver",Device=source.Device! with{Profile=source.Device.Profile with{Id="synthetic-second",ProductId=4134}}};
    string folder=Path.Combine(pluginDirectory,second.Id);Directory.CreateDirectory(folder);var fixture=System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(Path.Combine(root,"plugins","bundled",source.Id,"plugin.json")))!;fixture["id"]=second.Id;fixture["name"]=second.Name;fixture["device"]!["profile"]!["id"]="synthetic-second";fixture["device"]!["profile"]!["productId"]=4134;File.WriteAllText(Path.Combine(folder,"plugin.json"),fixture.ToJsonString());
    catalog=new PluginCatalog(Path.Combine(root,"plugins","bundled"),pluginDirectory);
    var migrationLegacy=new Configuration{Profile=source.Device!.Profile,DevicePluginID=source.Id,AutoConnect=true,RemoteSetupCompleted=true,RemoteSetupCheckpoint=new(RemoteSetupStage.Practice,true),VoiceTyping=new(VoiceTypingMode.Everywhere,"microphone",true),ArtworkPath="first-photo.png"};
    var library=new RemoteConfigurationLibrary(receiverMigrationTemp,migrationLegacy,catalog);
    var other=library.Load(second.Id);
    Check(!other.AutoConnect&&!other.RemoteSetupCompleted&&other.RemoteSetupCheckpoint==null,"another receiver never inherits reconnect or setup consent");
    Check(other.VoiceTyping.Mode==VoiceTypingMode.Off&&other.ArtworkPath=="","another receiver never inherits OS voice typing consent or photo");
    var file=library.StoreFor(second.Id);file.Save(migrationLegacy);var bytes=File.ReadAllBytes(file.Path);
    Throws(()=>library.Load(second.Id),"receiver store rejects settings for a different device identity");
    Check(File.ReadAllBytes(file.Path).SequenceEqual(bytes),"mismatched receiver settings are preserved for recovery");
}
finally{if(Directory.Exists(receiverMigrationTemp))Directory.Delete(receiverMigrationTemp,true);}
var pendingVoice=new PendingVoiceStart();
var cancelledTicket=pendingVoice.Begin();pendingVoice.Cancel();
Check(!pendingVoice.TryComplete(cancelledTicket,true),"focus/profile cancellation invalidates delayed dictation start");
var currentTicket=pendingVoice.Begin();
Check(!pendingVoice.TryComplete(cancelledTicket,true)&&pendingVoice.Pending,"stale callback cannot clear a newer pending start");
Check(!pendingVoice.TryComplete(currentTicket,false),"stopped receiver cannot commit pending dictation");
Check(pendingVoice.TryComplete(currentTicket,true)&&!pendingVoice.Pending,"current running receiver may commit exactly one delayed start");
Check(!pendingVoice.TryComplete(currentTicket,true),"duplicate delayed callback cannot inject another shortcut");
var launchCatalog=new PluginCatalog(Path.Combine(root,"plugins","bundled"),Path.Combine(Path.GetTempPath(),"justvibe-launch-test-"+Guid.NewGuid()));
var launchApp=launchCatalog.Apps.First();
var legacyLaunch=JsonSerializer.Deserialize<Binding>("{\"name\":\"Power\",\"action\":\"Focus\"}",ConfigurationStore.Json)!;
Check(legacyLaunch.LaunchAppID==null&&legacyLaunch.LaunchAppPath==null,"legacy Show app bindings decode without a launch selection");
var launchConfig=new Configuration{AppPluginID=Configuration.NoSpecificAppID};
launchConfig=launchConfig with{AppMappings=new(){[AppRouting.Key(launchConfig.DevicePluginID,launchApp.Id)]=AppMapping.From(launchConfig with{TargetAppPath="C:\\Apps\\Chosen.exe"})}};
var launchBinding=new Binding("Power",new Usage(12,0x30),ActionKind.Focus,"power",launchApp.Id);
launchConfig=launchConfig with{Bindings=[launchBinding]};
var chosenLaunch=AppRouting.LaunchTarget(launchBinding,launchConfig,launchConfig,launchCatalog.Apps);
Check(chosenLaunch.AppPluginID==launchApp.Id&&chosenLaunch.TargetAppPath=="C:\\Apps\\Chosen.exe","Power opens its selected app using the saved location");
Check(launchConfig.AppPluginID==Configuration.NoSpecificAppID,"resolving a launch preserves the editor profile");
var launchRoute=AppRouting.Resolve(launchConfig,launchCatalog.Apps,new ForegroundApp(Name:"Unrelated",Path:"C:\\Unrelated.exe",Instance:"42"));
Check(launchRoute?.Bindings[0].Action==ActionKind.Focus&&launchRoute.Bindings[0].LaunchAppID==launchApp.Id,"shared routing retains the explicit Open app target");
var explicitLaunch=launchBinding with{LaunchAppPath="C:\\Apps\\Explicit.exe"};
Check(AppRouting.LaunchTarget(explicitLaunch,launchConfig,launchConfig,launchCatalog.Apps).TargetAppPath==explicitLaunch.LaunchAppPath,"explicitly located app takes precedence");
Check(JsonSerializer.Deserialize<Binding>(JsonSerializer.Serialize(explicitLaunch,ConfigurationStore.Json),ConfigurationStore.Json)==explicitLaunch,"launch identity and path survive settings serialization");
Throws(()=>AppRouting.LaunchTarget(launchBinding with{LaunchAppID="missing.app"},launchConfig,launchConfig,launchCatalog.Apps),"removed app does not fall back to another launch target");
Throws(()=>AppRouting.LaunchTarget(legacyLaunch,launchConfig,launchConfig,launchCatalog.Apps),"shared Open app never guesses an app");
var legacyLaunchConfig=launchConfig with{AppPluginID=launchApp.Id,TargetAppPath="C:\\Legacy.exe"};
Check(AppRouting.LaunchTarget(legacyLaunch,legacyLaunchConfig,legacyLaunchConfig,launchCatalog.Apps).TargetAppPath=="C:\\Legacy.exe","legacy Show app retains its original profile target");
var launchDevice=launchCatalog.Devices.First();launchConfig=launchConfig with{DevicePluginID=launchDevice.Id,Profile=launchDevice.Device!.Profile};
var launchSwitched=PluginSelection.Select(launchConfig,launchCatalog,launchDevice.Id,launchApp.Id);
var launchRestored=PluginSelection.Select(launchSwitched,launchCatalog,launchDevice.Id,Configuration.NoSpecificAppID);
Check(launchRestored.Bindings.Any(b=>b.Action==ActionKind.Focus&&b.LaunchAppID==launchApp.Id),"Open app selection survives profile switching");
Console.WriteLine($"JustVibeRemote Windows core: {passed} checks passed");
