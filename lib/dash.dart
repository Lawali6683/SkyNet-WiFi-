import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'db.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late AnimationController _progressController;
  bool _hideBalance = false;
  bool _showNotificationOverlay = false;
  bool _showCopyToast = false;
  late Box _settingsBox;

  @override
  void initState() {
    super.initState();
    _settingsBox = Hive.box('settings_box');
    _hideBalance = _settingsBox.get('hide_balance', defaultValue: false);
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _toggleBalanceVisibility() {
    setState(() {
      _hideBalance = !_hideBalance;
      _settingsBox.put('hide_balance', _hideBalance);
    });
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    setState(() {
      _showCopyToast = true;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showCopyToast = false;
        });
      }
    });
  }

  void _clearNotifications() async {
    final profile = Map<String, dynamic>.from(LocalDB.userProfilesBox.get('profile_data', defaultValue: <String, dynamic>{}));
    profile['account_notifications'] = [];
    await LocalDB.userProfilesBox.put('profile_data', profile);
    LocalDB.userProfileNotifier.value = profile;
    setState(() {
      _showNotificationOverlay = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: LocalDB.userProfileNotifier,
      builder: (context, profileData, child) {
        final String fullName = profileData['full_name'] ?? 'Haruna Lawali';
        final String accountNumber = profileData['account_number'] ?? '0123456789';
        final String balance = profileData['balance']?.toString() ?? '0.00';
        final List notifications = profileData['account_notifications'] ?? [];
        final int unreadCount = notifications.where((n) => n['unread'] == true).length;

        final String plan1Active = profileData['plan1_active'] ?? 'no';
        final String plan2Active = profileData['plan2_active'] ?? 'no';

        return Scaffold(
          key: _scaffoldKey,
          drawer: _buildDrawer(),
          body: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  color: Colors.white,
                ),
              ),
              Positioned.fill(
                child: Opacity(
                  opacity: 0.08,
                  child: Center(
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 320.w,
                      height: 320.h,
                      fit: BoxFit.contain,
                      errorBuilder: (c, e, s) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(
                  color: Colors.white.withOpacity(0.85),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    _buildTopAppBar(fullName, unreadCount),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 600) {
                            return _buildMobileLayout(balance, accountNumber, plan1Active, plan2Active, profileData);
                          } else if (constraints.maxWidth < 1024) {
                            return _buildTabletLayout(balance, accountNumber, plan1Active, plan2Active, profileData);
                          } else {
                            return _buildDesktopLayout(balance, accountNumber, plan1Active, plan2Active, profileData);
                          }
                        },
                      ),
                    ),
                    _buildStickyFooter(),
                  ],
                ),
              ),
              if (_showCopyToast) _buildFloatingToast(),
              if (_showNotificationOverlay) _buildNotificationOverlay(notifications),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopAppBar(String name, int unreadCount) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10.r,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: FaIcon(FontAwesomeIcons.bars, color: const Color(0xFF0D47A1), size: 22.r),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FaIcon(FontAwesomeIcons.wifi, color: const Color(0xFF0D47A1), size: 18.r),
                  SizedBox(width: 6.w),
                  Text(
                    'SkyNet WiFi',
                    style: TextStyle(
                      color: const Color(0xFF0D47A1),
                      fontSize: 18.sp,
                      fontWeight: FontWeight.black,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 2.h),
              Text(
                'Hello $name 🙏',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Stack(
            children: [
              IconButton(
                icon: FaIcon(FontAwesomeIcons.bell, color: const Color(0xFF0D47A1), size: 22.r),
                onPressed: () {
                  setState(() {
                    _showNotificationOverlay = true;
                  });
                },
              ),
              if (unreadCount > 0)
                Positioned(
                  top: 4.h,
                  right: 4.w,
                  child: Container(
                    padding: EdgeInsets.all(4.r),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: BoxConstraints(
                      minWidth: 16.w,
                      minHeight: 16.h,
                    ),
                    child: Text(
                      '$unreadCount',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9.sp,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Container(
        color: const Color(0xFF0D0E15),
        child: Column(
          children: [
            SafeArea(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FaIcon(FontAwesomeIcons.wifi, color: const Color(0xFF1976D2), size: 36.r),
                  SizedBox(height: 12.h),
                  Text(
                    'SkyNet Core Matrix',
                    style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            SizedBox(height: 32.h),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: 12.w),
                children: [
                  _buildDrawerItem(FontAwesomeIcons.house, 'Home', () => _launchUrl('https://skynetwifi.pages.dev')),
                  _buildDrawerItem(FontAwesomeIcons.circleQuestion, 'Help', () => Navigator.pushNamed(context, '/help')),
                  _buildDrawerItem(FontAwesomeIcons.database, 'Data Plan GB', () => Navigator.pushNamed(context, '/plan1')),
                  _buildDrawerItem(FontAwesomeIcons.bolt, 'Wi-Fi Plan Mbps', () => Navigator.pushNamed(context, '/plan2')),
                  _buildDrawerItem(FontAwesomeIcons.moneyBillTransfer, 'Withdraw', () => Navigator.pushNamed(context, '/withdraw')),
                  _buildDrawerItem(FontAwesomeIcons.briefcase, 'For Business', () => _launchUrl('https://skynetwifi.pages.dev/bs')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: FaIcon(icon, color: const Color(0xFF1976D2), size: 18.r),
      title: Text(
        title,
        style: TextStyle(color: Colors.white70, fontSize: 14.sp, fontWeight: FontWeight.w500),
      ),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }

  Widget _buildMobileLayout(String balance, String accNum, String p1, String p2, Map<String, dynamic> data) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.all(16.r),
      child: Column(
        children: [
          _buildWalletCard(balance),
          SizedBox(height: 16.h),
          _buildVirtualBankCard(accNum),
          SizedBox(height: 16.h),
          _buildMeteringDashboard(p1, p2, data),
          SizedBox(height: 16.h),
          _buildAdvertisingBanner(),
        ],
      ),
    );
  }

  Widget _buildTabletLayout(String balance, String accNum, String p1, String p2, Map<String, dynamic> data) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.all(24.r),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildWalletCard(balance)),
              SizedBox(width: 16.w),
              Expanded(child: _buildVirtualBankCard(accNum)),
            ],
          ),
          SizedBox(height: 20.h),
          _buildMeteringDashboard(p1, p2, data),
          SizedBox(height: 20.h),
          _buildAdvertisingBanner(),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout(String balance, String accNum, String p1, String p2, Map<String, dynamic> data) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.all(32.r),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Column(
              children: [
                _buildWalletCard(balance),
                SizedBox(height: 20.h),
                _buildVirtualBankCard(accNum),
                SizedBox(height: 20.h),
                _buildAdvertisingBanner(),
              ],
            ),
          ),
          SizedBox(width: 24.w),
          Expanded(
            flex: 5,
            child: _buildMeteringDashboard(p1, p2, data),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletCard(String balance) {
    return Container(
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D47A1).withOpacity(0.25),
            blurRadius: 15.r,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SKYNET UNIQUE WALLET',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              FaIcon(FontAwesomeIcons.creditCard, color: Colors.white70, size: 18.r),
            ],
          ),
          SizedBox(height: 16.h),
          Row(
            children: [
              Text(
                _hideBalance ? '₦ *********' : '₦ $balance',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24.sp,
                  fontWeight: FontWeight.black,
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(width: 12.w),
              IconButton(
                icon: Icon(
                  _hideBalance ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white70,
                  size: 20.r,
                ),
                onPressed: _toggleBalanceVisibility,
              ),
            ],
          ),
          SizedBox(height: 24.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/withdraw'),
                icon: const Icon(Icons.file_upload_outlined, color: Colors.white, size: 16),
                label: Text('Withdrawal', style: TextStyle(color: Colors.white, fontSize: 12.sp, fontWeight: FontWeight.bold)),
              ),
              SizedBox(width: 12.w),
              TextButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/th'),
                icon: const Icon(Icons.history, color: Colors.white, size: 16),
                label: Text('History Matrix', style: TextStyle(color: Colors.white, fontSize: 12.sp, fontWeight: FontWeight.bold)),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildVirtualBankCard(String accNum) {
    return Container(
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10.r,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'VIRTUAL FUNDING ACCOUNT',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 10.sp, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    'Wema Bank Plc',
                    style: TextStyle(color: const Color(0xFF0D47A1), fontSize: 14.sp, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Image.asset(
                'assets/images/wema.png',
                width: 38.w,
                height: 38.h,
                fit: BoxFit.contain,
                errorBuilder: (c, e, s) => Container(
                  width: 38.w,
                  height: 38.h,
                  color: Colors.grey.shade100,
                  child: const Icon(Icons.account_balance, color: Colors.grey),
                ),
              ),
            ],
          ),
          SizedBox(height: 20.h),
          Text(
            'ACCOUNT NUMBER',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 9.sp, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 4.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                accNum,
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              IconButton(
                icon: Icon(Icons.copy_rounded, color: const Color(0xFF1976D2), size: 20.r),
                onPressed: () => _copyToClipboard(accNum),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMeteringDashboard(String p1, String p2, Map<String, dynamic> data) {
    if (p2 == 'yes') {
      final String planName = data['my_plan_2'] ?? 'Premium Pipeline';
      final String speed = data['plan2_speed'] ?? '8 Mbps';
      final int daysRemaining = int.tryParse(data['plan2_days']?.toString() ?? '3') ?? 3;

      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(24.r),
        decoration: BoxDecoration(
          color: const Color(0xFF161824),
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bolt, color: Colors.amber, size: 24),
                SizedBox(width: 8.w),
                Text(
                  'High-Speed Bandwidth Node',
                  style: TextStyle(color: Colors.white, fontSize: 15.sp, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 20.h),
            Text(
              'ACTIVE SERVICE PROFILE',
              style: TextStyle(color: Colors.white54, fontSize: 10.sp, fontWeight: FontWeight.bold),
            ),
            Text(
              planName,
              style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16.h),
            Text(
              'PROVISIONED THROUGHPUT',
              style: TextStyle(color: Colors.white54, fontSize: 10.sp, fontWeight: FontWeight.bold),
            ),
            Text(
              speed,
              style: TextStyle(color: Colors.amber, fontSize: 24.sp, fontWeight: FontWeight.black),
            ),
            SizedBox(height: 24.h),
            Container(
              padding: EdgeInsets.all(12.r),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_top, color: Colors.white70, size: 16),
                  SizedBox(width: 8.w),
                  Text(
                    'Remaining Days: $daysRemaining',
                    style: TextStyle(color: Colors.white90, fontSize: 13.sp, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            )
          ],
        ),
      );
    }

    final double totalData = double.tryParse(data['total_data_allocated']?.toString() ?? '100.0') ?? 100.0;
    final double remainingData = double.tryParse(data['data_balance']?.toString() ?? '45.5') ?? 45.5;
    bool isConnected = data['is_connected'] == true;

    double progress = remainingData / (totalData > 0 ? totalData : 100.0);
    if (remainingData < 10.0) {
      progress = 0.10;
    }
    if (progress > 1.0) progress = 1.0;
    if (progress < 0.0) progress = 0.0;

    String dataUnit = remainingData >= 1000 ? 'GB' : 'MB';
    double displayValue = remainingData >= 1000 ? remainingData / 1000 : remainingData;

    return Container(
      padding: EdgeInsets.all(24.r),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10.r,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Volume Analytics Meter',
                style: TextStyle(color: Colors.black87, fontSize: 15.sp, fontWeight: FontWeight.bold),
              ),
              _buildPulseMonitor(isConnected),
            ],
          ),
          SizedBox(height: 24.h),
          AnimatedBuilder(
            animation: _progressController,
            builder: (context, child) {
              final currentProgress = progress * _progressController.value;
              return Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 140.r,
                    height: 140.r,
                    child: CircularProgressIndicator(
                      value: currentProgress,
                      strokeWidth: 12.r,
                      backgroundColor: Colors.grey.shade100,
                      color: remainingData < 50 ? Colors.orange : const Color(0xFF0D47A1),
                    ),
                  ),
                  Column(
                    children: [
                      Text(
                        displayValue.toStringAsFixed(1),
                        style: TextStyle(color: Colors.black87, fontSize: 26.sp, fontWeight: FontWeight.black),
                      ),
                      Text(
                        dataUnit,
                        style: TextStyle(color: Colors.grey, fontSize: 12.sp, fontWeight: FontWeight.bold),
                      ),
                    ],
                  )
                ],
              );
            },
          ),
          SizedBox(height: 24.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Network Diagnostics:',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12.sp),
              ),
              Text(
                isConnected ? 'Active Link Established' : 'Inactive Pipeline Block',
                style: TextStyle(
                  color: isConnected ? const Color(0xFF2E7D32) : Colors.grey.shade500,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Throughput Telemetry:',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12.sp),
              ),
              Text(
                isConnected ? '42.8 Mbps' : '0.0 Mbps',
                style: TextStyle(color: const Color(0xFF0D47A1), fontSize: 12.sp, fontWeight: FontWeight.black),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildPulseMonitor(bool active) {
    if (!active) {
      return Container(
        width: 12.w,
        height: 12.h,
        decoration: BoxDecoration(color: Colors.grey.shade400, shape: BoxShape.circle),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1.0),
      duration: const Duration(milliseconds: 1000),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Container(
            width: 12.w,
            height: 12.h,
            decoration: const BoxDecoration(color: Color(0xFF2E7D32), shape: BoxShape.circle),
          ),
        );
      },
      onEnd: () {},
    );
  }

  Widget _buildAdvertisingBanner() {
    final cachedAds = LocalDB.adDataBox.values.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (cachedAds.isEmpty) {
      return const SizedBox.shrink();
    }
    final targetAd = cachedAds.first;
    final String image = targetAd['Ad_image'] ?? '';
    final String link = targetAd['Ad_link'] ?? '';

    if (image.isEmpty) return const SizedBox.shrink();

    return InkWell(
      onPressed: link.isNotEmpty ? () => _launchUrl(link) : null,
      child: Container(
        width: double.infinity,
        height: 80.h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.r),
          image: DecorationImage(image: NetworkImage(image), fit: BoxFit.cover),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8.r,
              offset: const Offset(0, 3),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStickyFooter() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade100, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.around,
        children: [
          _buildFooterButton(FontAwesomeIcons.house, () => _launchUrl('https://skynetwifi.pages.dev')),
          _buildFooterButton(FontAwesomeIcons.layerGroup, () => Navigator.pushNamed(context, '/plan1')),
          InkWell(
            onPressed: () => Navigator.pushNamed(context, '/call'),
            child: Image.asset(
              'assets/images/call.png',
              width: 40.w,
              height: 40.h,
              errorBuilder: (c, e, s) => FaIcon(FontAwesomeIcons.phone, color: const Color(0xFF0D47A1), size: 20.r),
            ),
          ),
          _buildFooterButton(FontAwesomeIcons.clockRotateLeft, () => Navigator.pushNamed(context, '/ht')),
          _buildFooterButton(FontAwesomeIcons.userShield, () => Navigator.pushNamed(context, '/profile')),
        ],
      ),
    );
  }

  Widget _buildFooterButton(IconData icon, VoidCallback action) {
    return IconButton(
      icon: FaIcon(icon, color: const Color(0xFF242736), size: 20.r),
      onPressed: action,
    );
  }

  Widget _buildFloatingToast() {
    return Positioned(
      top: 20.h,
      left: 32.w,
      right: 32.w,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
          decoration: BoxDecoration(color: const Color(0xFF0D47A1), borderRadius: BorderRadius.circular(24.r)),
          child: Text(
            'Copied Successfully!',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 12.sp, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationOverlay(List notifications) {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          color: Colors.black54,
          padding: EdgeInsets.all(24.r),
          child: Center(
            child: Container(
              constraints: BoxConstraints(maxWidth: 460.w, maxHeight: 520.h),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16.r),
              ),
              padding: EdgeInsets.all(20.r),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Audit Statement Logs',
                        style: TextStyle(color: Colors.black87, fontSize: 16.sp, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.black54),
                        onPressed: () => setState(() => _showNotificationOverlay = false),
                      )
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: notifications.isEmpty
                        ? Center(
                            child: Text(
                              'No historical notification traces found.',
                              style: TextStyle(color: Colors.grey, fontSize: 13.sp),
                            ),
                          )
                        : ListView.separated(
                            itemCount: notifications.length,
                            separatorBuilder: (c, i) => const Divider(),
                            itemBuilder: (context, index) {
                              final item = notifications[index];
                              return Padding(
                                padding: EdgeInsets.symmetric(vertical: 4.h),
                                child: Text(
                                  item['message'] ?? '',
                                  style: TextStyle(color: Colors.grey.shade800, fontSize: 12.5.sp, height: 1.4),
                                ),
                              );
                            },
                          ),
                  ),
                  if (notifications.isNotEmpty) ...[
                    const Divider(),
                    SizedBox(height: 8.h),
                    SizedBox(
                      width: double.infinity,
                      height: 44.h,
                      child: ElevatedButton(
                        onPressed: _clearNotifications,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD32F2F),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                        ),
                        child: Text(
                          'FLUSH ACCOUNT LOGS',
                          style: TextStyle(color: Colors.white, fontSize: 12.sp, fontWeight: FontWeight.bold),
                        ),
                      ),
                    )
                  ]
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}