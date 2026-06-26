// lib/settings.dart — تنظیمات پلیر
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'store.dart';

class PlayerSettings extends StatefulWidget {
  final VideoSettings vs;
  final ValueChanged<VideoSettings> onChanged;
  final bool sub1Visible, sub2Visible;
  final ValueChanged<bool> onSub1Visible, onSub2Visible;
  final String? sub2Path;
  final int subDelayMs, subDelay2Ms, audioDelayMs;
  final ValueChanged<int> onSubDelayMs, onSubDelay2Ms, onAudioDelayMs;
  final Color color2;
  final ValueChanged<Color> onColor2;
  final VoidCallback onPickSub1, onPickSub2, onPickFont, onSaveForVideo;
  final double speed, ampVolume;
  final ValueChanged<double> onSpeed, onAmpVolume;

  const PlayerSettings({
    super.key,
    required this.vs, required this.onChanged,
    required this.sub1Visible, required this.onSub1Visible,
    required this.sub2Visible, required this.onSub2Visible,
    this.sub2Path,
    required this.subDelayMs, required this.onSubDelayMs,
    required this.subDelay2Ms, required this.onSubDelay2Ms,
    required this.audioDelayMs, required this.onAudioDelayMs,
    required this.color2, required this.onColor2,
    required this.onPickSub1, required this.onPickSub2,
    required this.onPickFont, required this.onSaveForVideo,
    required this.speed, required this.onSpeed,
    required this.ampVolume, required this.onAmpVolume,
  });

  @override State<PlayerSettings> createState()=>_SettingsState();
}

class _SettingsState extends State<PlayerSettings> with SingleTickerProviderStateMixin{
  late TabController _tab;
  late VideoSettings _vs;
  late int _sd1, _sd2, _ad;
  late Color _c2;
  late double _speed, _amp;
  late bool _s1v, _s2v;

  final List<Color> _textColors=const[Colors.white,Color(0xFFFFEB3B),Color(0xFF69F0AE),Color(0xFF40C4FF),Color(0xFFFF8A65),Color(0xFFFF80AB)];
  final List<Color> _bgColors=const[Colors.black,Color(0xFF0D1B2A),Color(0xFF1B2E1B),Color(0xFF2A1B1B),Color(0xFF1B1B2E),Colors.transparent];

  final TextEditingController _d1Ctrl=TextEditingController();
  final TextEditingController _d2Ctrl=TextEditingController();
  final TextEditingController _adCtrl=TextEditingController();

  @override
  void initState(){
    super.initState();
    _tab=TabController(length:4,vsync:this);
    _vs=widget.vs;_sd1=widget.subDelayMs;_sd2=widget.subDelay2Ms;_ad=widget.audioDelayMs;
    _c2=widget.color2;_speed=widget.speed;_amp=widget.ampVolume;
    _s1v=widget.sub1Visible;_s2v=widget.sub2Visible;
    _d1Ctrl.text='$_sd1';_d2Ctrl.text='$_sd2';_adCtrl.text='$_ad';
  }
  @override void dispose(){_tab.dispose();_d1Ctrl.dispose();_d2Ctrl.dispose();_adCtrl.dispose();super.dispose();}

  void _ch(VoidCallback fn){fn();setState((){});widget.onChanged(_vs);}

  @override
  Widget build(BuildContext context){
    return Column(mainAxisSize:MainAxisSize.min,children:[
      const SizedBox(height:10),
      Center(child:Container(width:40,height:4,decoration:BoxDecoration(color:Colors.white24,borderRadius:BorderRadius.circular(2)))),
      TabBar(controller:_tab,isScrollable:true,tabs:const[
        Tab(text:'زیرنویس',icon:Icon(Icons.subtitles,size:16)),
        Tab(text:'صدا / پخش',icon:Icon(Icons.volume_up,size:16)),
        Tab(text:'زیرنویس ۲',icon:Icon(Icons.subtitles_outlined,size:16)),
        Tab(text:'سایر',icon:Icon(Icons.more_horiz,size:16)),
      ]),
      SizedBox(height:MediaQuery.of(context).size.height*0.48,child:TabBarView(controller:_tab,children:[
        _sub1Tab(),_audioTab(),_sub2Tab(),_otherTab(),
      ])),
      SizedBox(height:MediaQuery.of(context).viewPadding.bottom+4),
    ]);
  }

