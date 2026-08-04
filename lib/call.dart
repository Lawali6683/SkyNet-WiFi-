import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:dio/dio.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:system_alert_window/system_alert_window.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class SkyNetCallPage extends StatefulWidget {
  const SkyNetCallPage({Key? key}) : super(key: key);

  @override
  State<SkyNetCallPage> createState() => _SkyNetCallPageState();
}

class _SkyNetCallPageState extends State<SkyNetCallPage> with TickerProviderStateMixin {
  late Box _dbBox;
  final Dio _dio = Dio();
  final FlutterTts _tts = FlutterTts();
  
  List<Map<String, dynamic>> _registeredContacts = [];
  List<Map<String, dynamic>> _unregisteredContacts = [];
  List<Map<String, dynamic>> _missedCalls = [];
  
  bool _isLoading = false;
  bool _showMissedCallsOverlay = false;
  int _onlineFriendsCount = 0;
  int _planRemainingDays = 0;
  bool _isVideoPlanActive = false;
  String _activeTab = "Contact";
  int? _expandedContactIndex;

  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  bool _isInCall = false;
  bool _isLoudspeaker = false;
  Offset _pipOffset = const Offset(20, 20);
  bool _showPip = true;

  late AnimationController _acceptIconController;

  @override
  void initState() {
    super.initState();
    _initHiveAndDependencies();
    _acceptIconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  Future<void> _initHiveAndDependencies() async {
    _dbBox = Hive.box('user_profiles_box');
    _loadLocalProfileMetrics();
    _initializeRenderers();
    _runBackgroundContactScraper();
  }

  void _loadLocalProfileMetrics() {
    final profile = Map<String, dynamic>.from(_dbBox.get('profile_data', defaultValue: <String, dynamic>{}));
    setState(() {
      _onlineFriendsCount = int.tryParse(profile['online_friends_count']?.toString() ?? '34') ?? 34;
      _planRemainingDays = int.tryParse(profile['video_plan_days']?.toString() ?? '30') ?? 30;
      _isVideoPlanActive = (profile['video_call_enabled'] ?? 'no') == 'yes' && _planRemainingDays > 0;
      _missedCalls = List<Map<String, dynamic>>.from(profile['missed_calls'] ?? []);
    });
  }

  Future<void> _initializeRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _runBackgroundContactScraper() async {
    try {
      List<String> mockHardwarePhones = ["+2348011112222", "+2348033334444", "+2348055556666"];
      final response = await _dio.post(
        'https://skynetwifi.pages.dev/mycontct',
        data: {'phones': mockHardwarePhones},
      );
      if (response.statusCode == 200 && response.data != null) {
        final List dynamicList = response.data['registered'] ?? [];
        final List unregList = response.data['unregistered'] ?? [];
        
        _registeredContacts = dynamicList.map((e) => Map<String, dynamic>.from(e)).toList();
        _unregisteredContacts = unregList.map((e) => Map<String, dynamic>.from(e)).toList();
        
        for (var contact in _registeredContacts) {
          await _cacheProfileImageLocally(contact['profile_url'], contact['uuid']);
        }
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _cacheProfileImageLocally(String? url, String uuid) async {
    if (url == null || url.isEmpty) return;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/thumb_$uuid.jpg';
      final file = File(filePath);
      if (!await file.exists()) {
        await _dio.download(url, filePath);
      }
    } catch (_) {}
  }

  Future<void> _triggerManualSync() async {
    setState(() => _isLoading = true);
    try {
      await _runBackgroundContactScraper();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _triggerAudioCall(Map<String, dynamic> contact) async {
    try {
      final response = await _dio.post(
        'https://skynetwifi.pages.dev/api/call',
        data: {'target_uuid': contact['uuid'], 'type': 'audio'},
      );
      if (response.statusCode == 200) {
        _setRoutingToEarSpeaker();
        _renderInCallOverlay(contact, false);
      } else {
        _triggerFailureAlert("The user you are trying to reach is unavailable");
      }
    } catch (_) {
      _triggerFailureAlert("Network connection lost. Please check your interface");
    }
  }

  Future<void> _triggerVideoCall(Map<String, dynamic> contact) async {
    if (!_isVideoPlanActive) {
      _showVideoUpgradeOverlay();
      return;
    }
    try {
      final response = await _dio.post(
        'https://skynetwifi.pages.dev/api/videocall',
        data: {'target_uuid': contact['uuid']},
      );
      if (response.statusCode == 200) {
        await _startWebRTCPipeline();
        _renderInCallOverlay(contact, true);
      } else {
        _triggerFailureAlert("The user you are trying to reach is unavailable");
      }
    } catch (_) {
      _triggerFailureAlert("Network connection lost. Please check your interface");
    }
  }

  Future<void> _processVideoPlanPayment() async {
    try {
      final double currentBalance = double.tryParse(_dbBox.get('profile_data', defaultValue: {})['user_balance']?.toString() ?? '0.0') ?? 0.0;
      if (currentBalance < 3000.0) {
        _triggerFailureAlert("Network connection lost. Please check your interface");
        return;
      }
      final response = await _dio.post('https://skynetwifi.pages.dev/api/pay', data: {'amount': 3000});
      if (response.statusCode == 200) {
        final profile = Map<String, dynamic>.from(_dbBox.get('profile_data', defaultValue: {}));
        profile['video_call_enabled'] = 'yes';
        profile['video_plan_days'] = 30;
        await _dbBox.put('profile_data', profile);
        _loadLocalProfileMetrics();
        if (Navigator.canPop(context)) Navigator.pop(context);
      }
    } catch (_) {}
  }

  Future<void> _startWebRTCPipeline() async {
    final Map<String, dynamic> configuration = {
      "iceServers": [{"url": "stun:stun.l.google.com:19302"}]
    };
    final Map<String, dynamic> loopConstraints = {
      "mandatory": {
        "OfferToReceiveAudio": true,
        "OfferToReceiveVideo": true,
      },
      "optional": [],
    };
    
    _peerConnection = await createPeerConnection(configuration, loopConstraints);
    
    final Map<String, dynamic> mediaConstraints = {
      "audio": {"noise_suppression": true, "echo_cancellation": true, "gain_control": true},
      "video": {
        "mandatory": {"minWidth": "640", "minHeight": "480", "minFrameRate": "30"},
        "optional": [{"bandWidthCeilingKbps": 1000}]
      }
    };
    
    MediaStream localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    _peerConnection!.addStream(localStream);
    _localRenderer.srcObject = localStream;
    
    _peerConnection!.onAddStream = (stream) {
      _remoteRenderer.srcObject = stream;
    };
    setState(() => _isInCall = true);
  }

  void _setRoutingToEarSpeaker() {
    setState(() => _isLoudspeaker = false);
  }

  void _toggleLoudspeaker() {
    setState(() => _isLoudspeaker = !_isLoudspeaker);
  }

  Future<void> _triggerFailureAlert(String alertPhrase) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        content: Text(alertPhrase, style: const TextStyle(color: Colors.white, fontSize: 14)),
      ),
    );
    await _tts.setLanguage("en-US");
    await _tts.speak(alertPhrase);
    await Future.delayed(const Duration(seconds: 3));
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  void _showVideoUpgradeOverlay() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: EdgeInsets.all(20.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Premium Video Access Required", style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.bold)),
            SizedBox(height: 12.h),
            Text("Your video plan is inactive. Unlock absolute high-fidelity video calling paths for 30 consecutive days.", style: TextStyle(color: Colors.grey, fontSize: 13.sp), textAlign: TextAlign.center),
            SizedBox(height: 20.h),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D47A1), minimumSize: Size(double.infinity, 45.h)),
              onPressed: _processVideoPlanPayment,
              child: const Text("Pay in your wallet - N3,000/Month", style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      ),
    );
  }

