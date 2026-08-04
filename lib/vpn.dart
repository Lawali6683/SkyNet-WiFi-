import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

class SkyNetVpnController {
  static final SkyNetVpnController _instance = SkyNetVpnController._internal();
  factory SkyNetVpnController() => _instance;
  SkyNetVpnController._internal();

  static const String appSecret = "@haruna66";
  final Box userBox = Hive.box('user_profiles_box');
  
  bool _isConnected = false;
  String? _ephemeralKey;
  StreamSubscription? _connectivitySubscription;
  Timer? _bucketTimer;

  double _availableTokens = 15000000.0; 
  final double _maxBucketCapacity = 15000000.0;
  final double _refillRatePerSecond = 15000000.0; 

  final ValueNotifier<String?> connectionStatusNotifier = ValueNotifier("Disconnected");
  final ValueNotifier<Map<String, dynamic>?> alertNotifier = ValueNotifier(null);

  static final GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey<NavigatorState>();

  Future<void> initializeVpnEngine() async {
    await _checkInitialInterfaceState();
    _startBackgroundNetworkScanning();
  }

  Future<void> _checkInitialInterfaceState() async {
    try {
      final result = await InternetAddress.lookup('canvzqvhrvyyanoicmgf.supabase.co');
      if (result.isEmpty || result.first.address.isEmpty) {
        _triggerTopFloatingAlert("Turn on your Data or Wi-Fi to establish SkyNet connectivity", null);
      }
    } catch (_) {
      _triggerTopFloatingAlert("Turn on your Data or Wi-Fi to establish SkyNet connectivity", null);
    }
  }

