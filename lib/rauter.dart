import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';

class SkyNetLocalDashboardPage extends StatefulWidget {
  const SkyNetLocalDashboardPage({Key? key}) : super(key: key);

  @override
  State<SkyNetLocalDashboardPage> createState() => _SkyNetLocalDashboardPageState();
}

class _SkyNetLocalDashboardPageState extends State<SkyNetLocalDashboardPage> {
  late Box _dbBox;
  final Dio _localDio = Dio(BaseOptions(baseUrl: 'http://192.168.8.1', connectTimeout: const Duration(seconds: 4)));
  final NetworkInfo _networkInfo = NetworkInfo();
  
  final TextEditingController _wifiPassController = TextEditingController();
  final TextEditingController _price500mbController = TextEditingController();
  final TextEditingController _price1gbController = TextEditingController();
  final TextEditingController _clientNameController = TextEditingController();
  final TextEditingController _customGbController = TextEditingController();
  final TextEditingController _clientPassController = TextEditingController();

  bool _isConfigEditable = false;
  bool _isPassVisible = false;
  String _selectedAllocation = "500 MB";
  
  List<Map<String, dynamic>> _activeLeases = [];
  List<Map<String, dynamic>> _historicalLogs = [];
  Map<String, dynamic>? _interceptedDevice;
  
  Timer? _pollingTimer;
  Timer? _policingTimer;

  @override
  void initState() {
    super.initState();
    _initializeLocalDatabase();
    _startLocalHardwareLoops();
  }

  void _initializeLocalDatabase() {
    _dbBox = Hive.box('user_profiles_box');
    final savedConfig = Map<String, dynamic>.from(_dbBox.get('router_config', defaultValue: <String, dynamic>{}));
    
    if (savedConfig.isNotEmpty) {
      _wifiPassController.text = savedConfig['wifi_passphrase'] ?? '';
      _price500mbController.text = savedConfig['price_500mb'] ?? '100';
      _price1gbController.text = savedConfig['price_1gb'] ?? '150';
      _isConfigEditable = false;
    } else {
      _isConfigEditable = true;
    }

    _historicalLogs = List<Map<String, dynamic>>.from(_dbBox.get('router_history_logs', defaultValue: []));
  }

