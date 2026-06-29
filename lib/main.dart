import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';

late List<CameraDescription> cameras;

// --- SJVN CORPORATE BRANDING & CONFIG ---
const Color sjvnBlue = Color(0xFF009CDE);   
const Color sjvnOrange = Color(0xFFF26522); 

// 💥 UPDATE THIS WHEN NGROK CHANGES
const String BASE_URL = "https://expedited-vowed-olympics.ngrok-free.dev";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const AttendanceApp());
}

// --- PERSISTENT APP STATE ---
class AppState {
  static String? loggedInUser;
  static String? adminToken;      
  static String? adminRole;       
  static bool isPunchedIn = false;
  static DateTime? punchInTime;
  static DateTime? punchOutTime;

  static Future<void> saveState() async {
    final prefs = await SharedPreferences.getInstance();
    if (loggedInUser != null) await prefs.setString('loggedInUser', loggedInUser!);
    await prefs.setBool('isPunchedIn', isPunchedIn);
    
    if (punchInTime != null) {
      await prefs.setString('punchInTime', punchInTime!.toIso8601String());
    } else {
      await prefs.remove('punchInTime');
    }
    
    if (punchOutTime != null) {
      await prefs.setString('punchOutTime', punchOutTime!.toIso8601String());
    } else {
      await prefs.remove('punchOutTime');
    }
  }

  static Future<void> loadState() async {
    final prefs = await SharedPreferences.getInstance();
    loggedInUser = prefs.getString('loggedInUser');
    isPunchedIn = prefs.getBool('isPunchedIn') ?? false;
    
    String? pIn = prefs.getString('punchInTime');
    if (pIn != null) punchInTime = DateTime.parse(pIn);
    
    String? pOut = prefs.getString('punchOutTime');
    if (pOut != null) punchOutTime = DateTime.parse(pOut);
  }

  // 💥 NOTE: loggedInUser is intentionally preserved across clearState() calls.
  // Employees stay associated with their entered ID across normal logout/app
  // restarts. Use clearLoggedInUser() (e.g. from a "Switch User"/"Change ID"
  // action) to explicitly reset it.
  static Future<void> clearState() async {
    final prefs = await SharedPreferences.getInstance();
    final preservedUser = loggedInUser;
    await prefs.clear();
    if (preservedUser != null) await prefs.setString('loggedInUser', preservedUser);
    
    loggedInUser = preservedUser;
    adminToken = null;
    adminRole = null;
    isPunchedIn = false;
    punchInTime = null;
    punchOutTime = null;
  }

  // 💥 Explicitly clears the stored employee ID. Call this from a
  // "Switch User" / "Change ID" action if one is added to the UI.
  static Future<void> clearLoggedInUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('loggedInUser');
    loggedInUser = null;
  }

  static String formatTime(DateTime? time) {
    if (time == null) return "--:--";
    String hours = time.hour.toString().padLeft(2, '0');
    String minutes = time.minute.toString().padLeft(2, '0');
    return "$hours:$minutes";
  }
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SJVN Attendance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
        ),
        colorScheme: const ColorScheme.dark(
          primary: sjvnBlue,
          secondary: sjvnOrange,
        ),
      ),
      home: const WelcomeScreen(),
    );
  }
}

// --- 1. WELCOME SCREEN (WITH SERVER SYNC) ---
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await AppState.loadState();
    
    // Ping server to verify active status
    if (AppState.loggedInUser != null) {
      try {
        var response = await http.get(
          Uri.parse("$BASE_URL/status?employee_id=${AppState.loggedInUser}"),
          headers: {
            'ngrok-skip-browser-warning': 'true',
          },
        ).timeout(const Duration(seconds: 5));
        
        if (response.statusCode == 200) {
          var data = jsonDecode(response.body);
          AppState.isPunchedIn = data['is_punched_in'];
          if (!AppState.isPunchedIn) {
            final today = DateTime.now().toIso8601String().substring(0, 10);
            final lastPunchDay = AppState.punchInTime?.toIso8601String().substring(0, 10);
            if (lastPunchDay != today) {
              AppState.punchInTime = null;
              AppState.punchOutTime = null;
            }
          }
          await AppState.saveState();
        }
      } catch (_) { }
    }

    await Future.delayed(const Duration(milliseconds: 1500));

    if (mounted) {
      if (AppState.loggedInUser != null) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const DashboardScreen()));
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const EmployeeIdScreen()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: sjvnBlue.withValues(alpha: 0.3), blurRadius: 30, spreadRadius: 5)]
              ),
              child: Image.asset('assets/sjvn_logo.png', height: 120),
            ),
            const SizedBox(height: 30),
            const Text("SECURE TERMINAL", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 3, color: Colors.white)),
            const SizedBox(height: 40),
            const CircularProgressIndicator(color: sjvnOrange),
          ],
        ),
      ),
    );
  }
}

