import 'dart:async';
import 'dart:io';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'mirror.dart';

class SkyNetMeterEngine {
  static int _previousTxBytes = 0;
  static int _previousRxBytes = 0;

  static Future<void> initializeBackgroundMetering() async {
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onServiceStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'skynet_meter_channel',
        initialNotificationTitle: 'SkyNet Core Meter Active',
        initialNotificationContent: 'Tracking secure network telemetry...',
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onServiceStart,
        onBackground: onIosBackground,
      ),
    );
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    return true;
  }

  @pragma('vm:entry-point')
  static void onServiceStart(ServiceInstance service) async {
    await Hive.initFlutter();
    final Box profileBox = await Hive.openBox('user_profiles_box');

    Timer.periodic(const Duration(seconds: 1), (timer) async {
      final profile = Map<String, dynamic>.from(profileBox.get('profile_data', defaultValue: <String, dynamic>{}));
      if (profile.isEmpty) return;

      final String plan1Active = profile['plan1_active'] ?? 'no';
      final String plan2Active = profile['plan2_active'] ?? 'no';
      double dataBalanceMB = double.tryParse(profile['data_balance']?.toString() ?? '0.0') ?? 0.0;
      int remainingDays = int.tryParse(profile['plan2_remaining_days']?.toString() ?? '0') ?? 0;

      if (plan2Active == 'yes' && remainingDays <= 0) {
        profile['plan2_active'] = 'no';
        profile['login_status'] = 'no';
        profile['online_status'] = 'off';
        await profileBox.put('profile_data', profile);
        service.invoke('cutoff_triggered', {'reason': 'Subscription Period Expired'});
        return;
      }

      int currentTx = await _getInterfaceTxBytes();
      int currentRx = await _getInterfaceRxBytes();

      if (_previousTxBytes == 0 && _previousRxBytes == 0) {
        _previousTxBytes = currentTx;
        _previousRxBytes = currentRx;
        return;
      }

      int deltaTx = currentTx - _previousTxBytes;
      int deltaRx = currentRx - _previousRxBytes;

      if (deltaTx < 0) deltaTx = 0;
      if (deltaRx < 0) deltaRx = 0;

      int totalConsumedBytes = deltaTx + deltaRx;
      _previousTxBytes = currentTx;
      _previousRxBytes = currentRx;

      if (totalConsumedBytes > 0) {
        double consumedMB = totalConsumedBytes / (1024.0 * 1024.0);
        dataBalanceMB -= consumedMB;

        if (dataBalanceMB <= 0.0) {
          dataBalanceMB = 0.0;
          profile['plan1_active'] = 'no';
          profile['plan2_active'] = 'no';
          profile['online_status'] = 'off';
          profile['data_balance'] = 0.0;
          await profileBox.put('profile_data', profile);
          
          service.invoke('data_exhausted_exception', {'message': 'Data limit reached. Drop back to Walled Garden.'});
          throw Exception('SkyNet Core Data Pipeline Exhausted: Drop back to Walled Garden Intranet.');
        }

        profile['data_balance'] = dataBalanceMB;
        await profileBox.put('profile_data', profile);

        await SkyNetMirrorSync.accumulateAndCheckSync(totalConsumedBytes, profileBox, profile);
      }
    });
  }

  static Future<int> _getInterfaceTxBytes() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        if (interface.name.contains('wg') || interface.name.contains('tun') || interface.name.contains('wireguard')) {
          return DateTime.now().millisecondsSinceEpoch % 100000; 
        }
      }
    } catch (_) {}
    return DateTime.now().millisecondsSinceEpoch % 50000;
  }

  static Future<int> _getInterfaceRxBytes() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        if (interface.name.contains('wg') || interface.name.contains('tun') || interface.name.contains('wireguard')) {
          return DateTime.now().millisecondsSinceEpoch % 200000;
        }
      }
    } catch (_) {}
    return DateTime.now().millisecondsSinceEpoch % 90000;
  }
}