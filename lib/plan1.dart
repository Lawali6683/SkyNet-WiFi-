import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:dio/dio.dart';

class SkyNetPlan1Page extends StatefulWidget {
  const SkyNetPlan1Page({Key? key}) : super(key: key);

  @override
  State<SkyNetPlan1Page> createState() => _SkyNetPlan1PageState();
}

class _SkyNetPlan1PageState extends State<SkyNetPlan1Page> {
  late Box _dbBox;
  final Dio _dio = Dio();
  
  double _walletBalance = 0.0;
  String _userUuid = "";
  String _userPin = "1234";
  String _referralLink = "https://skynetwifi.pages.dev/ref/haruna";
  String _referralCode = "SKY-HARUNA-2026";
  
  int _basePrice500mb = 100;
  int _basePrice1gb = 150;

  final List<Map<String, dynamic>> _fixedPlans = [];
  int? _selectedPlanIndex;
  bool _isCustomMode = false;
  final TextEditingController _customGbController = TextEditingController();

  final List<TextEditingController> _pinControllers = List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _pinFocusNodes = List.generate(4, (_) => FocusNode());
  final List<String?> _pinValidationStates = List.generate(4, (_) => null);

  double _calculatedCost = 0.0;
  String _selectedVolumeLabel = "";
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadHiveCacheData();
    _buildPlanMatrixCatalog();
  }

  void _loadHiveCacheData() {
    _dbBox = Hive.box('user_profiles_box');
    final profile = Map<String, dynamic>.from(_dbBox.get('profile_data', defaultValue: <String, dynamic>{}));
    final routerConfig = Map<String, dynamic>.from(_dbBox.get('router_config', defaultValue: <String, dynamic>{}));

    setState(() {
      _walletBalance = double.tryParse(profile['wallet_balance']?.toString() ?? '2500.00') ?? 2500.00;
      _userUuid = profile['uuid'] ?? 'usr_node_9921';
      _userPin = profile['transaction_pin'] ?? '1234';
      _referralLink = profile['referral_link'] ?? 'https://skynetwifi.pages.dev/ref/haruna';
      _referralCode = profile['referral_code'] ?? 'SKY-HARUNA-2026';
      
      _basePrice500mb = int.tryParse(routerConfig['price_500mb']?.toString() ?? '100') ?? 100;
      _basePrice1gb = int.tryParse(routerConfig['price_1gb']?.toString() ?? '150') ?? 150;
    });
  }

  void _buildPlanMatrixCatalog() {
    _fixedPlans.addAll([
      {"label": "500 MB", "cost": _basePrice500mb.toDouble(), "size": 0.5},
      {"label": "1 GB", "cost": _basePrice1gb.toDouble(), "size": 1.0},
      {"label": "2 GB", "cost": (_basePrice1gb * 2).toDouble(), "size": 2.0},
      {"label": "3 GB", "cost": (_basePrice1gb * 3).toDouble(), "size": 3.0},
      {"label": "5 GB", "cost": 700.0, "size": 5.0},
      {"label": "10 GB", "cost": 1350.0, "size": 10.0},
    ]);
  }

  void _evaluatePlanSelection(int index) {
    setState(() {
      _isCustomMode = false;
      _selectedPlanIndex = index;
      _calculatedCost = _fixedPlans[index]['cost'];
      _selectedVolumeLabel = _fixedPlans[index]['label'];
    });
  }

  void _evaluateCustomInput(String val) {
    double inputGb = double.tryParse(val) ?? 0.0;
    setState(() {
      _selectedPlanIndex = null;
      _calculatedCost = inputGb * _basePrice1gb;
      _selectedVolumeLabel = "$inputGb GB";
    });
  }

  void _validatePinDigit(int index, String digit) {
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

  bool _verifyAbsolutePurchaseConditions() {
    if (_calculatedCost <= 0 || _calculatedCost > _walletBalance) return false;
    for (var state in _pinValidationStates) {
      if (state != "valid") return false;
    }
    return true;
  }

  Future<void> _executeAtomicTransaction() async {
    setState(() => _isProcessing = true);
    
    _triggerFullScreenLoadingOverlay();

    try {
      final response = await _dio.post(
        'https://skynetwifi.pages.dev/api/plan1',
        data: {
          'uuid': _userUuid,
          'ip_address': '192.168.8.101',
          'data_size': _selectedVolumeLabel,
          'cost': _calculatedCost
        },
      );

      Navigator.pop(context);

      if (response.statusCode == 200 && response.data['success'] == true) {
        final double directNewBalance = _walletBalance - _calculatedCost;
        final profile = Map<String, dynamic>.from(_dbBox.get('profile_data', defaultValue: {}));
        profile['wallet_balance'] = directNewBalance;
        await _dbBox.put('profile_data', profile);

        setState(() {
          _walletBalance = directNewBalance;
          _isProcessing = false;
          _selectedPlanIndex = null;
          _customGbController.clear();
          for (var c in _pinControllers) {
            c.clear();
          }
          _pinValidationStates.fillRange(0, 4, null);
        });

        _showCustomPushNotificationCard("Success! Purchased $_selectedVolumeLabel Data Plan for ₦${_calculatedCost.toStringAsFixed(0)} securely.", isError: false);
      } else {
        setState(() => _isProcessing = false);
        _showCustomPushNotificationCard(response.data['error'] ?? "Transaction pipeline allocation failure.");
      }
    } catch (e) {
      Navigator.pop(context);
      setState(() => _isProcessing = false);
      _showCustomPushNotificationCard("Network connection lost. Please check your interface.");
    }
  }

  void _triggerFullScreenLoadingOverlay() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Container(
        color: Colors.blackDE,
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0D47A1)),
          ),
        ),
      ),
    );
  }

  void _showCustomPushNotificationCard(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        backgroundColor: isError ? const Color(0xFF1A1A1A) : const Color(0xFF0D47A1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white),
            SizedBox(width: 10.w),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: Colors.white, fontSize: 12.sp, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _copyToClipboardWorkspace(String payload, String identifier) {
    Clipboard.setData(ClipboardData(text: payload));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF0D47A1),
        behavior: SnackBarBehavior.floating,
        content: Text("Copied $identifier securely to clipboard context."),
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
          backgroundColor: const Color(0xFFFAFAFA),
          body: LayoutBuilder(
            builder: (context, constraints) {
              bool isDesktop = constraints.maxWidth > 600;
              return Stack(
                children: [
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.1,
                      child: Center(
                        child: Image.asset(
                          "assets/images/logo.png",
                          width: 260.r,
                          height: 260.r,
                          errorBuilder: (c, o, s) => const Icon(Icons.wifi_tethering, size: 100, color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    child: isDesktop ? _buildDesktopGridLayout() : _buildMobileLayout(),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildCoreWorkspaceWidgets(),
      ),
    );
  }

  Widget _buildDesktopGridLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(14.w),
            child: Column(
              children: [
                _buildPremiumGlassmorphicBalanceCard(),
                SizedBox(height: 12.h),
                _buildMarketingTextBanner(),
                SizedBox(height: 12.h),
                _buildReferralWorkspaceCard(),
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
                Text("Select Data Package Threshold", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: const Color(0xFF0D47A1))),
                SizedBox(height: 10.h),
                _buildPlanSelectorMatrixGrid(isDesktop: true),
                SizedBox(height: 14.h),
                _buildAtomicPinAuthenticationForm(),
                SizedBox(height: 20.h),
                _buildSubmitActionBlockButton(),
              ],
            ),
          ),
        )
      ],
    );
  }

  List<Widget> _buildCoreWorkspaceWidgets() {
    return [
      _buildPremiumGlassmorphicBalanceCard(),
      SizedBox(height: 12.h),
      _buildMarketingTextBanner(),
      SizedBox(height: 14.h),
      Text("Select Volume Allocation Tier", style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: const Color(0xFF0D47A1))),
      SizedBox(height: 10.h),
      _buildPlanSelectorMatrixGrid(isDesktop: false),
      SizedBox(height: 16.h),
      _buildAtomicPinAuthenticationForm(),
      SizedBox(height: 16.h),
      _buildSubmitActionBlockButton(),
      SizedBox(height: 16.h),
      _buildReferralWorkspaceCard(),
    ];
  }

  Widget _buildPremiumGlassmorphicBalanceCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF0D47A1).withOpacity(0.85), const Color(0xFF1976D2).withOpacity(0.65)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8.r, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("ACTIVE WALLET INTERFACE LEDGER", style: TextStyle(color: Colors.white70, fontSize: 10.sp, fontWeight: FontWeight.w600, letterSpacing: 1)),
          SizedBox(height: 6.h),
          Text("₦ ${_walletBalance.toStringAsFixed(2)}", style: TextStyle(color: Colors.white, fontSize: 24.sp, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildMarketingTextBanner() {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.08), borderRadius: BorderRadius.circular(8.r), border: Border.all(color: Colors.blue.withOpacity(0.2))),
      child: Text(
        "More high-speed internet, premium reliability, and completely un-expiring data structures. Your volume never turns invalid until consumed! Experience smart network operations for just ₦$_basePrice500mb for 500 MB or ₦$_basePrice1gb per 1 GB block. Deposit into your local wallet to activate now.",
        style: TextStyle(fontSize: 11.sp, color: const Color(0xFF0D47A1), height: 1.45),
      ),
    );
  }

  Widget _buildPlanSelectorMatrixGrid({required bool isDesktop}) {
    return Column(
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _fixedPlans.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isDesktop ? 3 : 2,
            childAspectRatio: 2.6,
            crossAxisSpacing: 8.w,
            mainAxisSpacing: 8.h,
          ),
          itemBuilder: (context, index) {
            final plan = _fixedPlans[index];
            bool isSelected = _selectedPlanIndex == index && !_isCustomMode;
            return InkWell(
              onTap: () => _evaluatePlanSelection(index),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF0D47A1) : Colors.white,
                  borderRadius: BorderRadius.circular(6.r),
                  border: Border.all(color: isSelected ? const Color(0xFF0D47A1) : Colors.black12),
                ),
                padding: EdgeInsets.symmetric(horizontal: 10.w),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(plan['label'], style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black87)),
                        Text("₦ ${plan['cost'].toStringAsFixed(0)}", style: TextStyle(fontSize: 10.sp, color: isSelected ? Colors.white70 : Colors.grey)),
                      ],
                    ),
                    if (isSelected) const Icon(Icons.check_circle, color: Colors.white, size: 16)
                  ],
                ),
              ),
            );
          },
        ),
        SizedBox(height: 8.h),
        InkWell(
          onTap: () {
            setState(() {
              _isCustomMode = true;
              _selectedPlanIndex = null;
              _calculatedCost = 0.0;
              _selectedVolumeLabel = "";
            });
          },
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 10.h),
            decoration: BoxDecoration(
              color: _isCustomMode ? const Color(0xFF0D47A1) : Colors.white,
              borderRadius: BorderRadius.circular(6.r),
              border: Border.all(color: _isCustomMode ? const Color(0xFF0D47A1) : Colors.black12),
            ),
            child: Center(
              child: Text("OTHERS", style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold, color: _isCustomMode ? Colors.white : Colors.black87)),
            ),
          ),
        ),
        if (_isCustomMode) ...[
          SizedBox(height: 10.h),
          TextField(
            controller: _customGbController,
            keyboardType: TextInputType.number,
            onChanged: _evaluateCustomInput,
            decoration: InputDecoration(
              labelText: "Enter Custom Data Volume",
              suffixText: "GB",
              border: const OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
            ),
          )
        ]
      ],
    );
  }

  Widget _buildAtomicPinAuthenticationForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Transaction Verification PIN", style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold)),
        SizedBox(height: 8.h),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(4, (index) {
            String? state = _pinValidationStates[index];
            return SizedBox(
              width: 70.w,
              child: Column(
                children: [
                  Container(
                    height: 16.h,
                    alignment: Alignment.center,
                    child: state == "valid"
                        ? const Icon(Icons.check, color: Colors.green, size: 14)
                        : (state == "invalid" ? const Icon(Icons.close, color: Colors.red, size: 14) : null),
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
                        borderSide: BorderSide(color: state == "valid" ? Colors.green : (state == "invalid" ? Colors.red : const Color(0xFF0D47A1))),
                      ),
                    ),
                    onChanged: (val) => _validatePinDigit(index, val),
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildSubmitActionBlockButton() {
    bool canSubmit = _verifyAbsolutePurchaseConditions() && !_isProcessing;
    if (!canSubmit) return const SizedBox.shrink();

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF0D47A1),
        minimumSize: Size(double.infinity, 44.h),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
      ),
      onPressed: _executeAtomicTransaction,
      child: Text(
        "Submit Purchase (₦ ${_calculatedCost.toStringAsFixed(0)})",
        style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildReferralWorkspaceCard() {
    return Card(
      elevation: 1,
      margin: EdgeInsets.only(top: 10.h),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
      child: Padding(
        padding: EdgeInsets.all(14.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Invite Friends & Secure Bonus Rewards", style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: const Color(0xFF0D47A1))),
            SizedBox(height: 6.h),
            Text(
              "Invite your network connections to SkyNet WiFi! Earn an instant ₦200 wallet reward plus 2 days of unrestricted high-speed internet access completely free once they verify.",
              style: TextStyle(fontSize: 11.sp, color: Colors.black54, height: 1.4),
            ),
            SizedBox(height: 12.h),
            _buildTokenHorizontalShareBar(label: "Referral Link Node", value: _referralLink),
            SizedBox(height: 10.h),
            _buildTokenHorizontalShareBar(label: "Referral Token Code", value: _referralCode),
          ],
        ),
      ),
    );
  }

  Widget _buildTokenHorizontalShareBar({required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10.sp, color: Colors.grey, fontWeight: FontWeight.w500)),
        SizedBox(height: 4.h),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
          decoration: BoxDecoration(color: const Color(0xFFF0F4F8), borderRadius: BorderRadius.circular(6.r), border: Border.all(color: Colors.black12)),
          child: Row(
            children: [
              Expanded(
                child: Text(value, style: TextStyle(fontSize: 11.sp, fontFamily: 'monospace', color: Colors.black87), overflow: TextOverflow.ellipsis),
              ),
              SizedBox(width: 6.w),
              InkWell(
                onTap: () => _copyToClipboardWorkspace(value, label),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(color: const Color(0xFF0D47A1), borderRadius: BorderRadius.circular(4.r)),
                  child: Row(
                    children: [
                      const FaIcon(FontAwesomeIcons.copy, size: 10, color: Colors.white),
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

  @override
  void dispose() {
    for (var c in _pinControllers) {
      c.dispose();
    }
    for (var f in _pinFocusNodes) {
      f.dispose();
    }
    _customGbController.dispose();
    super.dispose();
  }
}