  void _startLocalHardwareLoops() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) => _discoverActiveLeases());
    _policingTimer = Timer.periodic(const Duration(seconds: 3), (timer) => _enforceBandwidthPolicingRules());
  }

  Future<void> _saveRouterConfiguration() async {
    final configPayload = {
      'wifi_passphrase': _wifiPassController.text.trim(),
      'price_500mb': _price500mbController.text.trim(),
      'price_1gb': _price1gbController.text.trim(),
      'last_updated': DateTime.now().toIso8601String(),
    };
    await _dbBox.put('router_config', configPayload);
    setState(() => _isConfigEditable = false);
  }

  Future<void> _discoverActiveLeases() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.wifi)) {
        final response = await _localDio.get('/api/v1/dhcp/leases');
        if (response.statusCode == 200 && response.data != null) {
          final List incomingLeases = response.data['active_hosts'] ?? [];
          setState(() {
            _activeLeases = incomingLeases.map((e) => Map<String, dynamic>.from(e)).toList();
          });
          _evaluateInterceptTrigger(response.data['unauthenticated_node']);
        }
      }
    } catch (_) {}
  }

  void _evaluateInterceptTrigger(Map<String, dynamic>? unauthNode) {
    if (unauthNode != null && _interceptedDevice == null) {
      setState(() {
        _interceptedDevice = unauthNode;
        _clientNameController.clear();
        _customGbController.clear();
        _clientPassController.clear();
      });
      _displayInterceptModal();
    }
  }

  Future<void> _enforceBandwidthPolicingRules() async {
    if (_activeLeases.isEmpty) return;
    List<Map<String, dynamic>> operationalList = List.from(_activeLeases);
    
    for (var device in operationalList) {
      double consumed = double.tryParse(device['consumed_mb']?.toString() ?? '0') ?? 0.0;
      double allocated = double.tryParse(device['allocated_mb']?.toString() ?? '0') ?? 0.0;
      
      if (consumed >= allocated && allocated > 0) {
        await _executeHardwareDisconnect(device['mac_address'], device['host_name'] ?? 'Unknown');
      }
    }
  }

  Future<void> _executeHardwareDisconnect(String macAddress, String hostName) async {
    try {
      final response = await _localDio.post('/api/v1/client/disconnect', data: {'mac_address': macAddress});
      if (response.statusCode == 200) {
        final targetDevice = _activeLeases.firstWhere((element) => element['mac_address'] == macAddress, orElse: () => {});
        if (targetDevice.isNotEmpty) {
          final logItem = {
            'host_name': hostName,
            'mac_address': macAddress,
            'total_consumed_mb': targetDevice['consumed_mb'] ?? 0.0,
            'terminated_at': DateTime.now().toIso8601String(),
            'status': 'Quota Exceeded'
          };
          _historicalLogs.add(logItem);
          await _dbBox.put('router_history_logs', _historicalLogs);
          setState(() {
            _activeLeases.removeWhere((element) => element['mac_address'] == macAddress);
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _submitClientAuthorization() async {
    if (_interceptedDevice == null) return;
    
    double calculatedQuotaMb = 500.0;
    if (_selectedAllocation == "Custom GB") {
      double customGb = double.tryParse(_customGbController.text.trim()) ?? 0.0;
      calculatedQuotaMb = customGb * 1024.0;
    }

    final authPayload = {
      'mac_address': _interceptedDevice!['mac_address'],
      'client_name': _clientNameController.text.trim(),
      'allocated_mb': calculatedQuotaMb,
      'passphrase': _clientPassController.text.trim()
    };

    try {
      final response = await _localDio.post('/api/v1/client/authorize', data: authPayload);
      if (response.statusCode == 200) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        setState(() => _interceptedDevice = null);
        _discoverActiveLeases();
      }
    } catch (_) {}
  }

  void _displayInterceptModal() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      pageBuilder: (context, anim1, anim2) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF151515),
              title: Row(
                children: [
                  const FaIcon(FontAwesomeIcons.triangleExclamation, color: Colors.amber, size: 20),
                  SizedBox(width: 10.w),
                  Text("Intercept Node Identified", style: TextStyle(color: Colors.white, fontSize: 16.sp)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Device HW: ${_interceptedDevice?['mac_address']}", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    SizedBox(height: 12.h),
                    TextField(
                      controller: _clientNameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: "Client Full Name", labelStyle: TextStyle(color: Colors.white70)),
                    ),
                    SizedBox(height: 10.h),
                    DropdownButton<String>(
                      value: _selectedAllocation,
                      dropdownColor: const Color(0xFF222222),
                      isExpanded: true,
                      style: const TextStyle(color: Colors.white),
                      items: ["500 MB", "Custom GB"].map((String value) {
                        return DropdownMenuItem<String>(value: value, child: Text(value));
                      }).toList(),
                      onChanged: (val) {
                        setModalState(() => _selectedAllocation = val!);
                      },
                    ),
                    if (_selectedAllocation == "Custom GB")
                      TextField(
                        controller: _customGbController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: "Enter GB Volume", labelStyle: TextStyle(color: Colors.white70)),
                      ),
                    TextField(
                      controller: _clientPassController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: "Distinct Link Passphrase", labelStyle: TextStyle(color: Colors.white70)),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() => _interceptedDevice = null);
                    Navigator.pop(context);
                  },
                  child: const Text("Ignore", style: TextStyle(color: Colors.grey)),
                ),
                TextButton(
                  onPressed: _submitClientAuthorization,
                  child: const Text("Authorize Lane", style: TextStyle(color: Colors.green)),
                )
              ],
            );
          },
        );
      },
    );
  }

  void _purgeClientRecordLocal(String macAddress) async {
    setState(() {
      _activeLeases.removeWhere((element) => element['mac_address'] == macAddress);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 690),
      minTextAdapt: true,
      builder: (context, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            bool isDesktop = constraints.maxWidth > 600;
            return Scaffold(
              backgroundColor: const Color(0xFFF4F6F9),
              appBar: AppBar(
                backgroundColor: const Color(0xFF00296B),
                elevation: 0,
                title: Text("SkyNet Local Reseller Node Dashboard", style: TextStyle(fontSize: 14.sp, color: Colors.white, fontWeight: FontWeight.bold)),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    onPressed: _discoverActiveLeases,
                  )
                ],
              ),
              body: isDesktop ? _buildSplitPaneLayout() : _buildVerticalScrollLayout(),
            );
          },
        );
      },
    );
  }

  Widget _buildVerticalScrollLayout() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(12.w),
      child: Column(
        children: [
          _buildCredentialCardBlock(),
          SizedBox(height: 12.h),
          _buildHardwareTrackerBlock(),
          SizedBox(height: 12.h),
          _buildHistoryLogsBlock(),
        ],
      ),
    );
  }

  Widget _buildSplitPaneLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(12.w),
            child: Column(
              children: [
                _buildCredentialCardBlock(),
                SizedBox(height: 12.h),
                _buildHistoryLogsBlock(),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1, color: Colors.black12),
        Expanded(
          flex: 6,
          child: Padding(
            padding: EdgeInsets.all(12.w),
            child: _buildHardwareTrackerBlock(),
          ),
        ),
      ],
    );
  }

  Widget _buildCredentialCardBlock() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
      child: Padding(
        padding: EdgeInsets.all(14.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Local Eco-System Configuration", style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: const Color(0xFF00296B))),
                if (!_isConfigEditable)
                  IconButton(
                    icon: Icon(_isPassVisible ? Icons.visibility : Icons.visibility_off, size: 18.r, color: Colors.grey),
                    onPressed: () => setState(() => _isPassVisible = !_isPassVisible),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => setState(() => _isConfigEditable = false),
                  )
              ],
            ),
            const Divider(),
            SizedBox(height: 8.h),
            if (_isConfigEditable) ...[
              TextField(
                controller: _wifiPassController,
                decoration: const InputDecoration(labelText: "Host Wi-Fi Passphrase", border: OutlineInputBorder()),
              ),
              SizedBox(height: 10.h),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _price500mbController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Price 500 MB (₦)", border: OutlineInputBorder()),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: TextField(
                      controller: _price1gbController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Price 1 GB (₦)", border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00296B), minimumSize: Size(double.infinity, 42.h)),
                onPressed: _saveRouterConfiguration,
                icon: const FaIcon(FontAwesomeIcons.floppyDisk, size: 14),
                label: const Text("Save Configuration", style: TextStyle(color: Colors.white)),
              )
            ] else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock, color: Color(0xFF00296B)),
                title: const Text("SSID Lock Security Phrase"),
                subtitle: Text(_isPassVisible ? _wifiPassController.text : "••••••••••••••••", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.sp)),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Base Allocation Metrics:", style: TextStyle(color: Colors.grey, fontSize: 11.sp)),
                  Text("500MB: ₦${_price500mbController.text} | 1GB: ₦${_price1gbController.text}", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.sp)),
                ],
              ),
              SizedBox(height: 12.h),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: Size(double.infinity, 36.h)),
                onPressed: () => setState(() => _isConfigEditable = true),
                icon: const Icon(Icons.edit, size: 14),
                label: const Text("Modify Credential Grid"),
              )
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildHardwareTrackerBlock() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
      child: Padding(
        padding: EdgeInsets.all(14.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Live Local DHCP Leases", style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold)),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                  decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(12.r)),
                  child: Text("${_activeLeases.length} Connected", style: TextStyle(color: Colors.green, fontSize: 10.sp, fontWeight: FontWeight.bold)),
                )
              ],
            ),
            const Divider(),
            _activeLeases.isEmpty
                ? Padding(
                    padding: EdgeInsets.symmetric(vertical: 20.h),
                    child: const Center(child: Text("No operational client instances found inside interface layer.")),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _activeLeases.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final item = _activeLeases[index];
                      double consumed = double.tryParse(item['consumed_mb']?.toString() ?? '0') ?? 0.0;
                      double allocated = double.tryParse(item['allocated_mb']?.toString() ?? '0') ?? 0.0;
                      
                      String metricText = consumed > 1024 
                          ? "${(consumed / 1024).toStringAsFixed(2)} GB"
                          : "${consumed.toStringAsFixed(0)} MB";
                          
                      String quotaText = allocated > 1024 
                          ? "${(allocated / 1024).toStringAsFixed(1)} GB"
                          : "${allocated.toStringAsFixed(0)} MB";

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF00296B).withOpacity(0.1),
                          child: const FaIcon(FontAwesomeIcons.laptopWifi, size: 14, color: Color(0xFF00296B)),
                        ),
                        title: Text(item['host_name'] ?? 'Unknown Host Device', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("MAC: ${item['mac_address']} | IP: ${item['ip_address'] ?? 'DHCP Bound'}", style: const TextStyle(fontSize: 11)),
                            SizedBox(height: 4.h),
                            LinearProgressIndicator(
                              value: allocated > 0 ? (consumed / allocated) : 0,
                              backgroundColor: Colors.black12,
                              color: consumed / allocated > 0.85 ? Colors.red : const Color(0xFF00296B),
                            )
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("$metricText / $quotaText", style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold)),
                            SizedBox(width: 4.w),
                            PopupMenuButton<String>(
                              onSelected: (action) {
                                if (action == 'disconnect') {
                                  _executeHardwareDisconnect(item['mac_address'], item['host_name'] ?? 'Unknown');
                                } else if (action == 'delete') {
                                  _purgeClientRecordLocal(item['mac_address']);
                                }
                              },
                              itemBuilder: (context) => [
                                const DropdownMenuItem(value: 'disconnect', child: Text("Disconnect Client", style: TextStyle(color: Colors.red))),
                                const DropdownMenuItem(value: 'delete', child: Text("Delete Record")),
                              ],
                            )
                          ],
                        ),
                      );
                    },
                  )
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryLogsBlock() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
      child: Padding(
        padding: EdgeInsets.all(14.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Immutable Station Consumption Logs", style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold)),
            const Divider(),
            _historicalLogs.isEmpty
                ? Padding(
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    child: const Center(child: Text("Database interaction logs are currently pristine.")),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _historicalLogs.length > 5 ? 5 : _historicalLogs.length,
                    itemBuilder: (context, index) {
                      final log = _historicalLogs.reversed.toList()[index];
                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 4.h),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(log['host_name'] ?? 'Unknown Client Address', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600)),
                                  Text("HW Ref: ${log['mac_address']}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text("${double.parse(log['total_consumed_mb'].toString()).toStringAsFixed(1)} MB", style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold)),
                                Text(log['status'] ?? 'Terminated', style: const TextStyle(fontSize: 9, color: Colors.redAccent)),
                              ],
                            )
                          ],
                        ),
                      );
                    },
                  )
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _policingTimer?.cancel();
    _wifiPassController.dispose();
    _price500mbController.dispose();
    _price1gbController.dispose();
    _clientNameController.dispose();
    _customGbController.dispose();
    _clientPassController.dispose();
    super.dispose();
  }
}