// --- 2. EMPLOYEE ID SCREEN (NO AUTH — TRUST-BASED) ---
class EmployeeIdScreen extends StatefulWidget {
  const EmployeeIdScreen({super.key});

  @override
  State<EmployeeIdScreen> createState() => _EmployeeIdScreenState();
}

class _EmployeeIdScreenState extends State<EmployeeIdScreen> {
  final TextEditingController _idController = TextEditingController();

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  void _continue() {
    final enteredId = _idController.text.trim();
    if (enteredId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Employee ID required"), backgroundColor: Colors.red));
      return;
    }

    AppState.loggedInUser = enteredId;
    AppState.saveState();

    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const DashboardScreen()));
  }

  Future<void> _showAdminAuthDialog() async {
    final TextEditingController userCtrl = TextEditingController();
    final TextEditingController passCtrl = TextEditingController();
    bool isChecking = false;
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: const Text("Admin Portal Login"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: userCtrl,
                    decoration: InputDecoration(
                      labelText: "Username",
                      filled: true,
                      fillColor: Colors.grey.shade900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: "Password",
                      filled: true,
                      fillColor: Colors.grey.shade900,
                    ),
                  ),
                  if (isChecking)
                    const Padding(
                      padding: EdgeInsets.only(top: 20),
                      child: CircularProgressIndicator(color: sjvnBlue),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: sjvnBlue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isChecking ? null : () async {
                    setDialogState(() => isChecking = true);
                    try {
                      var response = await http.post(
                        Uri.parse("$BASE_URL/admin/login"),
                        headers: {'ngrok-skip-browser-warning': 'true'},
                        body: {
                          'username': userCtrl.text.trim(),
                          'password': passCtrl.text.trim(),
                        },
                      );
                      if (response.statusCode == 200) {
                        var parsed = jsonDecode(response.body);
                        AppState.adminToken = parsed['access_token'];
                        AppState.adminRole = parsed['role'];
                        if (mounted) Navigator.pop(dialogContext);
                        if (mounted) {
                          Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                AdminSettingsScreen(role: parsed['role']),
                          ),
                        );
                        }
                      } else {
                        throw Exception(
                            jsonDecode(response.body)['detail'] ??
                                "Invalid Credentials");
                      }
                    } catch (e) {
                      setDialogState(() => isChecking = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(e.toString().replaceAll("Exception: ", "")),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  child: const Text("Login"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.settings, color: Colors.white24, size: 20), onPressed: _showAdminAuthDialog),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: sjvnBlue.withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 3)]
                  ),
                  child: Image.asset('assets/sjvn_logo.png', height: 90),
                ),
                const SizedBox(height: 30),
                const Text(
                  "Enter Your Employee ID",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 40),

                TextField(
                  controller: _idController,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: "Employee ID",
                    prefixIcon: const Icon(Icons.badge, color: sjvnBlue),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey.shade900,
                  ),
                  onSubmitted: (_) => _continue(),
                ),

                const SizedBox(height: 40),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20), backgroundColor: sjvnBlue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text("Continue", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  onPressed: _continue,
                ),

              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- 3. DASHBOARD SCREEN ---