  void _renderInCallOverlay(Map<String, dynamic> contact, bool isVideo) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      pageBuilder: (context, anim1, anim2) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Scaffold(
              backgroundColor: Colors.black,
              body: Stack(
                children: [
                  if (isVideo) ...[
                    Positioned.fill(child: RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)),
                    if (_showPip)
                      Positioned(
                        left: _pipOffset.dx,
                        top: _pipOffset.dy,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              _pipOffset += details.delta;
                            });
                            setModalState(() {});
                          },
                          child: Container(
                            width: 110.w,
                            height: 150.h,
                            decoration: BoxDecoration(border: Border.all(color: Colors.white30, width: 2)),
                            child: Stack(
                              children: [
                                RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: GestureDetector(
                                    onTap: () {
                                      setModalState(() => _showPip = false);
                                    },
                                    child: const Icon(Icons.close, color: Colors.white, size: 16),
                                  ),
                                )
                              ],
                            ),
                          ),
                        ),
                      ),
                  ] else ...[
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(radius: 50.r, backgroundColor: Colors.grey[800], child: const Icon(Icons.person, size: 50, color: Colors.white)),
                          SizedBox(height: 20.h),
                          Text(contact['local_contact_name'] ?? 'Unknown', style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.bold)),
                          SizedBox(height: 10.h),
                          Text(_isLoudspeaker ? "Loudspeaker Active" : "Connected via Ear-Speaker", style: TextStyle(color: Colors.white54, fontSize: 13.sp)),
                        ],
                      ),
                    ),
                  ],
                  Positioned(
                    bottom: 40.h,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: Icon(_isLoudspeaker ? Icons.volume_up : Icons.volume_down, color: Colors.white, size: 28.r),
                          onPressed: () {
                            _toggleLoudspeaker();
                            setModalState(() {});
                          },
                        ),
                        GestureDetector(
                          onTap: () {
                            _hangUpCall();
                            Navigator.pop(context);
                          },
                          child: Image.asset('access/images/deciine', width: 65.r, height: 65.r),
                        ),
                        ScaleTransition(
                          scale: _acceptIconController,
                          child: GestureDetector(
                            onTap: () {},
                            child: Image.asset('access/images/accept', width: 65.r, height: 65.r),
                          ),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _hangUpCall() async {
    await _peerConnection?.close();
    _peerConnection = null;
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    setState(() => _isInCall = false);
    await _tts.setLanguage("en-US");
    await _tts.speak("Call ended by user");
  }

  void _spawnMessageOverlay(Map<String, dynamic> contact) {
    final TextEditingController textController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text("Message to ${contact['local_contact_name']}", style: TextStyle(color: Colors.white, fontSize: 14.sp)),
        content: TextField(
          controller: textController,
          maxLength: 50,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () async {
              if (textController.text.trim().isNotEmpty) {
                await _dio.post('https://skynetwifi.pages.dev/api/massage', data: {
                  'target_uuid': contact['uuid'],
                  'phone': contact['phone_number'],
                  'payload': textController.text.trim()
                });
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text("Send", style: TextStyle(color: Color(0xFF0D47A1))),
          )
        ],
      ),
    );
  }

  void _executeLocalContactActionMenu(Map<String, dynamic> contact, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text("Delete Contact", style: TextStyle(color: Colors.white)),
              onTap: () {
                setState(() {
                  _registeredContacts.removeAt(index);
                  _expandedContactIndex = null;
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.grey),
              title: const Text("Block On/Off", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  @pragma('vm:entry-point')
  static void onSystemAlertWindowCallback(String tag) {
    if (tag == "close_chat_head") {
      SystemAlertWindow.closeSystemWindow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 690),
      minTextAdapt: true,
      builder: (context, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            bool isDesktop = constraints.maxWidth > 600;
            return Scaffold(
              backgroundColor: const Color(0xFFFAFAFA),
              appBar: AppBar(
                backgroundColor: const Color(0xFF0D47A1),
                elevation: 0,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("SkyNet Core Audio/Video Panel", style: TextStyle(fontSize: 14.sp, color: Colors.white, fontWeight: FontWeight.bold)),
                    Text("$_onlineFriendsCount Friends Online | Video Plan: ${_isVideoPlanActive ? '$_planRemainingDays Days Left' : 'Expired'}", style: TextStyle(fontSize: 10.sp, color: Colors.white70)),
                  ],
                ),
                actions: [
                  if (_isLoading)
                    const Center(child: Padding(padding: EdgeInsets.right(16), child: CircularProgressIndicator(color: Colors.white)))
                ],
              ),
              body: Stack(
                children: [
                  isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
                  if (_showMissedCallsOverlay) _buildMissedCallsOverlayWidget(),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildNavigationTabBar(),
        Expanded(
          child: _activeTab == "Contact" ? _buildContactsListView() : _buildUnregisteredListView(),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        Container(
          width: 200.w,
          color: Colors.white,
          child: ListView(
            children: [
              ListTile(
                leading: const Icon(FontAwesomeIcons.addressBook),
                title: const Text("Contacts"),
                selected: _activeTab == "Contact",
                onTap: () => setState(() => _activeTab = "Contact"),
              ),
              ListTile(
                leading: const Icon(FontAwesomeIcons.phoneSlash),
                title: const Text("Missed Calls"),
                onTap: () => setState(() => _showMissedCallsOverlay = true),
              ),
              ListTile(
                leading: const Icon(FontAwesomeIcons.syncAlt),
                title: const Text("Sync Contacts"),
                onTap: _triggerManualSync,
              )
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _buildContactsListView())
      ],
    );
  }

  Widget _buildNavigationTabBar() {
    return Container(
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildTabButton("Contact", FontAwesomeIcons.addressBook),
          _buildTabButton("Missed Call", FontAwesomeIcons.phoneSlash),
          _buildTabButton("Share to my contact", FontAwesomeIcons.shareNodes),
          _buildTabButton("More", FontAwesomeIcons.ellipsis),
        ],
      ),
    );
  }

  Widget _buildTabButton(String tabName, IconData icon) {
    bool isActive = _activeTab == tabName;
    return InkWell(
      onTap: () {
        if (tabName == "Missed Call") {
          setState(() => _showMissedCallsOverlay = true);
        } else if (tabName == "More") {
          _triggerManualSync();
        } else if (tabName == "Share to my contact") {
          setState(() => _activeTab = "Share");
        } else {
          setState(() => _activeTab = tabName);
        }
      },
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 8.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(icon, color: isActive ? const Color(0xFF0D47A1) : Colors.grey, size: 18.r),
            SizedBox(height: 4.h),
            Text(tabName, style: TextStyle(color: isActive ? const Color(0xFF0D47A1) : Colors.grey, fontSize: 9.sp))
          ],
        ),
      ),
    );
  }

  Widget _buildContactsListView() {
    if (_registeredContacts.isEmpty) {
      return const Center(child: Text("No registered core contacts found."));
    }
    return ListView.separated(
      itemCount: _registeredContacts.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final contact = _registeredContacts[index];
        bool isExpanded = _expandedContactIndex == index;
        return Column(
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blueAccent,
                child: Text(contact['local_contact_name']?[0] ?? 'U', style: const TextStyle(color: Colors.white)),
              ),
              title: Text(contact['local_contact_name'] ?? 'Unknown Member', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
              trailing: IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () => _executeLocalContactActionMenu(contact, index),
              ),
              onTap: () {
                setState(() {
                  _expandedContactIndex = isExpanded ? null : index;
                });
              },
            ),
            if (isExpanded) _buildQuickActionSubContainer(contact)
          ],
        );
      },
    );
  }

  Widget _buildUnregisteredListView() {
    if (_unregisteredContacts.isEmpty) {
      return const Center(child: Text("No unregistered contacts."));
    }
    return ListView.builder(
      itemCount: _unregisteredContacts.length,
      itemBuilder: (context, index) {
        final contact = _unregisteredContacts[index];
        return ListTile(
          title: Text(contact['local_contact_name'] ?? 'External Contact'),
          subtitle: Text(contact['phone_number'] ?? ''),
          trailing: TextButton(
            child: const Text("Invite via SMS"),
            onPressed: () {},
          ),
        );
      },
    );
  }

  Widget _buildQuickActionSubContainer(Map<String, dynamic> contact) {
    return Container(
      color: const Color(0xFFF0F4C3),
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(icon: const Icon(Icons.phone, color: Colors.green), onPressed: () => _triggerAudioCall(contact)),
          IconButton(icon: const Icon(Icons.videocam, color: Colors.blue), onPressed: () => _triggerVideoCall(contact)),
          IconButton(icon: const Icon(Icons.message, color: Colors.orange), onPressed: () => _spawnMessageOverlay(contact)),
        ],
      ),
    );
  }

  Widget _buildMissedCallsOverlayWidget() {
    return Positioned.fill(
      child: Container(
        color: Colors.blackDE,
        child: Center(
          child: Container(
            width: 300.w,
            height: 400.h,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12.r)),
            padding: EdgeInsets.all(16.w),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Offline Missed Calls", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _showMissedCallsOverlay = false))
                  ],
                ),
                Expanded(
                  child: _missedCalls.isEmpty
                      ? const Center(child: Text("No missed call parameters recorded."))
                      : ListView.builder(
                          itemCount: _missedCalls.length,
                          itemBuilder: (context, index) {
                            final log = _missedCalls[index];
                            return ListTile(
                              title: Text(log['caller_name'] ?? 'Unknown Caller'),
                              subtitle: Text(log['timestamp'] ?? ''),
                            );
                          },
                        ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _acceptIconController.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _peerConnection?.dispose();
    super.dispose();
  }
}