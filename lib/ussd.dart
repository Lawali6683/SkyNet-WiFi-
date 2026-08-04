import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:system_alert_window/system_alert_window.dart';
import 'package:dio/dio.dart';

class SkyNetUssdInterceptor {
  static const MethodChannel _callChannel = MethodChannel('com.skynetwifi.network/ussd_intercept');
  static const MethodChannel _smsChannel = MethodChannel('com.skynetwifi.network/mock_sms');
  
  static final SkyNetUssdInterceptor _instance = SkyNetUssdInterceptor._internal();
  factory SkyNetUssdInterceptor() => _instance;
  SkyNetUssdInterceptor._internal();

  late Box walletBox;
  late Box subscriptionBox;
  late Box profileBox;
  
  final Dio _dio = Dio();
  String _currentMenuState = "MAIN";

  Future<void> initializeUssdEngine() async {
    walletBox = Hive.box('user_wallet_box');
    subscriptionBox = Hive.box('user_subscriptions_box');
    profileBox = Hive.box('user_profiles_box');
    
    await SystemAlertWindow.requestPermissions;
    
    _callChannel.setMethodCallHandler((call) async {
      if (call.method == "onOutgoingCall") {
        final String dialingString = call.arguments.toString().trim();
        if (dialingString == "#221#" || dialingString == "#111#" || dialingString == "#112#" || dialingString == "#113#") {
          _launchDialogueInterface();
          return true; 
        }
      }
      return false;
    });
  }

  void _launchDialogueInterface() {
    _currentMenuState = "MAIN";
    SystemWindowHeader header = SystemWindowHeader(
      title: SystemWindowText(text: "SkyNet WiFi Dialogue Window", fontSize: 16, color: SystemWindowColor.toHex(Colors.white), fontWeight: FontWeight.BOLD),
      subTitle: SystemWindowText(text: "Welcome to SkyNet WiFi", fontSize: 12, color: SystemWindowColor.toHex(Colors.white70)),
      decoration: SystemWindowDecoration(startColor: SystemWindowColor.toHex(const Color(0xFF0D47A1))),
    );

    SystemWindowBody body = SystemWindowBody(
      rows: [
        EachRow(
          columns: [
            EachColumn(
              text: SystemWindowText(
                text: "1 check account balance\n2 check data balance\n3 show my account wallet Number\n4 buy data GB plan\n5 buy WiFi access MBPS",
                fontSize: 14,
                color: SystemWindowColor.toHex(Colors.black87),
              ),
            ),
          ],
        ),
        EachRow(
          columns: [
            EachColumn(
              input: SystemWindowInput(
                hint: "Enter selection option",
                fontSize: 14,
                inputType: TextInputType.number,
                showBorder: true,
              ),
            ),
          ],
        ),
      ],
    );

    SystemWindowFooter footer = SystemWindowFooter(
      buttons: [
        SystemWindowButton(
          text: SystemWindowText(text: "Cancel", fontSize: 12, color: SystemWindowColor.toHex(Colors.red)),
          tag: "btn_cancel",
        ),
        SystemWindowButton(
          text: SystemWindowText(text: "Send/OK", fontSize: 12, color: SystemWindowColor.toHex(Colors.green)),
          tag: "btn_send_main",
        ),
      ],
    );

    SystemAlertWindow.showSystemWindow(
      header: header,
      body: body,
      footer: footer,
      margin: SystemWindowMargin(left: 16, right: 16, top: 100, bottom: 0),
      gravity: SystemWindowGravity.TOP,
    );

    SystemAlertWindow.registerOnClickListener((tag) {
      if (tag == "btn_cancel") {
        SystemAlertWindow.closeSystemWindow();
      } else if (tag == "btn_send_main") {
        _handleMainNavigationSelection("1"); 
      }
    });
  }