  // ──────── تب زیرنویس ۱ ────────
  Widget _sub1Tab()=>SingleChildScrollView(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('نمایش زیرنویس'),value:_s1v,
        onChanged:(v){setState(()=>_s1v=v);widget.onSub1Visible(v);}),

    // اندازه فونت
    Text('اندازه فونت: ${_vs.fontSize.round()}'),
    Slider(min:6,max:100,value:_vs.fontSize,onChanged:(v)=>_ch(()=>_vs.fontSize=v)),

    SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Bold (پررنگ)'),value:_vs.bold,
        onChanged:(v)=>_ch(()=>_vs.bold=v)),

    // دیلی زیرنویس با عدد
    const Text('دیلی زیرنویس (ms):'),const SizedBox(height:6),
    Row(children:[
      IconButton(icon:const Icon(Icons.remove),onPressed:(){setState(()=>_sd1-=100);widget.onSubDelayMs(_sd1);_d1Ctrl.text='$_sd1';}),
      Expanded(child:TextField(controller:_d1Ctrl,keyboardType:const TextInputType.numberWithOptions(signed:true),
        textAlign:TextAlign.center,
        onChanged:(v){final n=int.tryParse(v);if(n!=null){setState(()=>_sd1=n);widget.onSubDelayMs(n);}},
        decoration:const InputDecoration(suffixText:'ms',border:OutlineInputBorder(),isDense:true))),
      IconButton(icon:const Icon(Icons.add),onPressed:(){setState(()=>_sd1+=100);widget.onSubDelayMs(_sd1);_d1Ctrl.text='$_sd1';}),
    ]),
    Slider(min:-10000,max:10000,value:_sd1.toDouble().clamp(-10000,10000),
        onChanged:(v){setState(()=>_sd1=v.round());widget.onSubDelayMs(_sd1);_d1Ctrl.text='$_sd1';}),

    // موقعیت
    Text('موقعیت از پایین: ${_vs.bottomPadding.round()}px'),
    Slider(min:0,max:900,value:_vs.bottomPadding.clamp(0,900),onChanged:(v)=>_ch(()=>_vs.bottomPadding=v)),

    const SizedBox(height:8),const Text('چینش'),const SizedBox(height:8),
    SegmentedButton<int>(
      segments:const[
        ButtonSegment(value:1,label:Text('راست'),icon:Icon(Icons.format_align_right,size:16)),
        ButtonSegment(value:2,label:Text('وسط'),icon:Icon(Icons.format_align_center,size:16)),
        ButtonSegment(value:0,label:Text('چپ'),icon:Icon(Icons.format_align_left,size:16)),
      ],
      selected:{_vs.textAlign},onSelectionChanged:(s)=>_ch(()=>_vs.textAlign=s.first),
    ),

    const SizedBox(height:12),const Text('رنگ متن'),const SizedBox(height:8),
    Wrap(spacing:10,children:_textColors.map((c)=>GestureDetector(onTap:()=>_ch(()=>_vs.textColor=c.value),
      child:Container(width:34,height:34,decoration:BoxDecoration(color:c,shape:BoxShape.circle,
          border:Border.all(color:c.value==_vs.textColor?Colors.white:Colors.transparent,width:3))))).toList()),

    const SizedBox(height:12),const Text('رنگ پس‌زمینه'),const SizedBox(height:8),
    Wrap(spacing:10,children:_bgColors.map((c){
      final sel=c.value==_vs.bgColor;
      return GestureDetector(onTap:()=>_ch(()=>_vs.bgColor=c.value),child:Container(width:34,height:34,
        decoration:BoxDecoration(color:c==Colors.transparent?null:c,shape:BoxShape.circle,
            border:Border.all(color:sel?Colors.white:Colors.white24,width:sel?3:1)),
        child:c==Colors.transparent?const Center(child:Icon(Icons.block,size:18,color:Colors.white38)):null));
    }).toList()),
    Text('شفافیت پس‌زمینه: ${(_vs.bgOpacity*100).round()}%'),
    Slider(min:0,max:1,value:_vs.bgOpacity,onChanged:(v)=>_ch(()=>_vs.bgOpacity=v)),

    const Divider(height:20),const Text('فونت'),const SizedBox(height:8),
    // فونت‌های پیش‌فرض
    Wrap(spacing:8,runSpacing:6,children:kDefaultFonts.map(((String label,String family) f)=>ChoiceChip(
      label:Text(f.$1,style:TextStyle(fontFamily:f.$2.isEmpty?null:f.$2)),
      selected:_vs.fontFamily==f.$2,
      onSelected:(_)=>_ch(()=>_vs.fontFamily=f.$2),
    )).toList()),
    const SizedBox(height:8),
    OutlinedButton.icon(onPressed:(){Navigator.pop(context);widget.onPickFont();},
        icon:const Icon(Icons.font_download),label:const Text('فونت دلخواه از فایل (TTF/OTF)')),

    const Divider(height:20),
    // ابزارهای زیرنویس زنده
    const Text('ابزارهای زیرنویس زنده'),const SizedBox(height:8),
    Row(children:[
      Expanded(child:OutlinedButton.icon(icon:const Icon(Icons.copy,size:16),label:const Text('کپی'),
          onPressed:(){Navigator.pop(context);})),
      const SizedBox(width:8),
      Expanded(child:OutlinedButton.icon(icon:const Icon(Icons.translate,size:16),label:const Text('ترجمه'),
          onPressed:(){
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('متن زیرنویس را کپی کرده و در اپ ترجمه paste کنید')));
          })),
      const SizedBox(width:8),
      Expanded(child:OutlinedButton.icon(icon:const Icon(Icons.book,size:16),label:const Text('دیکشنری'),
          onPressed:(){
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('متن را کپی کرده و در دیکشنری جستجو کنید')));
          })),
    ]),

    const Divider(height:20),
    OutlinedButton.icon(onPressed:(){Navigator.pop(context);widget.onPickSub1();},
        icon:const Icon(Icons.file_open),label:const Text('انتخاب زیرنویس ۱')),
  ]));

  // ──────── تب صدا / پخش ────────
  Widget _audioTab()=>SingleChildScrollView(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    // دیلی صدا
    const Text('دیلی صدا (ms):'),const SizedBox(height:6),
    Row(children:[
      IconButton(icon:const Icon(Icons.remove),onPressed:(){setState(()=>_ad-=100);widget.onAudioDelayMs(_ad);_adCtrl.text='$_ad';}),
      Expanded(child:TextField(controller:_adCtrl,keyboardType:const TextInputType.numberWithOptions(signed:true),
        textAlign:TextAlign.center,
        onChanged:(v){final n=int.tryParse(v);if(n!=null){setState(()=>_ad=n);widget.onAudioDelayMs(n);}},
        decoration:const InputDecoration(suffixText:'ms',border:OutlineInputBorder(),isDense:true,
            helperText:'فقط برای نمایش — نیاز به آپگرید media_kit دارد'))),
      IconButton(icon:const Icon(Icons.add),onPressed:(){setState(()=>_ad+=100);widget.onAudioDelayMs(_ad);_adCtrl.text='$_ad';}),
    ]),

    const Divider(height:24),
    // تقویت صدا
    const Text('تقویت صدا:'),
    Text('${_amp.round()}%',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
    Slider(min:100,max:300,value:_amp,onChanged:(v){setState(()=>_amp=v);widget.onAmpVolume(v);}),

    const Divider(height:24),
    // سرعت
    Text('سرعت: ${_speed%1==0?_speed.toInt():_speed}x'),
    Slider(min:0.25,max:10,divisions:39,value:_speed,
        onChanged:(v){final s=(v*4).round()/4;setState(()=>_speed=s);widget.onSpeed(s);_ch(()=>_vs.speed=s);}),
    Wrap(spacing:6,children:[0.5,1.0,1.5,2.0,3.0,5.0,10.0].map((s)=>ChoiceChip(
      label:Text('${s%1==0?s.toInt():s}x'),selected:_speed==s,
      onSelected:(_){setState(()=>_speed=s);widget.onSpeed(s);_ch(()=>_vs.speed=s);})).toList()),

    const Divider(height:24),
    // حالت شب
    Text('حالت شب: ${(_vs.nightOpacity*100).round()}%'),
    Slider(min:0,max:1,value:_vs.nightOpacity,activeColor:Colors.orange,onChanged:(v)=>_ch(()=>_vs.nightOpacity=v)),
  ]));

  // ──────── تب زیرنویس ۲ ────────
  Widget _sub2Tab()=>SingleChildScrollView(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('زیرنویس ۲ (همزمان)'),value:_s2v,
        onChanged:(v){setState(()=>_s2v=v);widget.onSub2Visible(v);}),
    OutlinedButton.icon(onPressed:(){Navigator.pop(context);widget.onPickSub2();},
        icon:const Icon(Icons.file_open),label:const Text('بارگذاری زیرنویس ۲')),
    if(widget.sub2Path!=null)Text('فایل: ${widget.sub2Path!.split('/').last}',style:const TextStyle(fontSize:11,color:Colors.white54)),
    const SizedBox(height:12),
    const Text('دیلی زیرنویس ۲ (ms):'),const SizedBox(height:6),
    Row(children:[
      IconButton(icon:const Icon(Icons.remove),onPressed:(){setState(()=>_sd2-=100);widget.onSubDelay2Ms(_sd2);_d2Ctrl.text='$_sd2';}),
      Expanded(child:TextField(controller:_d2Ctrl,keyboardType:const TextInputType.numberWithOptions(signed:true),
        textAlign:TextAlign.center,
        onChanged:(v){final n=int.tryParse(v);if(n!=null){setState(()=>_sd2=n);widget.onSubDelay2Ms(n);}},
        decoration:const InputDecoration(suffixText:'ms',border:OutlineInputBorder(),isDense:true))),
      IconButton(icon:const Icon(Icons.add),onPressed:(){setState(()=>_sd2+=100);widget.onSubDelay2Ms(_sd2);_d2Ctrl.text='$_sd2';}),
    ]),
    Slider(min:-10000,max:10000,value:_sd2.toDouble().clamp(-10000,10000),
        onChanged:(v){setState(()=>_sd2=v.round());widget.onSubDelay2Ms(_sd2);_d2Ctrl.text='$_sd2';}),
    const SizedBox(height:12),
    const Text('رنگ زیرنویس ۲'),const SizedBox(height:8),
    Wrap(spacing:10,children:[Colors.white,const Color(0xFFFFEB3B),const Color(0xFF69F0AE),const Color(0xFF40C4FF),const Color(0xFFFF8A65)].map((c)=>
      GestureDetector(onTap:(){setState(()=>_c2=c);widget.onColor2(c);},
        child:Container(width:34,height:34,decoration:BoxDecoration(color:c,shape:BoxShape.circle,
            border:Border.all(color:c.value==_c2.value?Colors.white:Colors.transparent,width:3))))).toList()),
  ]));

  // ──────── تب سایر ────────
  Widget _otherTab()=>SingleChildScrollView(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    FilledButton.icon(onPressed:widget.onSaveForVideo,icon:const Icon(Icons.save),
        label:const Text('ذخیره تنظیمات برای این ویدیو')),
    const SizedBox(height:6),
    const Text('با زدن این دکمه، همه تنظیمات زیرنویس و پخش فعلی برای این ویدیو ذخیره می‌شود.',
        style:TextStyle(fontSize:12,color:Colors.white54)),
    const Divider(height:28),
    const Text('راهنما',style:TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:8),
    _helpRow('↔ کشیدن افقی','جلو/عقب بردن ویدیو'),
    _helpRow('↕ کشیدن چپ','تنظیم نور صفحه'),
    _helpRow('↕ کشیدن راست','تنظیم صدای گوشی'),
    _helpRow('↕ کشیدن پایین صفحه','جابجایی زیرنویس'),
    _helpRow('🤏 دو انگشت','زوم و جابجایی'),
    _helpRow('دو ضربه چپ','۱۰ ثانیه عقب'),
    _helpRow('دو ضربه راست','۱۰ ثانیه جلو'),
    _helpRow('دو ضربه وسط','پخش / توقف'),
    _helpRow('نگه داشتن','پخش / توقف'),
  ]));

  Widget _helpRow(String key,String val)=>Padding(
    padding:const EdgeInsets.symmetric(vertical:3),
    child:Row(children:[
      SizedBox(width:160,child:Text(key,style:const TextStyle(color:Colors.white70,fontSize:12))),
      Text(val,style:const TextStyle(color:Colors.white54,fontSize:12)),
    ]),
  );
}

