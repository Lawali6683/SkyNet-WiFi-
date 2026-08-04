import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

class SkyNetTransmissionHistoryPage extends StatefulWidget {
  const SkyNetTransmissionHistoryPage({Key? key}) : super(key: key);

  @override
  State<SkyNetTransmissionHistoryPage> createState() => _SkyNetTransmissionHistoryPageState();
}

class _SkyNetTransmissionHistoryPageState extends State<SkyNetTransmissionHistoryPage> {
  late Box _dbBox;
  List<Map<String, dynamic>> _transmissionHistory = [];

  @override
  void initState() {
    super.initState();
    _syncLocalDatabaseState();
  }

  void _syncLocalDatabaseState() {
    _dbBox = Hive.box('user_profiles_box');
    final profile = Map<String, dynamic>.from(_dbBox.get('profile_data', defaultValue: <String, dynamic>{}));
    final List<dynamic> rawTransmission = profile['transmission'] ?? [];
    
    setState(() {
      _transmissionHistory = rawTransmission.map((item) => Map<String, dynamic>.from(item)).toList();
      _transmissionHistory.sort((a, b) {
        final DateTime dateA = DateTime.tryParse(a['timestamp'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final DateTime dateB = DateTime.tryParse(b['timestamp'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA);
      });
    });
  }

  Future<void> _commitUpdatedArrayToCache() async {
    final profile = Map<String, dynamic>.from(_dbBox.get('profile_data', defaultValue: <String, dynamic>{}));
    profile['transmission'] = _transmissionHistory;
    await _dbBox.put('profile_data', profile);
  }

  void _triggerClearAllVerificationModal() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          title: Text("Clear Transmission History", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: const Color(0xFF00296B))),
          content: Text("Are you completely certain you want to purge all transaction records? This structure cannot be reverted.", style: TextStyle(fontSize: 12.sp, color: Colors.black87)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel", style: TextStyle(color: Colors.grey, fontSize: 12.sp, fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                setState(() {
                  _transmissionHistory.clear();
                });
                await _commitUpdatedArrayToCache();
                _displaySystemFeedbackSnackbar("All history logs flushed successfully.");
              },
              child: Text("Clear All", style: TextStyle(color: Colors.red, fontSize: 12.sp, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _executeAtomicRowDeletion(int index) async {
    setState(() {
      _transmissionHistory.removeAt(index);
    });
    await _commitUpdatedArrayToCache();
    _displaySystemFeedbackSnackbar("Selected record removed securely from cache ledger.");
  }

  void _displaySystemFeedbackSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        backgroundColor: const Color(0xFF00296B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
        content: Text(message, style: TextStyle(color: Colors.white, fontSize: 11.sp, fontWeight: FontWeight.w400)),
      ),
    );
  }

  String _formatIsoTimestamp(String? isoString) {
    if (isoString == null || isoString.isEmpty) return "Unknown Date";
    try {
      final DateTime parsed = DateTime.parse(isoString);
      return DateFormat('dd MMM yyyy • hh:mm a').format(parsed);
    } catch (_) {
      return isoString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 690),
      minTextAdapt: true,
      builder: (context, child) {
        return Scaffold(
          backgroundColor: const Color(0xFFF9FAFC),
          appBar: AppBar(
            backgroundColor: const Color(0xFF00296B),
            elevation: 0,
            title: Text("Transmission History Log", style: TextStyle(fontSize: 13.sp, color: Colors.white, fontWeight: FontWeight.bold)),
            actions: [
              if (_transmissionHistory.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep, color: Colors.white),
                  tooltip: "Clear All History",
                  onPressed: _triggerClearAllVerificationModal,
                )
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              bool isWideView = constraints.maxWidth > 600;
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
                          errorBuilder: (c, o, s) => const Icon(Icons.history, size: 85, color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Center(
                      child: Container(
                        maxWidth: isWideView ? 580.w : double.infinity,
                        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                        child: _transmissionHistory.isEmpty ? _buildEmptyFolderIllustration() : _buildTransmissionListView(),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyFolderIllustration() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FaIcon(FontAwesomeIcons.folderOpen, size: 45.r, color: Colors.black26),
        SizedBox(height: 12.h),
        Text("No Transmission Records Located", style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: Colors.black54)),
        SizedBox(height: 4.h),
        Text("All operational local network traffic metrics appear clean.", style: TextStyle(fontSize: 11.sp, color: Colors.grey)),
      ],
    );
  }

  Widget _buildTransmissionListView() {
    return ListView.separated(
      itemCount: _transmissionHistory.length,
      separatorBuilder: (context, index) => SizedBox(height: 8.h),
      itemBuilder: (context, index) {
        final node = _transmissionHistory[index];
        final String direction = node['direction'] ?? 'deposit';
        final bool isWithdrawal = direction == 'withdrawal';
        final double amount = double.tryParse(node['amount']?.toString() ?? '0') ?? 0.0;
        final String status = node['status'] ?? 'Success';

        return Card(
          elevation: 0.5,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r), side: const BorderSide(color: Colors.black12, width: 0.5)),
          color: Colors.white,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
            child: Row(
              children: [
                Container(
                  width: 34.r,
                  height: 34.r,
                  decoration: BoxDecoration(
                    color: isWithdrawal ? Colors.red.withOpacity(0.08) : Colors.green.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: FaIcon(
                      isWithdrawal ? FontAwesomeIcons.arrowUpRightFromSquare : FontAwesomeIcons.arrowDownLeftFromSquare,
                      size: 13.r,
                      color: isWithdrawal ? Colors.red : Colors.green,
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            "₦ ${amount.toStringAsFixed(2)}",
                            style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          const Spacer(),
                          _buildStatusIndicatorTag(status),
                        ],
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        _formatIsoTimestamp(node['timestamp']),
                        style: TextStyle(fontSize: 10.sp, color: Colors.grey, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 10.w),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 18),
                  onPressed: () => _executeAtomicRowDeletion(index),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 16.r,
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusIndicatorTag(String stateLabel) {
    bool isCompleted = stateLabel.toLowerCase() == 'success';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: isCompleted ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4.r),
      ),
      child: Text(
        stateLabel.toUpperCase(),
        style: TextStyle(
          fontSize: 8.5.sp,
          fontWeight: FontWeight.black,
          color: isCompleted ? Colors.green.shade700 : Colors.orange.shade700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}