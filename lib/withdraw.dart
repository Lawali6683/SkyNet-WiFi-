import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:dio/dio.dart';

class SkyNetWithdrawPage extends StatefulWidget {
  const SkyNetWithdrawPage({Key? key}) : super(key: key);

  @override
  State<SkyNetWithdrawPage> createState() => _SkyNetWithdrawPageState();
}

class _SkyNetWithdrawPageState extends State<SkyNetWithdrawPage> {
  late Box _dbBox;
  final Dio _dio = Dio();

  double _walletBalance = 0.0;
  String _userUuid = "";
  String _userPin = "1234";

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _accountController = TextEditingController();
  final List<TextEditingController> _pinControllers = List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _pinFocusNodes = List.generate(4, (_) => FocusNode());

  bool _isAmountValid = false;
  double _calculatedTotalCharge = 0.0;

  final List<Map<String, String>> _nigerianBanks = [
    {"name": "Access Bank", "code": "044"},
    {"name": "First Bank of Nigeria", "code": "011"},
    {"name": "GTBank", "code": "058"},
    {"name": "Kuda Bank", "code": "50211"},
    {"name": "Moniepoint MFB", "code": "50515"},
    {"name": "OPay", "code": "999992"},
    {"name": "Palmpay", "code": "999991"},
    {"name": "United Bank for Africa (UBA)", "code": "033"},
    {"name": "Zenith Bank", "code": "057"}
  ];

