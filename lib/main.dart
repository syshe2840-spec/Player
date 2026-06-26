import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'browser.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Color(0xFF08080F),
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'پلیر',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C3AED),
          brightness: Brightness.dark,
        ).copyWith(
          background: const Color(0xFF08080F),
          surface: const Color(0xFF0E0E1A),
          primary: const Color(0xFF7C3AED),
          secondary: const Color(0xFF0EA5E9),
        ),
        scaffoldBackgroundColor: const Color(0xFF08080F),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF08080F),
          surfaceTintColor: Colors.transparent,
          elevation: 0, scrolledUnderElevation: 0,
          foregroundColor: Colors.white,
          titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w600,
              letterSpacing: 0.3, color: Colors.white),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFF0D0D1E),
          modalBackgroundColor: Color(0xFF0D0D1E),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: const Color(0xFF7C3AED),
          inactiveTrackColor: Colors.white.withOpacity(0.12),
          thumbColor: Colors.white,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5, elevation: 0),
          overlayShape: SliderComponentShape.noOverlay,
          trackHeight: 2.5,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: MaterialStateProperty.resolveWith((s) =>
              s.contains(MaterialState.selected) ? Colors.white : const Color(0xFF888888)),
          trackColor: MaterialStateProperty.resolveWith((s) =>
              s.contains(MaterialState.selected) ? const Color(0xFF7C3AED) : const Color(0xFF2A2A4A)),
          trackOutlineColor: MaterialStateProperty.all(Colors.transparent),
        ),
        segmentedButtonTheme: const SegmentedButtonThemeData(
          style: ButtonStyle(
            backgroundColor: MaterialStatePropertyAll(Color(0xFF1A1A2E)),
            foregroundColor: MaterialStatePropertyAll(Colors.white),
            side: MaterialStatePropertyAll(BorderSide(color: Color(0xFF3B3B5E))),
          ),
        ),
        dividerColor: const Color(0xFF1A1A35),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFF0D0D1E),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          iconColor: Color(0xFF94A3B8),
        ),
        chipTheme: const ChipThemeData(
          backgroundColor: Color(0xFF1A1A2E),
          side: BorderSide(color: Color(0xFF3B3B5E), width: 0.5),
          labelStyle: TextStyle(fontSize: 12),
        ),
        iconTheme: const IconThemeData(color: Color(0xFFCBD5E1)),
        textTheme: const TextTheme(
          titleMedium: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.2),
          bodySmall: TextStyle(color: Color(0xFF94A3B8)),
        ),
        popupMenuTheme: const PopupMenuThemeData(
          color: Color(0xFF161628),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF7C3AED),
            foregroundColor: Colors.white,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF3B3B5E)),
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF7C3AED)),
        ),
      ),
      builder: (ctx, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const BrowserScreen(),
    );
  }
}

