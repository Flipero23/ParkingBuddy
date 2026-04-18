import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/map_screen.dart';
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

class ParkingBuddyApp extends StatelessWidget {
  const ParkingBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ParkingBuddy',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const MapScreen(),
    );
  }
}
