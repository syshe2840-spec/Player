import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'browser.dart';
import 'store.dart';
import 'api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// نمایش snackbar که همیشه بالای navbar میاد
void showSnack(BuildContext ctx, String msg, {
  Color color = const Color(0xFF7C3AED),
  int seconds = 5,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: color,
    duration: Duration(seconds: seconds),
    behavior: SnackBarBehavior.floating,
    margin: EdgeInsets.only(
      bottom: MediaQuery.of(ctx).padding.bottom + 72,
      left: 16, right: 16,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    action: actionLabel != null ? SnackBarAction(
      label: actionLabel,
      textColor: Colors.white,
      onPressed: onAction ?? () {},
    ) : null,
  ));
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Store.load();
  await ApiService.init();
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
      title: 'Vezoo',
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
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        ),
      ),
      builder: (ctx, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const _HomeWrapper(),
    );
  }
}

// ── Wrapper: startup check برای آپدیت و اعلان ──
class _HomeWrapper extends StatefulWidget {
  const _HomeWrapper();
  @override State<_HomeWrapper> createState()=>_HomeWrapperState();
}
class _HomeWrapperState extends State<_HomeWrapper>{
  @override void initState(){
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_)=>_startup());
  }

  Future<void> _startup()async{
    ApiService.sendStat('open');
    await Future.delayed(const Duration(seconds:2));
    if(!mounted)return;
    // چک آپدیت
    final cfg=await ApiService.getConfig();
    if(cfg!=null&&mounted){
      final force=cfg['force_update']=='1';
      if(ApiService.isNewer(cfg['app_version']??'',ApiService.appVersion)){
        await _showUpdate(cfg,force);
      }
    }
    if(!mounted)return;
    // چک اعلان
    final ann=await ApiService.getAnnouncement();
    if(ann!=null&&mounted)await _showAnnounce(ann);
  }

  Future<void> _showUpdate(Map cfg,bool force)async{
    await showDialog(context:context,barrierDismissible:!force,builder:(ctx)=>AlertDialog(
      title:Text(cfg['update_title']??'بروزرسانی'),
      content:Text(cfg['update_message']??'نسخه جدید منتشر شد'),
      actions:[
        if(!force)TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('بعداً')),
        FilledButton(onPressed:()async{
          final url=cfg['download_url']??'';
          if(url.isNotEmpty)await launchUrl(Uri.parse(url),mode:LaunchMode.externalApplication);
          if(mounted&&!force)Navigator.pop(ctx);
        },child:const Text('دانلود')),
      ],
    ));
  }

  Future<void> _showAnnounce(Map ann)async{
    // چک تعداد نمایش
    final annId=ann['id']?.toString()??'0';
    final maxShows=(ann['max_shows']??1) as int;
    final prefs=await SharedPreferences.getInstance();
    final showKey='ann_shown_\$annId';
    final shownCount=prefs.getInt(showKey)??0;
    if(maxShows>0&&shownCount>=maxShows)return; // به حد رسیده
    await prefs.setInt(showKey,shownCount+1); // یه بار دیگه نشون داده شد

    final cancel=(ann['cancellable']??1).toString()!='0';
    await showDialog(context:context,barrierDismissible:cancel,builder:(ctx)=>AlertDialog(
      title:Text(ann['title']??''),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        if((ann['image_url']??'').isNotEmpty)ClipRRect(
          borderRadius:BorderRadius.circular(8),
          child:Image.network(ann['image_url'],height:160,fit:BoxFit.cover,
            errorBuilder:(_,__,___)=>const SizedBox())),
        if((ann['message']??'').isNotEmpty)Padding(
          padding:const EdgeInsets.only(top:12),child:Text(ann['message'])),
      ]),
      actions:[
        if(cancel)TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('بستن')),
        if((ann['link']??'').isNotEmpty)FilledButton(
          onPressed:()async{
            await launchUrl(Uri.parse(ann['link']),mode:LaunchMode.externalApplication);
            if(mounted)Navigator.pop(ctx);
          },child:Text(ann['link_text']??'مشاهده')),
      ],
    ));
  }

  @override Widget build(BuildContext ctx)=>const BrowserScreen();
}