  void _startBackgroundNetworkScanning() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Stream.periodic(const Duration(seconds: 5)).listen((_) async {
      if (Platform.isWindows) {
        await _scanWindowsWifiAdapters();
      } else if (Platform.isAndroid || Platform.isIOS) {
        await _scanMobileRadioChannels();
      }
    });
  }

  Future<void> _scanWindowsWifiAdapters() async {
    bool routerDetected = await _simulateSsidScan("skyNet WiFi");
    if (routerDetected) {
      _triggerTopFloatingAlert("SkyNet Router Detected", "Connect to Router");
    }
  }

  Future<void> _scanMobileRadioChannels() async {
    bool routerDetected = await _simulateSsidScan("skyNet WiFi");
    if (routerDetected) {
      _triggerTopFloatingAlert("SkyNet Router Detected", "Connect to Router");
    }
  }

  Future<bool> _simulateSsidScan(String targetSsid) async {
    final profile = userBox.get('profile_data');
    if (profile is Map && profile['online_status'] == 'on') {
      return true;
    }
    return false;
  }

  void _triggerTopFloatingAlert(String message, String? actionText) {
    alertNotifier.value = {
      "message": message,
      "actionText": actionText,
      "timestamp": DateTime.now().millisecondsSinceEpoch
    };

    final context = globalNavigatorKey.currentContext;
    if (context != null) {
      final overlay = Overlay.of(context);
      late OverlayEntry entry;
      
      entry = OverlayEntry(
        builder: (context) => Positioned(
          top: 50.0,
          left: 20.0,
          right: 20.0,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              decoration: BoxDecoration(
                color: const Color(0xFF0D47A1),
                borderRadius: BorderRadius.circular(12.0),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 10.0, offset: Offset(0, 4))
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.0),
                    ),
                  ),
                  if (actionText != null)
                    TextButton(
                      style: TextButton.styleFrom(backgroundColor: Colors.white24),
                      onPressed: () {
                        entry.remove();
                        executeRouterBindingProtocol();
                      },
                      child: Text(actionText, style: const TextStyle(color: Colors.white, fontSize: 11.0)),
                    )
                ],
              ),
            ),
          ),
        ),
      );

      overlay.insert(entry);
      if (actionText == null) {
        Timer(const Duration(seconds: 3), () => entry.remove());
      }
    }
  }

  Future<void> executeRouterBindingProtocol() async {
    connectionStatusNotifier.value = "Binding to SkyNet Access Point...";
    await Future.delayed(const Duration(milliseconds: 800));
    await establishTunnelSession(transientToken: "session_init_payload_token");
  }

  Future<void> establishTunnelSession({required String transientToken}) async {
    final profile = userBox.get('profile_data', defaultValue: {});
    if (profile is! Map) return;

    final String plan1Active = profile['plan1_active'] ?? 'no';
    final String plan2Active = profile['plan2_active'] ?? 'no';
    final double dataBalance = double.tryParse(profile['data_balance']?.toString() ?? '0.0') ?? 0.0;
    final String deviceUuid = profile['device_uuid'] ?? 'unassigned_node_uuid';

    _ephemeralKey = _generateHmacSha256Signature(deviceUuid, transientToken);

    if (plan1Active == 'yes' && dataBalance > 0.00) {
      await _provisionUncappedTunnel(_ephemeralKey!);
    } else if (plan2Active == 'yes') {
      await _provisionClampedTunnel(_ephemeralKey!);
    } else {
      await _provisionWalledGardenTunnel(_ephemeralKey!);
    }
  }

  String _generateHmacSha256Signature(String uuid, String token) {
    final keyBytes = utf8.encode(appSecret);
    final messageBytes = utf8.encode("$uuid:$token");
    final hmac = Hmac(sha256, keyBytes);
    final digest = hmac.convert(messageBytes);
    return digest.toString();
  }

  Future<void> _provisionUncappedTunnel(String sessionKey) async {
    _stopTokenBucket();
    final Map<String, String> wireguardConfig = {
      "PrivateKey": sessionKey,
      "Address": "10.0.0.2/32",
      "DNS": "1.1.1.1",
      "PublicKey": "skynet_public_backbone_gateway_server_node",
      "Endpoint": "canvzqvhrvyyanoicmgf.supabase.co:51820",
      "AllowedIPs": "0.0.0.0/0",
      "PersistentKeepalive": "25"
    };
    await _executeSystemInterfaceBinding(wireguardConfig);
  }

  Future<void> _provisionClampedTunnel(String sessionKey) async {
    _startTokenBucketAlgorithm(15.0); 
    final Map<String, String> wireguardConfig = {
      "PrivateKey": sessionKey,
      "Address": "10.0.0.3/32",
      "DNS": "1.1.1.1",
      "PublicKey": "skynet_public_backbone_gateway_server_node",
      "Endpoint": "canvzqvhrvyyanoicmgf.supabase.co:51820",
      "AllowedIPs": "0.0.0.0/0",
      "MTU": "1280"
    };
    await _enforceTetheringRestrictions();
    await _executeSystemInterfaceBinding(wireguardConfig);
  }

  Future<void> _provisionWalledGardenTunnel(String sessionKey) async {
    _stopTokenBucket();
    final Map<String, String> wireguardConfig = {
      "PrivateKey": sessionKey,
      "Address": "10.0.0.4/32",
      "DNS": "1.1.1.1",
      "PublicKey": "skynet_isolated_intranet_gateway_node",
      "Endpoint": "canvzqvhrvyyanoicmgf.supabase.co:51820",
      "AllowedIPs": "104.21.19.100/32, 172.67.140.210/32, 10.0.0.0/8", 
      "PersistentKeepalive": "15"
    };
    await _executeSystemInterfaceBinding(wireguardConfig);
  }

  Future<void> _enforceTetheringRestrictions() async {
    if (Platform.isAndroid) {
      await _executeSystemShellPayload("ndc ipfwd disable tethering");
    }
  }

  void _startTokenBucketAlgorithm(double maxMbps) {
    _stopTokenBucket();
    final double bytesPerSecond = maxMbps * 125000.0;
    _bucketTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      _availableTokens += bytesPerSecond * 0.1;
      if (_availableTokens > _maxBucketCapacity) {
        _availableTokens = _maxBucketCapacity;
      }
    });
  }

  void _stopTokenBucket() {
    _bucketTimer?.cancel();
    _bucketTimer = null;
  }

  bool consumeTokensForPacket(int packetSizeBytes) {
    if (_bucketTimer == null) return true; 
    if (_availableTokens >= packetSizeBytes) {
      _availableTokens -= packetSizeBytes;
      return true;
    }
    return false; 
  }

  Future<void> _executeSystemInterfaceBinding(Map<String, String> config) async {
    _isConnected = true;
    connectionStatusNotifier.value = "Connected";
  }

  Future<void> terminateTunnelContext() async {
    _stopTokenBucket();
    _ephemeralKey = null;
    _isConnected = false;
    connectionStatusNotifier.value = "Disconnected";
    await _flushInterfaceRoutingTables();
  }

  Future<void> _flushInterfaceRoutingTables() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _executeSystemShellPayload(String command) async {
    try {
      if (Platform.isAndroid) {
        await Process.run('sh', ['-c', command]);
      }
    } catch (_) {}
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _stopTokenBucket();
  }
}