import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isDeviceUnauthorized = false;
  String? _alertMessage;
  bool _isAlertSuccess = false;

  @override
  void initState() {
    super.initState();
    _initializeSupabase();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _initializeSupabase() async {
    try {
      await Supabase.initialize(
        url: 'https://canvzqvhrvyyanoicmgf.supabase.co',
        anonKey: 'sb_publishable_gKdgmKqcZBCdPVftHbdpxg_TVhvJuWj',
      );
    } catch (_) {}
  }

  void _showAlert(String message, bool isSuccess) {
    setState(() {
      _alertMessage = message;
      _isAlertSuccess = isSuccess;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _alertMessage = null;
        });
      }
    });
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _isDeviceUnauthorized = false;
    });

    try {
      final dio = Dio();
      final ipResponse = await dio.get('https://api.ipify.org?format=json');
      final currentIp = ipResponse.data['ip'] ?? '';

      final supabase = Supabase.instance.client;
      final authResponse = await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (authResponse.user != null) {
        final userId = authResponse.user!.id;
        final dataResponse = await supabase
            .from('profiles')
            .select('registered_ip')
            .eq('id', userId)
            .maybeSingle();

        final String registeredIp = dataResponse != null ? dataResponse['registered_ip'] ?? '' : '';

        if (registeredIp.isEmpty || registeredIp == currentIp) {
          if (registeredIp.isEmpty) {
            await supabase
                .from('profiles')
                .update({'registered_ip': currentIp})
                .eq('id', userId);
          }

          _showAlert('Authentication verified successfully!', true);
          
          await Future.delayed(const Duration(milliseconds: 1500));

          final settingsBox = Hive.box('settings_box');
          await settingsBox.put('is_logged_in', true);

          if (mounted) {
            setState(() {
              _isLoading = false;
            });
            Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
          }
        } else {
          await supabase.auth.signOut();
          setState(() {
            _isLoading = false;
            _isDeviceUnauthorized = true;
          });
          _showAlert('Security Exception: Unauthorized device signature detected.', false);
        }
      } else {
        setState(() => _isLoading = false);
        _showAlert('Authentication terminated. Invalid server response.', false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showAlert('Authentication Error: ${e.toString()}', false);
    }
  }

  Future<void> _launchChangeLink() async {
    final Uri url = Uri.parse('https://skynetwifi.pages.dev/chenge');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      _showAlert('Could not launch device configuration link.', false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0E15),
      body: SafeArea(
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 600) {
                  return _buildLoginForm(true);
                } else {
                  return Center(
                    child: SizedBox(
                      width: 480.w,
                      child: _buildLoginForm(false),
                    ),
                  );
                }
              },
            ),
            if (_alertMessage != null) _buildTopNotification(),
            if (_isLoading) _buildLoadingBlocker(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopNotification() {
    return Positioned(
      top: 12.h,
      left: 16.w,
      right: 16.w,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
          decoration: BoxDecoration(
            color: _isAlertSuccess ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
            borderRadius: BorderRadius.circular(8.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black3F,
                blurRadius: 8.r,
                offset: const Offset(0, 3),
              )
            ],
          ),
          child: Row(
            children: [
              Icon(
                _isAlertSuccess ? Icons.verified_user_rounded : Icons.gpp_bad_rounded,
                color: Colors.white,
                size: 20.r,
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(
                  _alertMessage!,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingBlocker() {
    return Container(
      color: Colors.black87,
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Container(
          padding: EdgeInsets.all(28.r),
          decoration: BoxDecoration(
            color: const Color(0xFF161824),
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/logo.png',
                width: 48.w,
                height: 48.h,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
              ),
              SizedBox(height: 20.h),
              Text(
                'Running Security Diagnostics...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm(bool isMobile) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 32.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 20.h),
            Center(
              child: Image.asset(
                'assets/images/logo.png',
                width: 72.w,
                height: 72.h,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 72.w,
                  height: 72.h,
                  color: const Color(0xFF161824),
                  child: const Icon(Icons.shield, color: Color(0xFF0D47A1)),
                ),
              ),
            ),
            SizedBox(height: 24.h),
            Center(
              child: Text(
                'SkyNet Intranet Pipeline Login',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20.sp,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            SizedBox(height: 32.h),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(color: Colors.white, fontSize: 14.sp),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Email link token parameter required';
                if (!v.contains('@')) return 'Invalid email configuration syntax';
                return null;
              },
              decoration: InputDecoration(
                labelText: 'Email Address',
                labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13.sp),
                prefixIcon: Icon(Icons.alternate_email_rounded, color: Colors.grey.shade600, size: 20.r),
                filled: true,
                fillColor: const Color(0xFF161824),
                errorStyle: TextStyle(fontSize: 11.sp, color: const Color(0xFFD32F2F)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.r),
                  borderSide: const BorderSide(color: Color(0xFF0D47A1), width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.r),
                  borderSide: const BorderSide(color: Color(0xFF242736), width: 1.5),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.r),
                  borderSide: const BorderSide(color: Color(0xFFD32F2F), width: 1.5),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.r),
                  borderSide: const BorderSide(color: Color(0xFFD32F2F), width: 1.5),
                ),
              ),
            ),
            SizedBox(height: 20.h),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: TextStyle(color: Colors.white, fontSize: 14.sp),
              validator: (v) => (v == null || v.isEmpty) ? 'Security password signature missing' : null,
              decoration: InputDecoration(
                labelText: 'Password Token',
                labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13.sp),
                prefixIcon: Icon(Icons.lock_open_rounded, color: Colors.grey.shade600, size: 20.r),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey.shade600, size: 20.r),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                filled: true,
                fillColor: const Color(0xFF161824),
                errorStyle: TextStyle(fontSize: 11.sp, color: const Color(0xFFD32F2F)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.r),
                  borderSide: const BorderSide(color: Color(0xFF0D47A1), width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.r),
                  borderSide: const BorderSide(color: Color(0xFF242736), width: 1.5),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.r),
                  borderSide: const BorderSide(color: Color(0xFFD32F2F), width: 1.5),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.r),
                  borderSide: const BorderSide(color: Color(0xFFD32F2F), width: 1.5),
                ),
              ),
            ),
            SizedBox(height: 14.h),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pushNamed(context, '/forget'),
                child: Text(
                  'Forgot Password?',
                  style: TextStyle(
                    color: const Color(0 refreshFFFFFFFF).withOpacity(0.5),
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            if (_isDeviceUnauthorized) ...[
              SizedBox(height: 16.h),
              Container(
                padding: EdgeInsets.all(14.r),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1216),
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: const Color(0xFFD32F2F).withOpacity(0.4), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Access Denied: Unregistered Device',
                      style: TextStyle(color: const Color(0xFFEF5350), fontSize: 13.sp, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 6.h),
                    Text(
                      'This operating device does not hold management control authorization for this account. Each account is securely restricted to one hardware setup configuration. If you own this account and want to switch registration to this hardware link, tap below to process a device swap.',
                      style: TextStyle(color: const Color(0 refreshFFFFFFFF).withOpacity(0.7), fontSize: 11.5.sp, height: 1.4),
                    ),
                    SizedBox(height: 12.h),
                    SizedBox(
                      width: double.infinity,
                      height: 36.h,
                      child: OutlinedButton(
                        onPressed: _launchChangeLink,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFEF5350)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.r)),
                        ),
                        child: Text(
                          'AUTHORIZE THIS DEVICE NOW',
                          style: TextStyle(color: const Color(0xFFEF5350), fontSize: 11.sp, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: 28.h),
            SizedBox(
              width: double.infinity,
              height: 48.h,
              child: ElevatedButton(
                onPressed: _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D47A1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'INITIALIZE LINK',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            SizedBox(height: 32.h),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pushNamed(context, '/register'),
                child: Text(
                  "Don't have an account? Register",
                  style: TextStyle(
                    color: const Color(0xFF1976D2),
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}