  String? _selectedBankCode;
  bool _isSearchingAccount = false;
  String? _validatedAccountName;
  String? _accountErrorText;
  final List<String?> _pinValidationStates = List.generate(4, (_) => null);
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadLocalCacheContext();
    _amountController.addListener(_validateRequestedAmount);
    _accountController.addListener(_handleAccountNumberInput);
  }

  void _loadLocalCacheContext() {
    _dbBox = Hive.box('user_profiles_box');
    final profile = Map<String, dynamic>.from(_dbBox.get('profile_data', defaultValue: <String, dynamic>{}));
    setState(() {
      _walletBalance = double.tryParse(profile['wallet_balance']?.toString() ?? '15000.00') ?? 15000.00;
      _userUuid = profile['uuid'] ?? 'usr_reseller_77a';
      _userPin = profile['transaction_pin'] ?? '1234';
    });
  }

  void _validateRequestedAmount() {
    final text = _amountController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _isAmountValid = false;
        _calculatedTotalCharge = 0.0;
      });
      return;
    }
    final inputAmount = double.tryParse(text) ?? 0.0;
    final totalCharge = inputAmount + (inputAmount * 0.01);
    setState(() {
      _calculatedTotalCharge = totalCharge;
      _isAmountValid = inputAmount > 0 && totalCharge <= _walletBalance;
    });
  }

  void _handleAccountNumberInput() {
    final text = _accountController.text.trim();
    if (text.length == 10 && _selectedBankCode != null) {
      _executeAccountLookupDaemon(text, _selectedBankCode!);
    } else {
      if (_validatedAccountName != null || _accountErrorText != null) {
        setState(() {
          _validatedAccountName = null;
          _accountErrorText = null;
          _resetPinMatrix();
        });
      }
    }
  }

  Future<void> _executeAccountLookupDaemon(String accountNum, String bankCode) async {
    setState(() {
      _isSearchingAccount = true;
      _validatedAccountName = null;
      _accountErrorText = null;
      _resetPinMatrix();
    });

    try {
      final response = await _dio.post(
        'https://skynetwifi.pages.dev/api/withdraw',
        data: {
          "bank_code": bankCode,
          "account_number": accountNum,
          "action": "validate"
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        if (response.data['success'] == true) {
          setState(() {
            _validatedAccountName = response.data['account_name'];
            _isSearchingAccount = false;
          });
        } else {
          setState(() {
            _accountErrorText = response.data['message'] ?? "Account resolution rejected.";
            _isSearchingAccount = false;
          });
        }
      }
    } catch (_) {
      setState(() {
        _accountErrorText = "Failed to communicate with account daemon.";
        _isSearchingAccount = false;
      });
    }
  }

  void _validatePinIndexDigit(int index, String value) {
    if (value.isEmpty) {
      setState(() => _pinValidationStates[index] = null);
      return;
    }
    if (value == _userPin[index]) {
      setState(() => _pinValidationStates[index] = "valid");
      if (index < 3) {
        _pinFocusNodes[index + 1].requestFocus();
      }
    } else {
      setState(() => _pinValidationStates[index] = "invalid");
    }
  }

  void _resetPinMatrix() {
    for (var c in _pinControllers) {
      c.clear();
    }
    _pinValidationStates.fillRange(0, 4, null);
  }

  bool _evaluateAbsoluteComplianceMetrics() {
    if (!_isAmountValid || _validatedAccountName == null) return false;
    for (var state in _pinValidationStates) {
      if (state != "valid") return false;
    }
    return true;
  }

  Future<void> _submitPayoutTransaction() async {
    setState(() => _isSubmitting = true);
    _triggerFullScreenLoadingScreen();

    try {
      final response = await _dio.post(
        'https://skynetwifi.pages.dev/api/withdraw',
        data: {
          "uuid": _userUuid,
          "ip_address": "192.168.8.1",
          "account_number": _accountController.text.trim(),
          "bank_code": _selectedBankCode,
          "amount": double.parse(_amountController.text.trim()),
          "action": "payout"
        },
      );

      Navigator.pop(context);

      if (response.statusCode == 200 && response.data['success'] == true) {
        final double recalculatedWallet = _walletBalance - _calculatedTotalCharge;
        final profile = Map<String, dynamic>.from(_dbBox.get('profile_data', defaultValue: {}));
        profile['wallet_balance'] = recalculatedWallet;
        await _dbBox.put('profile_data', profile);

        _showDarkNotificationBar("Withdrawal transaction processed securely.", isError: false);
        
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) Navigator.pop(context);
        });
      } else {
        setState(() => _isSubmitting = false);
        _showDarkNotificationBar(response.data['message'] ?? "Payout pipeline denied execution request.");
      }
    } catch (_) {
      Navigator.pop(context);
      setState(() => _isSubmitting = false);
      _showDarkNotificationBar("Network issue. Please try again later.");
    }
  }

  void _triggerFullScreenLoadingScreen() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Container(
        color: const Color(0xFF0F1015),
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00296B)),
          ),
        ),
      ),
    );
  }

  void _showDarkNotificationBar(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        backgroundColor: isError ? const Color(0xFF1E1E24) : const Color(0xFF00296B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white),
            SizedBox(width: 10.w),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: Colors.white, fontSize: 12.sp, fontWeight: FontWeight.w400),
              ),
            ),
          ],
        ),
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
          backgroundColor: const Color(0xFFFAFBFC),
          appBar: AppBar(
            backgroundColor: const Color(0xFF00296B),
            elevation: 0,
            title: Text("SkyNet Local Reseller Settlement", style: TextStyle(fontSize: 13.sp, color: Colors.white, fontWeight: FontWeight.bold)),
          ),
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
                          width: 240.r,
                          height: 240.r,
                          errorBuilder: (c, o, s) => const Icon(Icons.account_balance_wallet, size: 80, color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    child: isDesktop ? _buildDesktopSplitPanelView() : _buildMobileScrollFormView(),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildMobileScrollFormView() {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _compileInterfaceBlocks(),
      ),
    );
  }

  Widget _buildDesktopSplitPanelView() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(14.w),
            child: Column(
              children: [
                _buildDynamicBalanceHeaderCard(),
                SizedBox(height: 12.h),
                _buildSystemNotificationBanner(),
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
                _buildAmountValidationBlock(),
                SizedBox(height: 12.h),
                _buildBankSelectorAndAccountSection(),
                SizedBox(height: 14.h),
                if (_validatedAccountName != null) ...[
                  _buildSequentialPinFormBlock(),
                  SizedBox(height: 16.h),
                  _buildSubmitActionBlockButton(),
                ]
              ],
            ),
          ),
        )
      ],
    );
  }

  List<Widget> _compileInterfaceBlocks() {
    return [
      _buildDynamicBalanceHeaderCard(),
      SizedBox(height: 10.h),
      _buildSystemNotificationBanner(),
      SizedBox(height: 14.h),
      _buildAmountValidationBlock(),
      SizedBox(height: 12.h),
      _buildBankSelectorAndAccountSection(),
      SizedBox(height: 14.h),
      if (_validatedAccountName != null) ...[
        _buildSequentialPinFormBlock(),
        SizedBox(height: 16.h),
        _buildSubmitActionBlockButton(),
      ]
    ];
  }

  Widget _buildDynamicBalanceHeaderCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: const Color(0xFF00296B),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("LIQUID CASH BALANCE LEDGER", style: TextStyle(color: Colors.white70, fontSize: 9.sp, fontWeight: FontWeight.bold)),
              SizedBox(height: 4.h),
              Text("₦ ${_walletBalance.toStringAsFixed(2)}", style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.bold)),
            ],
          ),
          const FaIcon(FontAwesomeIcons.buildingColumns, color: Colors.white24, size: 22),
        ],
      ),
    );
  }

  Widget _buildSystemNotificationBanner() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.06),
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: Colors.blue.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF00296B), size: 16),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              "Withdrawal Network Fee: 1% is automatically applied to all outgoing payouts. Please ensure your balance covers this charge.",
              style: TextStyle(fontSize: 10.5.sp, color: const Color(0xFF00296B), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountValidationBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Payout Value Allocation", style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold, color: const Color(0xFF00296B))),
        SizedBox(height: 6.h),
        TextField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            prefixText: "₦ ",
            labelText: "Enter Amount",
            border: const OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
            suffixIcon: _amountController.text.isNotEmpty
                ? (_isAmountValid
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : const Icon(Icons.cancel, color: Color(0xFF1E1E24)))
                : null,
          ),
        ),
        if (_amountController.text.isNotEmpty) ...[
          SizedBox(height: 4.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Settlement Total (+1% Fee):", style: TextStyle(fontSize: 11.sp, color: Colors.black54)),
              Text("₦ ${_calculatedTotalCharge.toStringAsFixed(2)}",
                  style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold, color: _isAmountValid ? Colors.green : Colors.red)),
            ],
          )
        ]
      ],
    );
  }

  Widget _buildBankSelectorAndAccountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Destination Bank Parameters", style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold, color: const Color(0xFF00296B))),
        SizedBox(height: 6.h),
        DropdownButtonFormField<String>(
          value: _selectedBankCode,
          decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          hint: const Text("Select Target Financial Institution"),
          items: _nigerianBanks.map((bank) {
            return DropdownMenuItem<String>(
              value: bank['code'],
              child: Text(bank['name']!),
            );
          }).toList(),
          onChanged: (val) {
            setState(() {
              _selectedBankCode = val;
              _validatedAccountName = null;
              _accountErrorText = null;
              _resetPinMatrix();
            });
            if (_accountController.text.trim().length == 10) {
              _executeAccountLookupDaemon(_accountController.text.trim(), val!);
            }
          },
        ),
        SizedBox(height: 10.h),
        Text("Account Designation Serial", style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold, color: const Color(0xFF00296B))),
        SizedBox(height: 6.h),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _accountController,
                keyboardType: TextInputType.number,
                maxLength: 10,
                decoration: const InputDecoration(
                  labelText: "Account Number",
                  border: OutlineInputBorder(),
                  counterText: "",
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            if (_isSearchingAccount) ...[
              SizedBox(width: 10.w),
              _buildContextualShimmerWidget()
            ]
          ],
        ),
        if (_validatedAccountName != null) ...[
          SizedBox(height: 8.h),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(10.w),
            decoration: BoxDecoration(color: Colors.green.withOpacity(0.08), borderRadius: BorderRadius.circular(6.r), border: Border.all(color: Colors.green.withOpacity(0.3))),
            child: Text("Holder: $_validatedAccountName", style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
          ),
        ],
        if (_accountErrorText != null) ...[
          SizedBox(height: 8.h),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(10.w),
            decoration: BoxDecoration(color: Colors.red.withOpacity(0.08), borderRadius: BorderRadius.circular(6.r), border: Border.all(color: Colors.red.withOpacity(0.3))),
            child: Text(_accountErrorText!, style: TextStyle(fontSize: 11.sp, color: Colors.red.shade800, fontWeight: FontWeight.w500)),
          ),
        ]
      ],
    );
  }

  Widget _buildContextualShimmerWidget() {
    return Container(
      width: 32.r,
      height: 32.r,
      padding: EdgeInsets.all(6.r),
      child: const CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00296B))),
    );
  }

  Widget _buildSequentialPinFormBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Transaction Verification PIN", style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold, color: const Color(0xFF00296B))),
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
                    onChanged: (val) => _validatePinIndexDigit(index, val),
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
    bool canProceed = _evaluateAbsoluteComplianceMetrics() && !_isSubmitting;
    if (!canProceed) return const SizedBox.shrink();

    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF00296B),
        minimumSize: Size(double.infinity, 44.h),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
      ),
      onPressed: _submitPayoutTransaction,
      icon: const FaIcon(FontAwesomeIcons.paperPlane, size: 13, color: Colors.white),
      label: Text(
        "Submit Withdrawal (₦ ${_amountController.text.trim()})",
        style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _accountController.dispose();
    for (var c in _pinControllers) {
      c.dispose();
    }
    for (var f in _pinFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }
}