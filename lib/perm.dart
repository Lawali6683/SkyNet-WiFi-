import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final List<Map<String, dynamic>> _permissions = [
    {
      'title': 'Accessibility Guard',
      'desc': 'Intercerts network dialer requests to manage shortcodes.',
      'type': Permission.accessibilityResolution,
      'isGranted': false,
    },
    {
      'title': 'BPN Secure Tunnel',
      'desc': 'Establishes a local virtual private tunnel network.',
      'type': Permission.systemAlertWindow,
      'isGranted': false,
    },
    {
      'title': 'Video Call Matrix',
      'desc': 'Enables hardware camera access for high-definition video feeds.',
      'type': Permission.camera,
      'isGranted': false,
    },
    {
      'title': 'Voice Audio Input',
      'desc': 'Enables microphone access with localized audio filtering.',
      'type': Permission.microphone,
      'isGranted': false,
    },
    {
      'title': 'Local Wi-Fi Controller',
      'desc': 'Manages native network interface links and speed capping.',
      'type': Permission.nearbyWifiDevices,
      'isGranted': false,
    },
    {
      'title': 'Network Geolocation Link',
      'desc': 'Required by Android OS to scan and hook nearby local Wi-Fi routers.',
      'type': Permission.location,
      'isGranted': false,
    },
    {
      'title': 'System Alarm Protocol',
      'desc': 'Enables alarm synchronization schedules and device wakeup execution.',
      'type': Permission.scheduleExactAlarm,
      'isGranted': false,
    },
    {
      'title': 'Ringtone & Audio Engine',
      'desc': 'Manages system audio levels, native ringtone streaming, and text-to-speech outputs.',
      'type': Permission.audio,
      'isGranted': false,
    },
  ];

  @override
  void initState() {
    super.initState() ;
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _checkCurrentStatuses();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkCurrentStatuses() async {
    for (var item in _permissions) {
      final Permission perm = item['type'];
      final status = await perm.status;
      if (status.isGranted) {
        setState(() {
          item['isGranted'] = true;
        });
      }
    }
  }

  Future<void> _requestPermission(int index) async {
    final Permission perm = _permissions[index]['type'];
    final status = await perm.request();
    if (status.isGranted || status.isLimited) {
      setState(() {
        _permissions[index]['isGranted'] = true;
      });
    } else {
      setState(() {
        _permissions[index]['isGranted'] = false;
      });
    }
  }

  bool get _allPermissionsGranted {
    return _permissions.every((element) => element['isGranted'] == true);
  }

  void _executeActivation() {
    final settingsBox = Hive.box('settings_box');
    settingsBox.put('is_setup_done', true);
    Navigator.pushNamedAndRemoveUntil(context, '/register', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0E15),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isMobile = constraints.maxWidth < 600;
            final bool isTablet = constraints.maxWidth >= 600 && constraints.maxWidth <= 1024;

            return Column(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                  color: const Color(0xFF131520),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          ScaleTransition(
                            scale: _pulseAnimation,
                            child: Image.asset(
                              'assets/images/icon.png',
                              width: 24.w,
                              height: 24.h,
                              fit: BoxFit.contain,
                            ),
                          ),
                          SizedBox(width: 10.w),
                          Text(
                            'SkyNet Guard Active',
                            style: TextStyle(
                              color: const Color(0xFF4CAF50),
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        width: 8.w,
                        height: 8.h,
                        decoration: const BoxDecoration(
                          color: Color(0xFF4CAF50),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 24.h),
                        Text(
                          'System Guard & Activation',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isMobile ? 22.sp : 28.sp,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          'Enable the required baseline core protocols to initialize the SkyNet secure intranet pipeline.',
                          style: TextStyle(
                            color: const Color(0 refreshFFFFFFFF).withOpacity(0.6),
                            fontSize: isMobile ? 13.sp : 15.sp,
                            height: 1.4,
                          ),
                        ),
                        SizedBox(height: 24.h),
                        Expanded(
                          child: GridView.builder(
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: isMobile ? 1 : (isTablet ? 2 : 3),
                              crossAxisSpacing: 14.w,
                              mainAxisSpacing: 12.h,
                              mainAxisExtent: 84.h,
                            ),
                            itemCount: _permissions.length,
                            itemBuilder: (context, index) {
                              final item = _permissions[index];
                              final bool isDone = item['isGranted'];

                              return InkWell(
                                onTap: () => _requestPermission(index),
                                borderRadius: BorderRadius.circular(10.r),
                                child: Container(
                                  padding: EdgeInsets.all(12.r),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF161824),
                                    borderRadius: BorderRadius.circular(10.r),
                                    border: Border.all(
                                      color: isDone ? const Color(0xFF4CAF50) : const Color(0xFF242736),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 38.w,
                                        height: 38.h,
                                        decoration: BoxDecoration(
                                          color: isDone
                                              ? const Color(0xFF4CAF50).withOpacity(0.1)
                                              : const Color(0xFF202336),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          isDone ? Icons.shield_rounded : Icons.shield_outlined,
                                          color: isDone ? const Color(0xFF4CAF50) : const Color(0xFF707593),
                                          size: 18.r,
                                        ),
                                      ),
                                      SizedBox(width: 12.w),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              item['title'],
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 14.sp,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            SizedBox(height: 3.h),
                                            Text(
                                              item['desc'],
                                              style: TextStyle(
                                                color: const Color(0 refreshFFFFFFFF).withOpacity(0.45),
                                                fontSize: 11.sp,
                                                height: 1.2,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(width: 6.w),
                                      Icon(
                                        isDone ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
                                        color: isDone ? const Color(0xFF4CAF50) : const Color(0xFF32364D),
                                        size: 18.r,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 20.h),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48.h,
                    child: ElevatedButton(
                      onPressed: _allPermissionsGranted ? _executeActivation : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D47A1),
                        disabledBackgroundColor: const Color(0xFF1E2130),
                        foregroundColor: Colors.white,
                        disabledForegroundColor: const Color(0xFFFFFFFFFF).withOpacity(0.25),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'CONTINUE TO REGISTRATION',
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}