  void _handleMainNavigationSelection(String input) {
    switch (input) {
      case "1":
        final double walletBalance = walletBox.get('balance', defaultValue: 0.0);
        _renderAlertWindowResponse(
          "Wallet Balance",
          "Your SkyNet WiFi balance is ₦$walletBalance",
          () {
            SystemAlertWindow.closeSystemWindow();
            _dispatchMockSms("Dear Customer, your SkyNet WiFi wallet balance is ₦$walletBalance. Thank you for choosing SkyNet!");
          },
        );
        break;

      case "2":
        final String activePlanType = subscriptionBox.get('active_plan_type', defaultValue: 'none');
        String infoMessage = "You do not have any active Plan 1 or Plan 2 subscription.";
        
        if (activePlanType == 'plan2') {
          final int remainingDays = subscriptionBox.get('days_remaining', defaultValue: 0);
          infoMessage = "- Plan 2 (MBPS): $remainingDays Days Remaining";
        } else if (activePlanType == 'plan1') {
          final double remainingGb = subscriptionBox.get('gb_remaining', defaultValue: 0.0);
          infoMessage = "Active Plans:\n- Plan 1 (GB): $remainingGb GB Remaining";
        }
        
        _renderAlertWindowResponse(
          "Data Balance",
          infoMessage,
          () {
            SystemAlertWindow.closeSystemWindow();
            _dispatchMockSms("SkyNet Status Info:\n$infoMessage");
          },
        );
        break;

      case "3":
        final profile = Map<String, dynamic>.from(profileBox.get('profile_data', defaultValue: {}));
        final String walletNumber = profile['wallet_number'] ?? 'Not Configured';
        final String infoMessage = "Your SkyNet WiFi Wallet Number is: $walletNumber Wema Bank. Use this to fund your wallet.";
        
        _renderAlertWindowResponse(
          "Wallet Profile",
          infoMessage,
          () {
            SystemAlertWindow.closeSystemWindow();
            _dispatchMockSms(infoMessage);
          },
        );
        break;

      case "4":
        _renderPlan1SubMenu();
        break;

      case "5":
        _renderPlan2SubMenu();
        break;
    }
  }

  void _renderPlan1SubMenu() {
    _currentMenuState = "PLAN1";
    SystemWindowHeader header = SystemWindowHeader(
      title: SystemWindowText(text: "Buy Data GB Plan (Plan 1)", fontSize: 14, color: SystemWindowColor.toHex(Colors.white)),
      decoration: SystemWindowDecoration(startColor: SystemWindowColor.toHex(const Color(0xFF0D47A1))),
    );

    SystemWindowBody body = SystemWindowBody(
      rows: [
        EachRow(
          columns: [
            EachColumn(
              text: SystemWindowText(
                text: "1: 500 MB (₦100)\n2: 1GB (₦150)\n3: 5GB (₦1,000)\n4: 10GB (₦1,800)\n5: 20GB (₦3,200)\n6: Input GB you want",
                fontSize: 13,
                color: SystemWindowColor.toHex(Colors.black87),
              ),
            ),
          ],
        ),
        EachRow(
          columns: [
            EachColumn(
              input: SystemWindowInput(hint: "Select option", fontSize: 14, inputType: TextInputType.number, showBorder: true),
            ),
          ],
        ),
      ],
    );

    SystemWindowFooter footer = SystemWindowFooter(
      buttons: [
        SystemWindowButton(text: SystemWindowText(text: "Back", fontSize: 12, color: SystemWindowColor.toHex(Colors.grey)), tag: "btn_back"),
        SystemWindowButton(text: SystemWindowText(text: "Send/OK", fontSize: 12, color: SystemWindowColor.toHex(Colors.green)), tag: "btn_send_plan1"),
      ],
    );

    SystemAlertWindow.showSystemWindow(header: header, body: body, footer: footer);
  }

