import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _referralController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final List<TextEditingController> _pinControllers = List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _pinFocusNodes = List.generate(4, (_) => FocusNode());

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _showImageOverlay = false;
  bool _isLoading = false;
  File? _profileImage;
  String? _alertMessage;
  bool _isAlertSuccess = false;

  @override
  void initState() {
    super.initState();
    _checkClipboardForReferral();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _referralController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    for (var controller in _pinControllers) {
      controller.dispose();
    }
    for (var node in _pinFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _checkClipboardForReferral() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null) {
      final String text = data.text!.trim();
      final RegExp regExp = RegExp(r'^\d{6}$');
      if (regExp.hasMatch(text)) {
        setState(() {
          _referralController.text = text;
        });
      }
    }
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

  Future<void> _pickImage(ImageSource source) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: source,
      preferredCameraDevice: CameraDevice.front,
    );
    if (image != null) {
      setState(() {
        _profileImage = File(image.path);
      });
    }
  }

  String _getPin() {
    return _pinControllers.map((c) => c.text).join();
  }

  bool _validateForm() {
    if (!_formKey.currentState!.validate()) {
      return false;
    }
    if (_getPin().length < 4) {
      _showAlert('Please complete the 4-digit Security PIN', false);
      return false;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      _showAlert('Passwords do not match', false);
      return false;
    }
    return true;
  }

  Future<void> _processRegistration() async {
    if (_profileImage == null) {
      _showAlert('Please capture or select a profile image to continue', false);
      return refinementStep();
    }

    setState(() {
      _showImageOverlay = false;
      _isLoading = true;
    });

    try {
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final SupabaseClient supabase = Supabase.instance.client;

      await supabase.storage.from('skynet_files').upload(
            fileName,
            _profileImage!,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );

      final String profileUrl = supabase.storage.from('skynet_files').getPublicUrl(fileName);
      final Dio dio = Dio();

      final response = await dio.post(
        'https://skynetwifi.pages.dev/api/register',
        data: {
          'full_name': _nameController.text.trim(),
          'phone_number': _phoneController.text.trim(),
          'email': _emailController.text.trim(),
          'referral_code': _referralController.text.trim(),
          'security_pin': _getPin(),
          'password': _passwordController.text,
          'api_secret': '@haruna66',
          'device_uuid': 'HW-${_phoneController.text.trim().hashCode}',
          'profile_url': profileUrl,
        },
      );

      setState(() {
        _isLoading = false;
      });

      if (response.statusCode == 200 || response.statusCode == 201) {
        _showAlert('Registration Successful!', true);
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
          }
        });
      } else {
        _showAlert('Server registration failed. Please try again.', false);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showAlert(e.toString(), false);
    }
  }

  void refinementStep() {
    setState(() {
      _showImageOverlay = true;
    });
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
                  return _buildFormLayout(true);
                } else {
                  return Center(
                    child: SizedBox(
                      width: 520.w,
                      child: _buildFormLayout(false),
                    ),
                  );
                }
              },
            ),
            if (_alertMessage != null) _buildTopAlert(),
            if (_showImageOverlay) _buildImagePickerOverlay(),
            if (_isLoading) _buildFullScreenLoader(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopAlert() {
    return Positioned(
      top: 10.h,
      left: 16.w,
      right: 16.w,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
          decoration: BoxDecoration(
            color: _isAlertSuccess ? const Color(0xFF4CAF50) : const Color(0xFFD32F2F),
            borderRadius: BorderRadius.circular(8.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10.r,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Row(
            children: [
              Icon(
                _isAlertSuccess ? Icons.check_circle : Icons.error_outline,
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

  Widget _buildFullScreenLoader() {
    return Container(
      color: Colors.black87,
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Container(
          padding: EdgeInsets.all(32.r),
          decoration: BoxDecoration(
            color: const Color(0xFF161824),
            borderRadius: BorderRadius.circular(16.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/icon.png',
                width: 64.w,
                height: 64.h,
                fit: BoxFit.contain,
              ),
              SizedBox(height: 24.h),
              Text(
                'Synchronizing Secure Pipeline...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePickerOverlay() {
    return Container(
      color: Colors.blackDE,
      width: double.infinity,
      height: double.infinity,
      padding: EdgeInsets.all(24.r),
      child: Center(
        child: Container(
          padding: EdgeInsets.all(24.r),
          decoration: BoxDecoration(
            color: const Color(0xFF161824),
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: const Color(0xFF242736), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Profile Synchronization',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                'Capture or upload a valid front-facing avatar matrix configuration',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12.sp,
                ),
              ),
              SizedBox(height: 24.h),
              Container(
                width: 160.r,
                height: 160.r,
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0E15),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF0D47A1), width: 3),
                ),
                child: ClipOval(
                  child: _profileImage != null
                      ? Image.file(_profileImage!, fit: BoxFit.cover)
                      : Icon(Icons.account_circle, size: 120.r, color: const Color(0xFF242736)),
                ),
              ),
              SizedBox(height: 24.h),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_front),
                      label: const Text('Front Camera'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF242736)),
                        padding: EdgeInsets.vertical(12.h),
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.image),
                      label: const Text('Gallery Matrix'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF242736)),
                        padding: EdgeInsets.vertical(12.h),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20.h),
              SizedBox(
                width: double.infinity,
                height: 44.h,
                child: ElevatedButton(
                  onPressed: _processRegistration,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D47A1),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                  ),
                  child: Text(
                    'UPLOAD & ACTIVATE',
                    style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              SizedBox(height: 10.h),
              TextButton(
                onPressed: () {
                  setState(() {
                    _showImageOverlay = false;
                  });
                },
                child: Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey, fontSize: 13.sp),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormLayout(bool isMobile) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 24.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Image.asset(
                'assets/images/icon.png',
                width: 54.w,
                height: 54.h,
                fit: BoxFit.contain,
              ),
            ),
            SizedBox(height: 16.h),
            Center(
              child: Text(
                'Intranet Portal Registration',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20.sp,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            SizedBox(height: 24.h),
            _buildInputField(
              controller: _nameController,
              label: 'Full Name',
              icon: Icons.person_outline,
              validator: (v) => v!.isEmpty ? 'Name required' : null,
            ),
            SizedBox(height: 16.h),
            _buildInputField(
              controller: _phoneController,
              label: 'Phone Number',
              icon: Icons.phone_android_outlined,
              keyboardType: TextInputType.phone,
              validator: (v) => v!.isEmpty ? 'Phone number required' : null,
            ),
            SizedBox(height: 16.h),
            _buildInputField(
              controller: _emailController,
              label: 'Email Address',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                if (v!.isEmpty) return 'Email required';
                if (!v.contains('@')) return 'Invalid email configuration';
                return null;
              },
            ),
            SizedBox(height: 16.h),
            _buildInputField(
              controller: _referralController,
              label: 'Optional Referral Code',
              icon: Icons.g_route,
            ),
            SizedBox(height: 20.h),
            Text(
              'Security PIN Configuration',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 10.h),
            _buildPinRow(),
            SizedBox(height: 20.h),
            _buildInputField(
              controller: _passwordController,
              label: 'Password Token',
              icon: Icons.lock_outline,
              obscureText: _obscurePassword,
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              validator: (v) => v!.length < 6 ? 'Password requires minimum 6 parameters' : null,
            ),
            SizedBox(height: 16.h),
            _buildInputField(
              controller: _confirmPasswordController,
              label: 'Confirm Password Token',
              icon: Icons.lock_reset_outlined,
              obscureText: _obscureConfirmPassword,
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
              validator: (v) => v!.isEmpty ? 'Confirmation required' : null,
            ),
            SizedBox(height: 32.h),
            SizedBox(
              width: double.infinity,
              height: 48.h,
              child: ElevatedButton(
                onPressed: () {
                  if (_validateForm()) {
                    refinementStep();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D47A1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'CONTINUE',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            SizedBox(height: 24.h),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pushNamed(context, '/login'),
                child: Text(
                  'Already have an account? Login',
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

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(color: Colors.white, fontSize: 14.sp),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13.sp),
        prefixIcon: Icon(icon, color: Colors.grey.shade600, size: 20.r),
        suffixIcon: suffixIcon,
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
    );
  }

  Widget _buildPinRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(4, (index) {
        return SizedBox(
          width: 58.w,
          child: TextFormField(
            controller: _pinControllers[index],
            focusNode: _pinFocusNodes[index],
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 1,
            obscureText: true,
            style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.bold),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: const Color(0xFF161824),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.r),
                borderSide: const BorderSide(color: Color(0xFF242736), width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.r),
                borderSide: const BorderSide(color: Color(0xFF0D47A1), width: 2),
              ),
            ),
            onChanged: (value) {
              if (value.isNotEmpty && index < 3) {
                _pinFocusNodes[index + 1].requestFocus();
              } else if (value.isEmpty && index > 0) {
                _pinFocusNodes[index - 1].requestFocus();
              }
            },
          ),
        );
      }),
    );
  }
}