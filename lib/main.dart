import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('user_box');
  final settingsBox = await Hive.openBox('settings_box');

  final bool isSetupDone = settingsBox.get('is_setup_done', defaultValue: false);
  final bool isLoggedIn = settingsBox.get('is_logged_in', defaultValue: false);

  String initialRoute = '/perm';
  if (isSetupDone) {
    if (isLoggedIn) {
      initialRoute = '/dash';
    } else {
      initialRoute = '/login';
    }
  }

  runApp(SkyNetApp(initialRoute: initialRoute));
}

class SkyNetApp extends StatelessWidget {
  final String initialRoute;

  const SkyNetApp({
    super.key,
    required this.initialRoute,
  });

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 690),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'SkyNet WiFi',
          theme: ThemeData(
            scaffoldBackgroundColor: const Color(0xFF0D0E15),
            useMaterial3: true,
          ),
          initialRoute: initialRoute,
          onGenerateRoute: (settings) {
            Widget targetPage;
            switch (settings.name) {
              case '/perm':
                targetPage = const PermScreen();
                break;
              case '/login':
                targetPage = const LoginScreen();
                break;
              case '/dash':
                targetPage = const DashScreen();
                break;
              default:
                targetPage = const SkyNetHubView();
            }
            return PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  SkyNetResponsiveLayout(child: targetPage),
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
            );
          },
        );
      },
    );
  }
}

class SkyNetResponsiveLayout extends StatelessWidget {
  final Widget child;

  const SkyNetResponsiveLayout({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0E15),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 600) {
            return SafeArea(
              child: child,
            );
          } else if (constraints.maxWidth <= 1024) {
            return SafeArea(
              child: Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: Container(
                      color: const Color(0xFF0D0E15),
                      child: Center(
                        child: Image.asset(
                          'assets/images/icon.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: child,
                  ),
                ],
              ),
            );
          } else {
            return SafeArea(
              child: Row(
                children: [
                  Flexible(
                    flex: 1,
                    child: Container(
                      color: const Color(0xFF0D0E15),
                      child: Center(
                        child: Image.asset(
                          'assets/images/icon.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: child,
                  ),
                ],
              ),
            );
          }
        },
      ),
    );
  }
}

class SkyNetHubView extends StatelessWidget {
  const SkyNetHubView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0E15),
      body: Center(
        child: Image.asset(
          'assets/images/icon.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class PermScreen extends StatelessWidget {
  const PermScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D0E15),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: Center(
                child: Image.asset(
                  'assets/images/icon.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Flexible(
              flex: 1,
              child: Text(
                'SKYNET PERMISSIONS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D0E15),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: Center(
                child: Image.asset(
                  'assets/images/icon.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Flexible(
              flex: 1,
              child: Text(
                'SKYNET LOGIN',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DashScreen extends StatelessWidget {
  const DashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D0E15),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: Center(
                child: Image.asset(
                  'assets/images/icon.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Flexible(
              flex: 1,
              child: Text(
                'SKYNET DASHBOARD',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}