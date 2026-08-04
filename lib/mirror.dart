import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

class SkyNetMirrorSync {
  static const int syncThresholdBytes = 52428800; 
  static final Dio _dio = Dio();

  static Future<void> accumulateAndCheckSync(int bytesConsumed, Box profileBox, Map<String, dynamic> profile) async {
    int currentDelta = profileBox.get('consumed_delta', defaultValue: 0);
    currentDelta += bytesConsumed;

    if (currentDelta >= syncThresholdBytes) {
      await executeServerSync(currentDelta, profileBox, profile);
    } else {
      await profileBox.put('consumed_delta', currentDelta);
    }
  }

  static Future<void> executeServerSync(int deltaBytes, Box profileBox, Map<String, dynamic> profile) async {
    final String uuid = profile['id'] ?? '';
    const String apiSecret = '@haruna66';

    try {
      final response = await _dio.post(
        'https://skynetwifi.pages.dev/api/mirror',
        data: {
          'id': uuid,
          'api_secret': apiSecret,
          'consumed_delta': deltaBytes,
        },
        options: Options(
          headers: {'Content-Type': 'application/json'},
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200) {
        await profileBox.put('consumed_delta', 0);
      } else if (response.statusCode == 401 || response.statusCode == 404 || response.statusCode == 400) {
        profile['plan1_active'] = 'no';
        profile['plan2_active'] = 'no';
        profile['data_balance'] = 0.0;
        profile['online_status'] = 'off';
        await profileBox.put('profile_data', profile);
        await profileBox.put('consumed_delta', 0);
      }
    } catch (e) {
      await profileBox.put('consumed_delta', deltaBytes);
    }
  }
}