import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:dio/dio.dart';

class SkyNetPlan2Page extends StatefulWidget {
  const SkyNetPlan2Page({Key? key}) : super(key: key);

  @override
  State<SkyNetPlan2Page> createState() => _SkyNetPlan2PageState();
}

class _SkyNetPlan2PageState extends State<SkyNetPlan2Page> {
  late Box _dbBox;
  final Dio _dio = Dio();

  double _walletBalance = 0.0;
  String _userUuid = "";
  String _userPin = "1234";
  String _referralLink = "https://skynetwifi.pages.dev/ref/haruna";
  String _referralCode = "SKY-HARUNA-2026";

  final List<Map<String, dynamic>> _plan2Catalog = [];
  String? _selectedPlanId;
  double _selectedPlanCost = 0.0;
  bool _isProcessing = false;

  final List<TextEditingController> _pinControllers = List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _pinFocusNodes = List.generate(4, (_) => FocusNode());
  final List<String?> _pinValidationStates = List.generate(4, (_) => null);

  @override
  void initState() {
    super.initState();
    _loadHiveDatabaseAssets();
    _parsePlan2Schematics();
  }

  void _loadHiveDatabaseAssets() {
    _dbBox = Hive.box('user_profiles_box');
    final profile = Map<String, dynamic>.from(_dbBox.get('profile_data', defaultValue: <String, dynamic>{}));
    
    setState(() {
      _walletBalance = double.tryParse(profile['wallet_balance']?.toString() ?? '5000.00') ?? 5000.00;
      _userUuid = profile['uuid'] ?? 'usr_node_9921';
      _userPin = profile['transaction_pin'] ?? '1234';
      _referralLink = profile['referral_link'] ?? 'https://skynetwifi.pages.dev/ref/haruna';
      _referralCode = profile['referral_code'] ?? 'SKY-HARUNA-2026';
    });
  }

  void _parsePlan2Schematics() {
    // Attempt parsing from pricing_plans inside lib/db.dart structure context
    final dynamic rawPlans = _dbBox.get('pricing_plans');
    List<Map<String, dynamic>> temporaryList = [];

    if (rawPlans != null) {
      final Map<dynamic, dynamic> plansMap = Map<dynamic, dynamic>.from(rawPlans);
      plansMap.forEach((key, value) {
        final String planId = key.toString();
        if (planId.startsWith('plan_2_')) {
          temporaryList.add({
            "id": planId,
            ...Map<String, dynamic>.from(value)
          });
        }
      });
    }

    // Production Fallback parameters if database catalog yields empty results
    if (temporaryList.isEmpty) {
      temporaryList = [
        {
          "id": "plan_2_1",
          "name": "Standard Access 1",
          "cost": 1000.0,
          "speed": "10 Mbps",
          "duration": "1 Week",
          "limits": "All Social Networks, SD Streaming"
        },
        {
          "id": "plan_2_2",
          "name": "Premium Tier 2",
          "cost": 3500.0,
          "speed": "30 Mbps",
          "duration": "1 Month",
          "limits": "All Social Networks, TV Streaming, HD Videos"
        },
        {
          "id": "plan_2_3",
          "name": "SkyNet Ultra Extreme",
          "cost": 8000.0,
          "speed": "50+ Mbps",
          "duration": "1 Month",
          "limits": "Unrestricted Pipeline, 4K Broadcast, Zero Throttle"
        }
      ];
    }

    // Sort by cost sequentially
    temporaryList.sort((a, b) => (a['cost'] as double).compareTo(b['cost'] as double));
    setState(() {
      _plan2Catalog.addAll(temporaryList);
    });
  }

  void _validatePinCellDigit(int index, String digit) {
    if (digit.isEmpty) {
      setState(() => _pinValidationStates[index] = null);
      return;
    }
    if (digit == _userPin[index]) {
      setState(() => _pinValidationStates[index] = "valid");
      if (index < 3) {
        _pinFocusNodes[index + 1].requestFocus();
      }
    } else {
      setState(() => _pinValidationStates[index] = "invalid");
    }
  }

