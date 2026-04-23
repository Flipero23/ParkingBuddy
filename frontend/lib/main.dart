import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/map_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/auth_service.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const ParkingBuddyApp());
}

class ParkingBuddyApp extends StatefulWidget {
  const ParkingBuddyApp({super.key});

  @override
  State<ParkingBuddyApp> createState() => _ParkingBuddyAppState();
}

class _ParkingBuddyAppState extends State<ParkingBuddyApp> {
  final AuthService _authService = AuthService();
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _authService.loadFromStorage();
    if (!mounted) return;
    setState(() => _initializing = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ParkingBuddy',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: _initializing
          ? const _SplashScreen()
          : _authService.isLoggedIn
              ? MapScreen(authService: _authService)
              : WelcomeScreen(authService: _authService),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      ),
    );
  }
}