  void _renderPlan2SubMenu() {
    _currentMenuState = "PLAN2";
    SystemWindowHeader header = SystemWindowHeader(
      title: SystemWindowText(text: "Buy Access Speed (Plan 2)", fontSize: 14, color: SystemWindowColor.toHex(Colors.white)),
      decoration: SystemWindowDecoration(startColor: SystemWindowColor.toHex(const Color(0xFF0D47A1))),
    );

    SystemWindowBody body = SystemWindowBody(
      rows: [
        EachRow(
          columns: [
            EachColumn(
              text: SystemWindowText(
                text: "1: 20MBPS (7 Days) - ₦1,500\n2: 5MBPS (30 Days) - ₦5,000",
                fontSize: 13,
                color: SystemWindowColor.toHex(Colors.black87),
              ),
            ),
          ],
        ),
        EachRow(
          columns: [
            EachColumn(
              input: SystemWindowInput(hint: "Select option", fontSize: 14, inputType: TextInputType.number, showBorder: true),
            ),
          ],
        ),
      ],
    );

    SystemWindowFooter footer = SystemWindowFooter(
      buttons: [
        SystemWindowButton(text: SystemWindowText(text: "Back", fontSize: 12, color: SystemWindowColor.toHex(Colors.grey)), tag: "btn_back"),
        SystemWindowButton(text: SystemWindowText(text: "Send/OK", fontSize: 12, color: SystemWindowColor.toHex(Colors.green)), tag: "btn_send_plan2"),
      ],
    );

    SystemAlertWindow.showSystemWindow(header: header, body: body, footer: footer);
  }

  void _renderAlertWindowResponse(String title, String message, Function onConfirm) {
    SystemWindowHeader header = SystemWindowHeader(
      title: SystemWindowText(text: title, fontSize: 14, color: SystemWindowColor.toHex(Colors.white)),
      decoration: SystemWindowDecoration(startColor: SystemWindowColor.toHex(const Color(0xFF0D47A1))),
    );

    SystemWindowBody body = SystemWindowBody(
      rows: [
        EachRow(
          columns: [
            EachColumn(text: SystemWindowText(text: message, fontSize: 14, color: SystemWindowColor.toHex(Colors.black87))),
          ],
        ),
      ],
    );

    SystemWindowFooter footer = SystemWindowFooter(
      buttons: [
        SystemWindowButton(text: SystemWindowText(text: "OK", fontSize: 12, color: SystemWindowColor.toHex(Colors.green)), tag: "btn_alert_ok"),
      ],
    );

    SystemAlertWindow.showSystemWindow(header: header, body: body, footer: footer);
  }

  Future<void> _executePurchaseCycle(String planType, double cost, String packageId) async {
    final double currentBalance = walletBox.get('balance', defaultValue: 0.0);
    
    if (currentBalance < cost) {
      _renderAlertWindowResponse("Purchase Failed", "Purchase Failed! Your wallet balance is insufficient.", () {
        SystemAlertWindow.closeSystemWindow();
      });
      return;
    }

    final profile = Map<String, dynamic>.from(profileBox.get('profile_data', defaultValue: {}));
    final String uuid = profile['id'] ?? '';
    final String ipAddress = profile['ip_address'] ?? '0.0.0.0';

    final Map<String, dynamic> transactionPayload = {
      'id': uuid,
      'ip_address': ipAddress,
      'plan_type': planType,
      'package_id': packageId,
      'api_secret': '@haruna66'
    };

    try {
      final response = await _dio.post(
        'https://skynetwifi.pages.dev/api/buydata',
        data: transactionPayload,
        options: Options(headers: {'Content-Type': 'application/json'}),
      );

      if (response.statusCode == 200 && response.data['status'] == 'success') {
        final double postBalance = currentBalance - cost;
        await walletBox.put('balance', postBalance);
        
        _renderAlertWindowResponse("Transaction Success", "Package activated successfully.", () {
          SystemAlertWindow.closeSystemWindow();
          _dispatchMockSms("SkyNet Order Complete: Package $packageId purchased successfully. Account balance: ₦$postBalance.");
        });
      } else {
        _renderAlertWindowResponse("Server System Error", response.data['message'] ?? 'Processing Failure', () {});
      }
    } catch (e) {
      _renderAlertWindowResponse("Gateway Connect Timeout", "Failed to contact edge verification nodes.", () {});
    }
  }

  void _dispatchMockSms(String textContent) {
    _smsChannel.invokeMethod("triggerMockSmsNotification", {"body": textContent, "sender": "SkyNetWiFi"});
  }
}