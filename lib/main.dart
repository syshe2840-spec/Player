// lib/main.dart — نقطه ورود
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'browser.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'پلیر زیرنویس',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xFF6C63FF),
      scaffoldBackgroundColor: const Color(0xFF101014),
    ),
    builder: (ctx, child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!),
    home: const BrowserScreen(),
  );
}