// --- 3. DASHBOARD SCREEN ---
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {}); 
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncStatusFromServer();
    }
  }

  Future<void> _syncStatusFromServer() async {
    try {
      var response = await http.get(
        Uri.parse("$BASE_URL/status?employee_id=${AppState.loggedInUser}"),
        headers: {
          'ngrok-skip-browser-warning': 'true',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) setState(() => AppState.isPunchedIn = data['is_punched_in']);
      }
    } catch (_) {}
  }

  String getLiveDuration() {
    if (AppState.punchInTime == null) return "00:00:00";
    DateTime endTime = AppState.punchOutTime ?? DateTime.now();
    Duration diff = endTime.difference(AppState.punchInTime!);
    String hours = diff.inHours.toString().padLeft(2, '0');
    String minutes = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
    String seconds = diff.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$hours:$minutes:$seconds";
  }

  Future<void> _executeLogout() async {
    await AppState.clearState();
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const EmployeeIdScreen()));
  }

  Future<void> _handleLogout() async {
    if (AppState.isPunchedIn) {
      bool confirm = await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [Icon(Icons.warning_amber_rounded, color: sjvnOrange, size: 28), SizedBox(width: 10), Expanded(child: Text('Active Shift', style: TextStyle(color: sjvnOrange)))]),
          content: const Text('You are currently punched in. Proceed to Punch Out before logging out?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: sjvnOrange, foregroundColor: Colors.white), onPressed: () => Navigator.of(context).pop(true), child: const Text('Punch Out & Log Out')),
          ],
        ),
      ) ?? false;

      if (confirm) _navigateToCamera('out', logoutAfter: true);
    } else {
      await _executeLogout();
    }
  }

  void _navigateToCamera(String action, {bool logoutAfter = false}) async {
    final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => CameraScreen(action: action)));
    if (result == true && mounted) {
      if (logoutAfter) {
        await _executeLogout();
      } else {
        setState(() {});
      } 
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Dashboard", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        actions: [IconButton(icon: const Icon(Icons.exit_to_app, color: Colors.white), onPressed: _handleLogout)],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Image.asset('assets/sjvn_logo.png', height: 60),
                ),
              ),

              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppState.isPunchedIn ? sjvnBlue : Colors.grey.shade800, width: 2),
                ),
                child: Column(
                  children: [
                    Text(AppState.isPunchedIn ? "STATUS: ACTIVE SHIFT" : "STATUS: OFF DUTY", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppState.isPunchedIn ? sjvnBlue : Colors.grey.shade400)),
                    const SizedBox(height: 20),
                    const Text("Punch In Time", style: TextStyle(color: Colors.white54)),
                    Text(AppState.formatTime(AppState.punchInTime), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                    const Divider(height: 40, color: Colors.white24),
                    
                    Text(AppState.isPunchedIn ? "Live Shift Duration" : "Punch Out Time", style: const TextStyle(color: Colors.white54)),
                    Text(AppState.isPunchedIn ? getLiveDuration() : AppState.formatTime(AppState.punchOutTime), style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppState.isPunchedIn ? sjvnOrange : Colors.white)),
                  ],
                ),
              ),
              const Spacer(),
              
              if (!AppState.isPunchedIn && AppState.punchOutTime == null) ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20), backgroundColor: sjvnBlue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  icon: const Icon(Icons.login_rounded, size: 28), label: const Text("Punch IN", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), onPressed: () => _navigateToCamera('in'),
                ),
              ] else if (AppState.isPunchedIn) ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20), backgroundColor: sjvnOrange, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  icon: const Icon(Icons.logout_rounded, size: 28), label: const Text("Punch OUT", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), onPressed: () => _navigateToCamera('out'),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: sjvnBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: sjvnBlue.withValues(alpha: 0.3))),
                  child: Center(child: Text("Shift Complete for Today", style: TextStyle(fontSize: 18, color: sjvnBlue.withValues(alpha: 0.9), fontWeight: FontWeight.bold))),
                )
              ]
            ],
          ),
        ),
      ),
    );
  }
}