  bool _evaluateAbsoluteSubmissionCriteria() {
    if (_selectedPlanId == null || _selectedPlanCost > _walletBalance) return false;
    for (var validationState in _pinValidationStates) {
      if (validationState != "valid") return false;
    }
    return true;
  }

  Future<void> _executeSpeedPlanActivation() async {
    setState(() => _isProcessing = true);
    _triggerLoadingOverlayAnimation();

    try {
      final response = await _dio.post(
        'https://skynetwifi.pages.dev/api/plan2',
        data: {
          'uuid': _userUuid,
          'ip_address': '192.168.8.1',
          'package_id': _selectedPlanId,
          'cost_deduction': _selectedPlanCost
        },
      );

      Navigator.pop(context); // Tear down loading layer framework

      if (response.statusCode == 200 && response.data['success'] == true) {
        final double recalculatedBalance = _walletBalance - _selectedPlanCost;
        
        final profile = Map<String, dynamic>.from(_dbBox.get('profile_data', defaultValue: {}));
        profile['wallet_balance'] = recalculatedBalance;
        profile['active_speed_tier'] = _selectedPlanId;
        await _dbBox.put('profile_data', profile);

        setState(() {
          _walletBalance = recalculatedBalance;
          _isProcessing = false;
          _selectedPlanId = null;
          for (var ctrl in _pinControllers) {
            ctrl.clear();
          }
          _pinValidationStates.fillRange(0, 4, null);
        });

        _displayFloatingNotificationCard("Success! Speed Plan Active. Local QoS allocation pipeline updated.", isError: false);
        
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted && Navigator.canPop(context)) Navigator.pop(context);
        });
      } else {
        setState(() => _isProcessing = false);
        _displayFloatingNotificationCard(response.data['error'] ?? "Intranet provisioning refusal payload returned.");
      }
    } catch (_) {
      Navigator.pop(context);
      setState(() => _isProcessing = false);
      _displayFloatingNotificationCard("Asynchronous backend loop timeout. Ensure local network link integrity.");
    }
  }

  void _triggerLoadingOverlayAnimation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Container(
        color: Colors.black.withOpacity(0.88),
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00296B)),
          ),
        ),
      ),
    );
  }

  void _displayFloatingNotificationCard(String feedback, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        backgroundColor: isError ? const Color(0xFF151515) : const Color(0xFF00296B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
        content: Row(
          children: [
            Icon(isError ? Icons.bolt_toggle_off : Icons.bolt, color: Colors.white),
            SizedBox(width: 10.w),
            Expanded(
              child: Text(
                feedback,
                style: TextStyle(color: Colors.white, fontSize: 12.sp, fontWeight: FontWeight.w400),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _copyToClipboardWorkspace(String data, String logLabel) {
    Clipboard.setData(ClipboardData(text: data));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF00296B),
        behavior: SnackBarBehavior.floating,
        content: Text("Copied $logLabel securely to clip stack."),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 690),
      minTextAdapt: true,
      builder: (context, child) {
        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FB),
          appBar: AppBar(
            backgroundColor: const Color(0xFF00296B),
            elevation: 0,
            title: Text("SkyNet Premium Access Speed Matrix", style: TextStyle(fontSize: 13.sp, color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              bool isWideScreen = constraints.maxWidth > 600;
              return Stack(
                children: [
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.1,
                      child: Center(
                        child: Image.asset(
                          "assets/images/logo.png",
                          width: 250.r,
                          height: 250.r,
                          errorBuilder: (c, o, s) => const Icon(Icons.speed, size: 90, color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    child: isWideScreen ? _buildSplitDashboardPane() : _buildVerticalFlowLayout(),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildVerticalFlowLayout() {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _compileInvertedLayoutStack(isDesktop: false),
      ),
    );
  }

  Widget _buildSplitDashboardPane() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(14.w),
            child: Column(
              children: [
                _buildReferralRewardModuleCard(),
                SizedBox(height: 12.h),
                _buildSystemStatusWalletCard(),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1, color: Colors.black12),
        Expanded(
          flex: 6,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(14.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Available Bandwidth Profiles", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: const Color(0xFF00296B))),
                SizedBox(height: 10.h),
                _buildDynamicPlanSchematicParserGrid(),
                SizedBox(height: 14.h),
                _buildSecurityFormBlock(),
                SizedBox(height: 18.h),
                _buildActivationTriggerButton(),
              ],
            ),
          ),
        )
      ],
    );
  }

  List<Widget> _compileInvertedLayoutStack({required bool isDesktop}) {
    return [
      _buildReferralRewardModuleCard(), // Prominent Top Placement Enforced
      SizedBox(height: 14.h),
      _buildSystemStatusWalletCard(),
      SizedBox(height: 16.h),
      Text("Select High-Speed Subscription Tier", style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: const Color(0xFF00296B))),
      SizedBox(height: 10.h),
      _buildDynamicPlanSchematicParserGrid(),
      SizedBox(height: 16.h),
      _buildSecurityFormBlock(),
      SizedBox(height: 16.h),
      _buildActivationTriggerButton(),
    ];
  }

  Widget _buildReferralRewardModuleCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.all(14.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const FaIcon(FontAwesomeIcons.gift, color: Color(0xFF00296B), size: 16),
                SizedBox(width: 8.w),
                Text("Invite Friends & Secure Bonus Rewards", style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: const Color(0xFF00296B))),
              ],
            ),
            SizedBox(height: 8.h),
            Text(
              "Invite your network connections to SkyNet WiFi! Earn an instant ₦200 wallet reward plus 2 days of unrestricted high-speed internet access completely free once they verify.",
              style: TextStyle(fontSize: 11.sp, color: Colors.black87, height: 1.45),
            ),
            SizedBox(height: 12.h),
            _buildClipboardHorizontalRowBar(title: "Referral Link Node", dataString: _referralLink),
            SizedBox(height: 10.h),
            _buildClipboardHorizontalRowBar(title: "Referral Token Code", dataString: _referralCode),
          ],
        ),
      ),
    );
  }

  Widget _buildClipboardHorizontalRowBar({required String title, required String dataString}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: 10.sp, color: Colors.grey, fontWeight: FontWeight.w500)),
        SizedBox(height: 4.h),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
          decoration: BoxDecoration(color: const Color(0xFFF1F3F7), borderRadius: BorderRadius.circular(6.r), border: Border.all(color: Colors.black12)),
          child: Row(
            children: [
              Expanded(
                child: Text(dataString, style: TextStyle(fontSize: 11.sp, fontFamily: 'monospace', color: Colors.black87), overflow: TextOverflow.ellipsis),
              ),
              SizedBox(width: 6.w),
              GestureDetector(
                onTap: () => _copyToClipboardWorkspace(dataString, title),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.h),
                  decoration: BoxDecoration(color: const Color(0xFF00296B), borderRadius: BorderRadius.circular(4.r)),
                  child: Row(
                    children: [
                      const FaIcon(FontAwesomeIcons.copy, size: 9, color: Colors.white),
                      SizedBox(width: 4.w),
                      Text("Copy", style: TextStyle(color: Colors.white, fontSize: 10.sp, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSystemStatusWalletCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00296B), Color(0xFF003F88)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10.r),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6.r, offset: const Offset(0, 3))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("ACCOUNT LEDGER LIQUID BALANCE", style: TextStyle(color: Colors.white70, fontSize: 9.sp, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              SizedBox(height: 4.h),
              Text("₦ ${_walletBalance.toStringAsFixed(2)}", style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.bold)),
            ],
          ),
          const FaIcon(FontAwesomeIcons.wallet, color: Colors.white30, size: 24),
        ],
      ),
    );
  }

  Widget _buildDynamicPlanSchematicParserGrid() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _plan2Catalog.length,
      separatorBuilder: (context, index) => SizedBox(height: 10.h),
      itemBuilder: (context, index) {
        final plan = _plan2Catalog[index];
        bool isSelected = _selectedPlanId == plan['id'];

        return InkWell(
          onTap: () {
            setState(() {
              _selectedPlanId = plan['id'];
              _selectedPlanCost = plan['cost'];
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF00296B).withOpacity(0.04) : Colors.white,
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: isSelected ? const Color(0xFF00296B) : Colors.black12, width: isSelected ? 1.5 : 1.0),
              boxShadow: isSelected ? [BoxShadow(color: Colors.black12, blurRadius: 4.r)] : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(plan['name'], style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: isSelected ? const Color(0xFF00296B) : Colors.black87)),
                          const Spacer(),
                          Text("₦ ${plan['cost'].toStringAsFixed(0)}", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.black, color: const Color(0xFF00296B))),
                        ],
                      ),
                      SizedBox(height: 6.h),
                      Row(
                        children: [
                          _buildMetadataBadge(icon: FontAwesomeIcons.gaugeHigh, text: plan['speed'], color: Colors.blue),
                          SizedBox(width: 8.w),
                          _buildMetadataBadge(icon: FontAwesomeIcons.clock, text: plan['duration'], color: Colors.orange),
                        ],
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        "Access Allocation: ${plan['limits']}",
                        style: TextStyle(fontSize: 11.sp, color: Colors.black54, fontStyle: FontStyle.italic),
                      )
                    ],
                  ),
                ),
                SizedBox(width: 10.w),
                Container(
                  width: 20.r,
                  height: 20.r,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: isSelected ? const Color(0xFF00296B) : Colors.black26, width: 2),
                    color: isSelected ? const Color(0xFF00296B) : Colors.transparent,
                  ),
                  child: isSelected ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetadataBadge({required IconData icon, required String text, required Color color}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4.r)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(icon, size: 9, color: color),
          SizedBox(width: 4.w),
          Text(text, style: TextStyle(fontSize: 10.sp, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSecurityFormBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Transaction Verification PIN", style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold)),
        SizedBox(height: 8.h),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(4, (index) {
            String? verificationState = _pinValidationStates[index];
            return SizedBox(
              width: 70.w,
              child: Column(
                children: [
                  Container(
                    height: 14.h,
                    alignment: Alignment.center,
                    child: verificationState == "valid"
                        ? const Icon(Icons.check, color: Colors.green, size: 14)
                        : (verificationState == "invalid" ? const Icon(Icons.close, color: Colors.red, size: 14) : null),
                  ),
                  SizedBox(height: 4.h),
                  TextField(
                    controller: _pinControllers[index],
                    focusNode: _pinFocusNodes[index],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    obscureText: true,
                    maxLength: 1,
                    style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      counterText: "",
                      contentPadding: EdgeInsets.symmetric(vertical: 8.h),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6.r)),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: verificationState == "valid" ? Colors.green : (verificationState == "invalid" ? Colors.red : const Color(0xFF00296B))),
                      ),
                    ),
                    onChanged: (val) => _validatePinCellDigit(index, val),
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildActivationTriggerButton() {
    bool isAuthorized = _evaluateAbsoluteSubmissionCriteria() && !_isProcessing;
    if (!isAuthorized) return const SizedBox.shrink();

    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF00296B),
        minimumSize: Size(double.infinity, 45.h),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
      ),
      onPressed: _executeSpeedPlanActivation,
      icon: const FaIcon(FontAwesomeIcons.bolt, size: 14, color: Colors.white),
      label: Text(
        "Activate Speed Plan (₦ ${_selectedPlanCost.toStringAsFixed(0)})",
        style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  void dispose() {
    for (var ctrl in _pinControllers) {
      ctrl.dispose();
    }
    for (var fn in _pinFocusNodes) {
      fn.dispose();
    }
    super.dispose();
  }
}