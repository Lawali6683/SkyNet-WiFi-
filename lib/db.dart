import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocalDB {
  static late Box userProfilesBox;
  static late Box pricingPlansBox;
  static late Box wifiPurchasesBox;
  static late Box dataSaleBox;
  static late Box adDataBox;
  static late Box freeDataBox;

  static final ValueNotifier<Map<String, dynamic>> userProfileNotifier = ValueNotifier({});
  static final ValueNotifier<Map<String, dynamic>> pricingPlansNotifier = ValueNotifier({});
  static final ValueNotifier<List<dynamic>> wifiPurchasesNotifier = ValueNotifier([]);
  static final ValueNotifier<List<dynamic>> dataSaleNotifier = ValueNotifier([]);
  static final ValueNotifier<List<Map<String, dynamic>>> adDataNotifier = ValueNotifier([]);
  static final ValueNotifier<Map<String, dynamic>> freeDataNotifier = ValueNotifier({});

  static Future<void> initialize() async {
    await Hive.initFlutter();

    userProfilesBox = await Hive.openBox('user_profiles_box');
    pricingPlansBox = await Hive.openBox('pricing_plans_box');
    wifiPurchasesBox = await Hive.openBox('wifi_purchases_box');
    dataSaleBox = await Hive.openBox('data_sale_box');
    adDataBox = await Hive.openBox('ad_data_box');
    freeDataBox = await Hive.openBox('free_data_box');

    if (freeDataBox.get('free_data_ip') == null) {
      await freeDataBox.put('free_data_ip', '52-skyNetwifi');
    }

    final profileData = userProfilesBox.get('profile_data');
    if (profileData is Map) {
      userProfileNotifier.value = Map<String, dynamic>.from(profileData);
    }

    final plansData = pricingPlansBox.get('plans_data');
    if (plansData is Map) {
      pricingPlansNotifier.value = Map<String, dynamic>.from(plansData);
    }

    final purchasesData = wifiPurchasesBox.get('purchases_data');
    if (purchasesData is List) {
      wifiPurchasesNotifier.value = List.from(purchasesData);
    }

    final salesData = dataSaleBox.get('sales_data');
    if (salesData is List) {
      dataSaleNotifier.value = List.from(salesData);
    }

    final cachedAds = adDataBox.values.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    adDataNotifier.value = cachedAds;

    freeDataNotifier.value = {'free_data_ip': freeDataBox.get('free_data_ip')};

    await Supabase.initialize(
      url: 'https://canvzqvhrvyyanoicmgf.supabase.co',
      anonKey: 'sb_publishable_gKdgmKqcZBCdPVftHbdpxg_TVhvJuWj',
    );
  }

  static dynamic getUserField(String key) {
    final profile = userProfilesBox.get('profile_data', defaultValue: <String, dynamic>{});
    if (profile is Map) {
      return profile[key];
    }
    return null;
  }

  static Future<bool> updateBalanceOptimistic({required double amount, required bool isCredit}) async {
    final profile = Map<String, dynamic>.from(userProfilesBox.get('profile_data', defaultValue: <String, dynamic>{}));
    final double previousBalance = double.tryParse(profile['balance']?.toString() ?? '0.0') ?? 0.0;
    final double newBalance = isCredit ? previousBalance + amount : previousBalance - amount;

    profile['balance'] = newBalance;

    final List notifications = List.from(profile['account_notifications'] ?? []);
    if (isCredit) {
      notifications.add({
        'message': 'You get $amount in your SkyNet WiFi account total $newBalance',
        'unread': true,
      });
    } else {
      notifications.add({
        'message': 'You send $amount in your SkyNet WiFi account remain $newBalance',
        'unread': true,
      });
    }
    profile['account_notifications'] = notifications;

    await userProfilesBox.put('profile_data', profile);
    userProfileNotifier.value = profile;

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await Supabase.instance.client
            .from('profiles')
            .update({
              'balance': newBalance,
              'account_notifications': notifications,
            })
            .eq('id', userId);
        return true;
      }
      throw Exception();
    } catch (_) {
      profile['balance'] = previousBalance;
      if (notifications.isNotEmpty) {
        notifications.removeLast();
      }
      profile['account_notifications'] = notifications;
      await userProfilesBox.put('profile_data', profile);
      userProfileNotifier.value = profile;
      return false;
    }
  }

  static Future<bool> updateDataBalanceOptimistic({required double dataAmount, required bool isCredit}) async {
    final profile = Map<String, dynamic>.from(userProfilesBox.get('profile_data', defaultValue: <String, dynamic>{}));
    final double previousDataBalance = double.tryParse(profile['data_balance']?.toString() ?? '0.0') ?? 0.0;
    final double newDataBalance = isCredit ? previousDataBalance + dataAmount : previousDataBalance - dataAmount;

    profile['data_balance'] = newDataBalance;

    await userProfilesBox.put('profile_data', profile);
    userProfileNotifier.value = profile;

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await Supabase.instance.client
            .from('profiles')
            .update({'data_balance': newDataBalance})
            .eq('id', userId);
        return true;
      }
      throw Exception();
    } catch (_) {
      profile['data_balance'] = previousDataBalance;
      await userProfilesBox.put('profile_data', profile);
      userProfileNotifier.value = profile;
      return false;
    }
  }

  static Future<void> rotateAdvertisingCache(List<Map<String, dynamic>> remoteAds) async {
    bool holdsNewAd = false;
    final localKeys = adDataBox.keys.map((k) => k.toString()).toSet();

    for (var ad in remoteAds) {
      final String adId = ad['id']?.toString() ?? '';
      if (!localKeys.contains(adId)) {
        holdsNewAd = true;
        break;
      }
    }

    if (holdsNewAd) {
      await adDataBox.clear();
      for (var ad in remoteAds) {
        final String adId = ad['id']?.toString() ?? '';
        await adDataBox.put(adId, ad);
      }
      adDataNotifier.value = remoteAds;
    }
  }
}