// --- 4. CAMERA SCREEN ---
class CameraScreen extends StatefulWidget {
  final String action; 
  const CameraScreen({super.key, required this.action});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  bool _isCameraInitialized = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  void _initializeCamera() {
    final frontCamera = cameras.firstWhere((camera) => camera.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
    // 💥 UPDATED to High Resolution for Face Rec
    _controller = CameraController(frontCamera, ResolutionPreset.high, enableAudio: false);
    _controller.initialize().then((_) async {
      if (!mounted) return;
      // 💥 ADDED orientation lock so faces aren't sent sideways
      await _controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      setState(() => _isCameraInitialized = true);
    }).catchError((e) => debugPrint("Camera error: $e"));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showResultDialog(String title, String message, bool isSuccess) {
    showDialog(
      context: context, barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [Icon(isSuccess ? Icons.check_circle : Icons.error_outline, color: isSuccess ? sjvnBlue : Colors.red.shade500), const SizedBox(width: 10), Expanded(child: Text(title))]),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: isSuccess ? sjvnBlue : Colors.red.shade700, foregroundColor: Colors.white),
            child: const Text('OK'),
            onPressed: () { Navigator.of(context).pop(); if (isSuccess) Navigator.of(context).pop(true); },
          ),
        ],
      ),
    );
  }

  Future<void> _performScan() async {
    setState(() => _isLoading = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception("Turn on Location Services.");

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw Exception("Location denied.");
      }

      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final XFile photo = await _controller.takePicture();

      var request = http.MultipartRequest('POST', Uri.parse("$BASE_URL/punch"));
      request.headers.addAll({'ngrok-skip-browser-warning': 'true'});
      request.fields['employee_id'] = AppState.loggedInUser!;
      request.fields['action'] = widget.action; 
      request.fields['latitude'] = position.latitude.toString();
      request.fields['longitude'] = position.longitude.toString();
      request.files.add(await http.MultipartFile.fromPath('photo', photo.path));

      var response = await request.send();
      final respStr = await response.stream.bytesToString();

      if (mounted) {
        if (response.statusCode == 200) {
          var jsonResponse = jsonDecode(respStr);
          String user = jsonResponse['employee_id'];
          String site = jsonResponse['site'] ?? "Unknown Location";
          
          if (widget.action == 'in') { AppState.isPunchedIn = true; AppState.punchInTime = DateTime.now(); } 
          else { AppState.isPunchedIn = false; AppState.punchOutTime = DateTime.now(); }
          
          await AppState.saveState();
          _showResultDialog("Verification Success", "Identity confirmed for $user at $site.", true);
        } else {
          throw Exception(jsonDecode(respStr)['detail']);
        }
      }
    } catch (e) {
      if (mounted) _showResultDialog("Verification Failed", e.toString().replaceAll("Exception: ", ""), false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("PUNCH ${widget.action == 'in' ? 'IN' : 'OUT'} SCAN")),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(20),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20)]),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: _isCameraInitialized ? CameraPreview(_controller) : const Center(child: CircularProgressIndicator(color: Colors.white)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 65), backgroundColor: widget.action == 'in' ? sjvnBlue : sjvnOrange, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                icon: _isLoading ? const SizedBox.shrink() : const Icon(Icons.face_retouching_natural, size: 28),
                onPressed: _isLoading ? null : _performScan,
                label: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("Verify Identity", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- 5. REGISTRATION SCREEN ---
// --- 5. REGISTRATION SCREEN ---
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  late CameraController _controller;
  bool _isCameraInitialized = false;
  bool _isLoading = false;
  
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _pinController = TextEditingController(); // 💥 Added missing PIN controller
  final TextEditingController _mobileController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  void _initializeCamera() {
    final frontCamera = cameras.firstWhere((camera) => camera.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
    _controller = CameraController(frontCamera, ResolutionPreset.high, enableAudio: false);
    _controller.initialize().then((_) async {
      if (!mounted) return;
      await _controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      setState(() => _isCameraInitialized = true);
    }).catchError((e) => debugPrint("Camera error: $e"));
  }

  @override
  void dispose() {
    _controller.dispose();
    _idController.dispose();
    _pinController.dispose(); // 💥 Dispose the new controller
    _mobileController.dispose();
    super.dispose();
  }

  Future<void> _registerUser() async {
    if (AppState.adminToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Admin Authorization Required."), backgroundColor: Colors.red));
      return;
    }

    if (_idController.text.trim().isEmpty || _pinController.text.trim().isEmpty || _mobileController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("All fields are required."), backgroundColor: Colors.red));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final XFile photo = await _controller.takePicture();

      var request = http.MultipartRequest('POST', Uri.parse("$BASE_URL/register"));
      request.headers.addAll({'ngrok-skip-browser-warning': 'true', 'Authorization': 'Bearer ${AppState.adminToken}'});
      
      request.fields['employee_id'] = _idController.text.trim();
      request.fields['pin'] = _pinController.text.trim(); // 💥 Ensure PIN is sent to server
      request.fields['mobile_number'] = _mobileController.text.trim();
      request.files.add(await http.MultipartFile.fromPath('photo', photo.path));

      var response = await request.send();
      final respStr = await response.stream.bytesToString();

      if (mounted) {
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Registration Successful!"), backgroundColor: Colors.green));
          Navigator.pop(context); 
        } else {
          throw Exception(jsonDecode(respStr)['detail']);
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll("Exception: ", "")), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Enroll New Employee")),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 4,
              child: Container(
                margin: const EdgeInsets.all(20),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20)]),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: _isCameraInitialized ? CameraPreview(_controller) : const Center(child: CircularProgressIndicator(color: Colors.white)),
                ),
              ),
            ),
            Expanded(
              flex: 6, // Gave slightly more space for the extra field
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
                child: Column(
                  children: [
                    TextField(controller: _idController, decoration: InputDecoration(labelText: "New Employee ID", prefixIcon: const Icon(Icons.badge, color: sjvnBlue), filled: true, fillColor: Colors.grey.shade900, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                    const SizedBox(height: 10),
                    
                    // 💥 Re-added the missing PIN Field
                    TextField(
                      controller: _pinController, 
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: InputDecoration(
                        labelText: "Create 6-Digit PIN", 
                        counterText: "", // Hides the max length counter text below the field
                        prefixIcon: const Icon(Icons.password, color: sjvnBlue), 
                        filled: true, 
                        fillColor: Colors.grey.shade900, 
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
                      )
                    ),
                    const SizedBox(height: 10),

                    TextField(controller: _mobileController, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: "Mobile Number", prefixIcon: const Icon(Icons.phone_android, color: sjvnBlue), filled: true, fillColor: Colors.grey.shade900, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                    const SizedBox(height: 20),
                    
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60), backgroundColor: sjvnBlue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      icon: _isLoading ? const SizedBox.shrink() : const Icon(Icons.person_add),
                      onPressed: _isLoading ? null : _registerUser,
                      label: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("Capture Face & Register", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- 6. ADMIN SETTINGS SCREEN ---
class AdminSettingsScreen extends StatefulWidget {
  final String role; 
  const AdminSettingsScreen({super.key, required this.role});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  
  double _liveness = 0.75;
  bool _systemActive = true;
  List<dynamic> _locations = [];

  bool get canEdit => widget.role == 'super_admin';

  @override
  void initState() {
    super.initState();
    _fetchCurrentSettings();
  }

  Future<void> _fetchCurrentSettings() async {
    try {
      final response = await http.get(
        Uri.parse("$BASE_URL/admin/settings"),
        headers: {
          'ngrok-skip-browser-warning': 'true',
          'Authorization': 'Bearer ${AppState.adminToken}',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _liveness = (data['liveness_threshold'] as num).toDouble();
            _systemActive = data['system_active'];
            _locations = data['locations'] ?? [];
            _isLoading = false;
          });
        }
      } else {
        throw Exception("Failed to load settings");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error fetching settings: $e"), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveSettings() async {
    if (!canEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Permission Denied: Read-Only Access"), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final response = await http.post(
        Uri.parse("$BASE_URL/admin/settings"),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
          'Authorization': 'Bearer ${AppState.adminToken}',  
        },
        body: jsonEncode({
          'liveness_threshold': _liveness,
          'system_active': _systemActive,
          'locations': _locations,
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Server Config Updated!"), backgroundColor: Colors.green),
          );
          Navigator.pop(context);
        }
      } else {
        throw Exception("Failed to save.");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showAddAdminDialog() {
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String selectedRole = 'site_manager'; 
    bool isCreating = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text("Create New Admin", style: TextStyle(color: sjvnBlue)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: userCtrl, decoration: InputDecoration(labelText: "Username", filled: true, fillColor: Colors.grey.shade900)),
                const SizedBox(height: 10),
                TextField(controller: passCtrl, obscureText: true, decoration: InputDecoration(labelText: "Password", filled: true, fillColor: Colors.grey.shade900)),
                const SizedBox(height: 15),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  dropdownColor: Colors.grey.shade900,
                  decoration: InputDecoration(labelText: "Privilege Level", filled: true, fillColor: Colors.grey.shade900),
                  items: const [
                    DropdownMenuItem(value: 'site_manager', child: Text("Site Manager (Read Only)")),
                    DropdownMenuItem(value: 'super_admin', child: Text("Super Admin (Full Edit)")),
                  ],
                  onChanged: (val) => setDialogState(() => selectedRole = val!),
                ),
                if (isCreating) const Padding(padding: EdgeInsets.only(top: 15), child: CircularProgressIndicator(color: sjvnBlue)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Cancel")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: sjvnBlue, foregroundColor: Colors.white),
                onPressed: isCreating ? null : () async {
                  setDialogState(() => isCreating = true);
                  try {
                    var uri = Uri.parse("$BASE_URL/admin/create");
                    var response = await http.post(uri, headers: {
                      'ngrok-skip-browser-warning': 'true',
                      'Authorization': 'Bearer ${AppState.adminToken}',  
                    }, body: {
                      'new_username': userCtrl.text.trim(),
                      'new_password': passCtrl.text.trim(),
                      'new_role': selectedRole,
                    });

                    if (response.statusCode == 200) {
                      if (mounted) Navigator.pop(dialogContext);
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("User ${userCtrl.text} Created!"), backgroundColor: Colors.green));
                    } else {
                      var err = jsonDecode(response.body);
                      throw Exception(err['detail']);
                    }
                  } catch (e) {
                    setDialogState(() => isCreating = false);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
                  }
                },
                child: const Text("Create User"),
              )
            ],
          );
        }
      )
    );
  }

  void _showAddLocationDialog() {
    final nameCtrl = TextEditingController();
    final latCtrl = TextEditingController();
    final lonCtrl = TextEditingController();
    final radiusCtrl = TextEditingController(text: "50");
    bool isFetchingLocation = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text("Add New Site", style: TextStyle(color: sjvnBlue)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl, 
                    decoration: InputDecoration(
                      labelText: "Site Name (e.g., Warehouse B)",
                      filled: true, fillColor: Colors.grey.shade900,
                    )
                  ),
                  const SizedBox(height: 15),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: sjvnBlue.withValues(alpha: 0.15),
                        foregroundColor: sjvnBlue,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: sjvnBlue.withValues(alpha: 0.5))
                        ),
                      ),
                      icon: isFetchingLocation 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: sjvnBlue, strokeWidth: 2))
                          : const Icon(Icons.my_location),
                      label: Text(isFetchingLocation ? "Acquiring Satellites..." : "Auto-Fill Current GPS"),
                      onPressed: isFetchingLocation ? null : () async {
                        setDialogState(() => isFetchingLocation = true);
                        try {
                          bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
                          if (!serviceEnabled) throw Exception("Turn on Location Services.");

                          LocationPermission permission = await Geolocator.checkPermission();
                          if (permission == LocationPermission.denied) {
                            permission = await Geolocator.requestPermission();
                            if (permission == LocationPermission.denied) throw Exception("Permission denied.");
                          }

                          Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
                          
                          latCtrl.text = position.latitude.toString();
                          lonCtrl.text = position.longitude.toString();
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.toString()), backgroundColor: Colors.red)
                          );
                        } finally {
                          setDialogState(() => isFetchingLocation = false);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 15),

                  TextField(
                    controller: latCtrl, keyboardType: TextInputType.number, 
                    decoration: InputDecoration(
                      labelText: "Latitude",
                      filled: true, fillColor: Colors.grey.shade900,
                    )
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: lonCtrl, keyboardType: TextInputType.number, 
                    decoration: InputDecoration(
                      labelText: "Longitude",
                      filled: true, fillColor: Colors.grey.shade900,
                    )
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: radiusCtrl, keyboardType: TextInputType.number, 
                    decoration: InputDecoration(
                      labelText: "Allowed Radius (Meters)",
                      filled: true, fillColor: Colors.grey.shade900,
                    )
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: sjvnBlue, foregroundColor: Colors.white),
                onPressed: () {
                  if (nameCtrl.text.isNotEmpty && latCtrl.text.isNotEmpty && lonCtrl.text.isNotEmpty) {
                    setState(() {
                      _locations.add({
                        "name": nameCtrl.text.trim(),
                        "latitude": double.tryParse(latCtrl.text) ?? 0.0,
                        "longitude": double.tryParse(lonCtrl.text) ?? 0.0,
                        "radius": double.tryParse(radiusCtrl.text) ?? 50.0,
                      });
                    });
                    Navigator.pop(dialogContext);
                  }
                },
                child: const Text("Add Site"),
              )
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Server Admin Panel", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E1E1E),
        actions: [
          IconButton(
            icon: _isSaving 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: sjvnBlue, strokeWidth: 2)) 
                : Icon(Icons.cloud_upload, color: canEdit ? sjvnBlue : Colors.grey),
            onPressed: !canEdit || _isSaving ? null : _saveSettings,
            tooltip: canEdit ? "Push Changes to Server" : "Read-Only Access",
          )
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: sjvnBlue))
        : Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          children: [
                            if (!canEdit)
                              Container(
                                margin: const EdgeInsets.only(bottom: 20),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange)),
                                child: const Row(
                                  children: [
                                    Icon(Icons.visibility, color: Colors.orange, size: 20),
                                    SizedBox(width: 10),
                                    Text("READ-ONLY MODE", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: _systemActive ? sjvnBlue.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _systemActive ? sjvnBlue : Colors.red),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text("System Operational", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: canEdit ? Colors.white : Colors.grey)),
                                  Switch(
                                    value: _systemActive, 
                                    activeThumbColor: sjvnBlue, 
                                    onChanged: canEdit ? (val) => setState(() => _systemActive = val) : null
                                  )
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("AI Liveness Strictness", style: TextStyle(fontSize: 14, color: canEdit ? Colors.white70 : Colors.white30)),
                                Text("${(_liveness * 100).toInt()}%", style: TextStyle(fontWeight: FontWeight.bold, color: canEdit ? sjvnOrange : Colors.grey)),
                              ],
                            ),
                            Slider(
                              value: _liveness, min: 0.0, max: 1.0, divisions: 100, activeColor: sjvnOrange,
                              onChanged: canEdit ? (val) => setState(() => _liveness = val) : null,
                            ),
                          ],
                        ),
                      ),
                      
                      const Divider(color: Colors.white24, thickness: 1),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("ACTIVE SITES", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: sjvnBlue.withValues(alpha: canEdit ? 0.2 : 0.05), 
                                foregroundColor: canEdit ? sjvnBlue : Colors.grey, 
                                elevation: 0
                              ),
                              icon: const Icon(Icons.add_location_alt, size: 18),
                              label: const Text("New Site"),
                              onPressed: canEdit ? _showAddLocationDialog : null,
                            )
                          ],
                        ),
                      ),
                      
                      ListView.builder(
                        physics: const NeverScrollableScrollPhysics(), 
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        itemCount: _locations.length,
                        itemBuilder: (context, index) {
                          final loc = _locations[index];
                          return Card(
                            color: Colors.grey.shade900,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.white12)),
                            child: ListTile(
                              leading: CircleAvatar(backgroundColor: canEdit ? sjvnBlue : Colors.grey.shade800, child: const Icon(Icons.business, color: Colors.white, size: 20)),
                              title: Text(loc['name'], style: TextStyle(fontWeight: FontWeight.bold, color: canEdit ? Colors.white : Colors.white70)),
                              subtitle: Text("Radius: ${loc['radius']}m\nLat: ${loc['latitude']} | Lon: ${loc['longitude']}", style: const TextStyle(fontSize: 12, color: Colors.white54)),
                              trailing: IconButton(
                                icon: Icon(Icons.delete_outline, color: canEdit ? Colors.redAccent : Colors.white24),
                                onPressed: canEdit ? () => setState(() => _locations.removeAt(index)) : null,
                              ),
                            ),
                          );
                        },
                      ),

                      if (canEdit) ...[
                        const Divider(color: Colors.white24, thickness: 1, height: 40),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("SYSTEM ACCESS", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.white54)),
                              const SizedBox(height: 15),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    backgroundColor: Colors.white10,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  icon: const Icon(Icons.shield),
                                  label: const Text("Create New Administrator", style: TextStyle(fontWeight: FontWeight.bold)),
                                  onPressed: _showAddAdminDialog,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    backgroundColor: sjvnBlue.withValues(alpha: 0.15),
                                    foregroundColor: sjvnBlue,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(color: sjvnBlue.withValues(alpha: 0.5)),
                                    ),
                                  ),
                                  icon: const Icon(Icons.person_add),
                                  label: const Text("Register New Employee", style: TextStyle(fontWeight: FontWeight.bold)),
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const RegistrationScreen()),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 30),
                            ],
                          ),
                        )
                      ]

                    ],
                  ),
                ),
              ),
            ],
        ),
    );
  }
}
