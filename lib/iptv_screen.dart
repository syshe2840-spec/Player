import 'dart:io';
import 'package:flutter/material.dart';
import 'iptv_service.dart';
import 'player.dart';
import 'l10n.dart';

const kAccent = Color(0xFF7C3AED);
const kBg = Color(0xFF08080F);
const kCard = Color(0xFF12121C);
const kBorder = Color(0xFF232350);

class IptvScreen extends StatefulWidget {
  const IptvScreen({super.key});
  @override State<IptvScreen> createState() => _IptvScreenState();
}

class _IptvScreenState extends State<IptvScreen> with SingleTickerProviderStateMixin {
  List<IptvAccount> _accounts = [];
  IptvAccount? _current;
  late TabController _tab;

  bool _refreshing = false;
  String _lastRefreshStr = '';
  int _refreshKey = 0;

  @override void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _loadAccounts();
  }

  Future<void> _refresh({bool manual = false}) async {
    if (_current == null || _refreshing) return;
    final should = manual || await IptvService.shouldRefresh(_current!);
    if (!should) return;
    setState(() => _refreshing = true);
    try {
      await IptvService.setLastRefresh(_current!);
      final last = await IptvService.getLastRefresh(_current!);
      if (mounted) setState(() {
        _refreshing = false;
        _refreshKey++;
        _lastRefreshStr = last != null ? '${last.hour.toString().padLeft(2,'0')}:${last.minute.toString().padLeft(2,'0')}' : '';
      });
      // rebuild tabs
      _tab.index = _tab.index; // force rebuild
      if (mounted) setState(() {});
    } catch (_) { if (mounted) setState(() => _refreshing = false); }
  }

  void _showRefreshSettings() {
    if (_current == null) return;
    final intervals = {-1: 'Never', 0: 'Every open', 60: '1 hour', 120: '2 hours', 360: '6 hours', 720: '12 hours', 1440: '24 hours'};
    showModalBottomSheet(context: context, backgroundColor: kCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(builder: (ctx, ss) => Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        const Text('Auto Refresh', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        if (_lastRefreshStr.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4),
          child: Text('Last refresh: $_lastRefreshStr', style: const TextStyle(color: Colors.white38, fontSize: 12))),
        const SizedBox(height: 8),
        ...intervals.entries.map((e) => FutureBuilder<int>(
          future: IptvService.getRefreshInterval(_current!),
          builder: (ctx, snap) {
            final cur = snap.data ?? 0;
            return ListTile(dense: true,
              leading: Icon(cur == e.key ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                color: cur == e.key ? kAccent : Colors.white38, size: 20),
              title: Text(e.value, style: TextStyle(color: cur == e.key ? Colors.white : Colors.white60, fontSize: 13)),
              onTap: () async {
                await IptvService.setRefreshInterval(_current!, e.key);
                ss(() {});
              });
          })),
        const SizedBox(height: 8),
        SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: Row(children: [
          Expanded(child: FilledButton.icon(
            onPressed: () { Navigator.pop(ctx); _refresh(manual: true); },
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Refresh Now'),
            style: FilledButton.styleFrom(backgroundColor: kAccent))),
        ]))),
      ])));
  }
  @override void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _loadAccounts() async {
    final a = await IptvService.getAccounts();
    setState(() { _accounts = a; if (a.isNotEmpty) _current = a.first; });
  }

  void _play(String url, String title,
      {List<Map<String,String>>? channels, int chanIdx=0, bool isLive=false}) {
    Navigator.push(context, MaterialPageRoute(builder: (_) =>
      PlayerScreen(
        playlist: [File(url)], playlistIndex: 0,
        isLive: isLive, isOnlineUrl: true,
        channelList: channels,
        channelIndex: chanIdx)));
  }

  void _showAddAccount() {
    bool isM3u = false;
    final nameCtrl = TextEditingController();
    final m3uCtrl = TextEditingController();
    final serverCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool testing = false;
    String? err;

    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: kCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => StatefulBuilder(builder: (ctx, ss) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, top: 16, left: 16, right: 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Add IPTV', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          // toggle
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: () => ss(() => isM3u = false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: !isM3u ? kAccent : const Color(0xFF2A2A3A),
                  borderRadius: BorderRadius.circular(8)),
                child: const Text('Xtream Codes', textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))))),
            const SizedBox(width: 8),
            Expanded(child: GestureDetector(
              onTap: () => ss(() => isM3u = true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isM3u ? kAccent : const Color(0xFF2A2A3A),
                  borderRadius: BorderRadius.circular(8)),
                child: const Text('M3U Playlist', textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))))),
          ]),
          const SizedBox(height: 12),
          _field(nameCtrl, 'Name (optional)', Icons.label_rounded),
          const SizedBox(height: 8),
          if (isM3u) ...[
            _field(m3uCtrl, 'M3U URL (http://...)', Icons.link_rounded),
          ] else ...[
            _field(serverCtrl, 'Server URL (http://myiptv.com:8080)', Icons.dns_rounded),
            const SizedBox(height: 8),
            _field(userCtrl, 'Username', Icons.person_rounded),
            const SizedBox(height: 8),
            _field(passCtrl, 'Password', Icons.lock_rounded, obscure: true),
          ],
          if (err != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(err!, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton(
              onPressed: testing ? null : () async {
                ss(() { testing = true; err = null; });
                if (isM3u) {
                  // M3U — ذخیره مستقیم بدون تست
                  final url = m3uCtrl.text.trim();
                  if (url.isEmpty || !url.startsWith('http')) {
                    ss(() { testing = false; err = 'Enter a valid M3U URL'; });
                    return;
                  }
                  final acc = IptvAccount(
                    name: nameCtrl.text.isEmpty ? 'M3U Playlist' : nameCtrl.text,
                    server: url, username: '__m3u__', password: '');
                  await IptvService.saveAccount(acc);
                  Navigator.pop(ctx);
                  await _loadAccounts();
                } else {
                  final acc = IptvAccount(
                    name: nameCtrl.text.isEmpty ? serverCtrl.text : nameCtrl.text,
                    server: serverCtrl.text.trim(),
                    username: userCtrl.text.trim(),
                    password: passCtrl.text.trim());
                  final ok = await IptvService.testAccount(acc);
                  if (ok) {
                    await IptvService.saveAccount(acc);
                    Navigator.pop(ctx);
                    await _loadAccounts();
                  } else { ss(() { testing = false; err = 'Connection failed — check server/user/pass'; }); }
                }
              },
              style: FilledButton.styleFrom(backgroundColor: kAccent),
              child: testing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(isM3u ? 'Add' : 'Connect'))),
          ]),
          const SizedBox(height: 16),
        ]))));
  }

  Widget _field(TextEditingController c, String hint, IconData icon, {bool obscure=false}) =>
    TextField(controller: c, obscureText: obscure, style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
        prefixIcon: Icon(icon, size: 18, color: Colors.white38),
        filled: true, fillColor: const Color(0xFF1A1A2A),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)));

  @override Widget build(BuildContext context) => Scaffold(
    resizeToAvoidBottomInset: true,
    backgroundColor: kBg,
    appBar: AppBar(
      backgroundColor: kBg,
      title: const Text('IPTV', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      actions: [
        if (_accounts.isNotEmpty) PopupMenuButton<IptvAccount>(
          icon: const Icon(Icons.switch_account_rounded, color: Colors.white70),
          color: kCard,
          onSelected: (a) => setState(() => _current = a),
          itemBuilder: (_) => _accounts.map((a) =>
            PopupMenuItem(value: a, child: Text(a.name, style: const TextStyle(color: Colors.white)))).toList()),
        IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
          onPressed: _current == null ? null : () => _refresh(manual: true)),
        IconButton(icon: const Icon(Icons.timer_rounded, color: Colors.white54),
          onPressed: _current == null ? null : () => _showRefreshSettings()),
        IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.white54),
          onPressed: _current == null ? null : () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: const Color(0xFF1A1A2A),
                title: const Text('Delete Account?', style: TextStyle(color: Colors.white, fontSize: 16)),
                content: Text('Remove "${_current!.name}"?\nThis cannot be undone.',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false),
                    child: const Text('No', style: TextStyle(color: Colors.white54))),
                  FilledButton(onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('Yes, Delete')),
                ]));
            if (confirm != true) return;
            await IptvService.deleteAccount(_current!);
            await _loadAccounts();
            // اگه لیست خالی شد → به صفحه اول برگرد
            if (_accounts.isEmpty && mounted) {
              setState(() { _current = null; });
            }
          }),
        IconButton(icon: const Icon(Icons.add_rounded, color: Colors.white),
          onPressed: _showAddAccount),
      ],
      bottom: _current == null ? null : TabBar(
        controller: _tab,
        indicatorColor: kAccent,
        tabs: const [
          Tab(text: 'Live TV', icon: Icon(Icons.live_tv_rounded, size: 16)),
          Tab(text: 'Movies', icon: Icon(Icons.movie_rounded, size: 16)),
          Tab(text: 'Series', icon: Icon(Icons.video_library_rounded, size: 16)),
        ])),
    body: SafeArea(
      bottom: true, minimum: const EdgeInsets.only(bottom: 16),
      child: _current == null
      ? _emptyState()
      : TabBarView(controller: _tab, children: [
          _LiveTab(account: _current!, onPlay: _play, key: ValueKey(_refreshKey)),
          _VodTab(account: _current!, onPlay: _play, key: ValueKey(_refreshKey)),
          _SeriesTab(account: _current!, onPlay: _play, key: ValueKey(_refreshKey)),
        ])));

  Widget _emptyState() => SafeArea(
    child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.live_tv_rounded, size: 64, color: Colors.white12),
    const SizedBox(height: 16),
    const Text('No IPTV account', style: TextStyle(color: Colors.white54, fontSize: 16)),
    const SizedBox(height: 8),
    const Text('Add your Xtream Codes account\nor M3U playlist', style: TextStyle(color: Colors.white38, fontSize: 13), textAlign: TextAlign.center),
    const SizedBox(height: 24),
    FilledButton.icon(onPressed: _showAddAccount,
      icon: const Icon(Icons.add_rounded), label: const Text('Add Account'),
      style: FilledButton.styleFrom(backgroundColor: kAccent)),
    const SizedBox(height: 32),
  ])));
}

// ── Live TV ──
class _LiveTab extends StatefulWidget {
  final IptvAccount account; final void Function(String, String, {List<Map<String,String>>? channels, int chanIdx, bool isLive}) onPlay;
  const _LiveTab({super.key, required this.account, required this.onPlay});
  @override State<_LiveTab> createState() => _LiveTabState();
}
class _LiveTabState extends State<_LiveTab> {
  List<IptvCategory> _cats = [];
  List<IptvChannel> _channels = [];
  List<IptvChannel> _filtered = [];
  IptvCategory? _selCat;
  bool _loading = true, _showGrid = true;
  String _search = '';

  @override void initState() { super.initState(); _loadWithRefresh(); }

  Future<void> _loadWithRefresh() async {
    final should = await IptvService.shouldRefresh(widget.account);
    if (should) await IptvService.setLastRefresh(widget.account);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (widget.account.username == '__m3u__') {
        // M3U playlist
        _channels = await IptvService.parseM3U(widget.account.server);
        // دسته‌بندی‌ها از groupTitle
        final cats = _channels.map((c) => c.categoryId).toSet()
          .where((c) => c.isNotEmpty).toList();
        _cats = cats.map((c) => IptvCategory(c, c)).toList();
      } else {
        _cats = await IptvService.getLiveCategories(widget.account);
        _channels = await IptvService.getLiveStreams(widget.account);
      }
      _applyFilter();
    } catch (e) { if (mounted) setState(() => _loading = false); }
    if (mounted) setState(() => _loading = false);
  }

  void _applyFilter() {
    var list = _channels;
    if (_selCat != null) list = list.where((c) => c.categoryId == _selCat!.id).toList();
    if (_search.isNotEmpty) list = list.where((c) => c.name.toLowerCase().contains(_search.toLowerCase())).toList();
    _filtered = list;
  }

  @override Widget build(BuildContext context) {
    final kb = MediaQuery.of(context).viewInsets.bottom;
    // اگه گروهی انتخاب نشده → نمایش گروه‌ها به صورت grid
    if (_showGrid && _cats.isNotEmpty) {
      return _buildGroupGrid();
    }
    return PopScope(
      canPop: _cats.isEmpty,  // اگه کانالی لود نشد، back کار کنه
      onPopInvokedWithResult: (did, __) { if (!did) setState(() { _showGrid = true; _selCat = null; _search = ''; _applyFilter(); }); },
      child: _loading ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back', style: TextStyle(color: Colors.white70))),
      ])) : Column(children: [
        // search + back to groups
        Padding(padding: EdgeInsets.only(left:10, right:10, top:10, bottom: kb > 0 ? 0 : 10),
          child: Row(children: [
            if (_selCat != null) IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white),
              onPressed: () => setState(() { _showGrid = true; _selCat = null; _search = ''; _applyFilter(); }),
              padding: EdgeInsets.zero, constraints: const BoxConstraints()),
            const SizedBox(width: 8),
            Expanded(child: TextField(
              onChanged: (v) => setState(() { _search = v; _applyFilter(); }),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: _selCat != null ? _selCat!.name : 'All Channels | همه کانال‌ها',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Colors.white38),
                filled: true, fillColor: kCard,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 8)))),
          ])),
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 16),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: _filtered.length,
          itemBuilder: (_, i) {
            final ch = _filtered[i];
            return ListTile(
              dense: true,
              leading: ch.logo.isNotEmpty
                ? ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(ch.logo, width: 52, height: 36, fit: BoxFit.contain, errorBuilder: (_,__,___) => const Icon(Icons.live_tv_rounded, color: Colors.white38, size: 28)))
                : const Icon(Icons.live_tv_rounded, color: Colors.white38, size: 28),
              title: Text(ch.name, style: const TextStyle(color: Colors.white, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => widget.onPlay(ch.url, ch.name, channels: _channels.map((c)=>{'url':c.url,'name':c.name}).toList(), chanIdx: _channels.indexOf(ch), isLive: true));
          })),
      ]));
  }

  Widget _buildGroupGrid() {
    // تعداد کانال هر گروه
    Map<String, int> countMap = {};
    for (final ch in _channels) { countMap[ch.categoryId] = (countMap[ch.categoryId] ?? 0) + 1; }
    final allCats = [IptvCategory('__all__', 'All Channels | همه کانال‌ها'), ..._cats];
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(10,10,10,6),
        child: TextField(
          onChanged: (v) => setState(() { _search = v; if (v.isNotEmpty) { _selCat = null; _applyFilter(); } }),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'جستجو در کانال‌ها...', hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
            prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Colors.white38),
            filled: true, fillColor: kCard,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 8)))),
      Padding(padding: const EdgeInsets.fromLTRB(10,0,10,6),
        child: Row(children: [
          const Icon(Icons.grid_view_rounded, size: 14, color: Colors.white38),
          const SizedBox(width: 6),
          Text('${_cats.length} گروه', style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ])),
      Expanded(child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(10,0,10,20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 2.2, mainAxisSpacing: 10, crossAxisSpacing: 10),
        itemCount: allCats.length,
        itemBuilder: (_, i) {
          final cat = allCats[i];
          final count = cat.id == '__all__' ? _channels.length : (countMap[cat.id] ?? 0);
          return GestureDetector(
            onTap: () => setState(() {
              _showGrid = false;
              _selCat = cat.id == '__all__' ? null : cat;
              _search = '';
              _applyFilter();
              if (cat.id == '__all__') _filtered = List.from(_channels);
            }),
            child: Container(
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kBorder),
                boxShadow: [BoxShadow(color: kAccent.withOpacity(0.08), blurRadius: 12, offset: const Offset(0,4))]),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Container(width: 36, height: 36,
                  decoration: BoxDecoration(color: kAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                  child: Icon(cat.id == '__all__' ? Icons.live_tv_rounded : Icons.folder_rounded,
                    color: kAccent, size: 18)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(cat.name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('$count کانال', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                ])),
              ])));
        })),
    ]);
  }

  Widget _catChip(IptvCategory? cat, String label) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: GestureDetector(
      onTap: () => setState(() { _selCat = cat; _applyFilter(); }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _selCat?.id == cat?.id && (_selCat != null || cat == null) ? kAccent : kCard,
          borderRadius: BorderRadius.circular(16)),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)))));
}

// ── Movies ──

class _VodTab extends StatefulWidget {
  final IptvAccount account; final void Function(String, String, {List<Map<String,String>>? channels, int chanIdx, bool isLive}) onPlay;
  const _VodTab({super.key, required this.account, required this.onPlay});
  @override State<_VodTab> createState() => _VodTabState();
}
class _VodTabState extends State<_VodTab> {
  List<IptvCategory> _cats = [];
  List<IptvVod> _vods = [], _filtered = [];
  IptvCategory? _selCat;
  bool _loading = true, _showGrid = true;
  String _search = '';

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _cats = await IptvService.getVodCategories(widget.account);
      _vods = await IptvService.getVodStreams(widget.account);
      _applyFilter();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }
  void _applyFilter() {
    var list = _vods;
    if (_selCat != null) list = list.where((v) => v.categoryId == _selCat!.id).toList();
    if (_search.isNotEmpty) list = list.where((v) => v.name.toLowerCase().contains(_search.toLowerCase())).toList();
    _filtered = list;
  }

  @override Widget build(BuildContext context) {
    if (_showGrid && _cats.isNotEmpty) {
      return _buildGroupGrid();
    }
    return _loading ? const Center(child: CircularProgressIndicator())
    : Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(10,10,10,6),
          child: Row(children: [
            if (_selCat != null) IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white),
              onPressed: () => setState(() { _selCat = null; _search = ''; _applyFilter(); }),
              padding: EdgeInsets.zero, constraints: const BoxConstraints()),
            if (_selCat != null) const SizedBox(width: 8),
            Expanded(child: TextField(onChanged: (v) => setState(() { _search=v; _applyFilter(); }),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: _selCat?.name ?? 'جستجوی فیلم...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Colors.white38),
                filled: true, fillColor: kCard,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 8)))),
          ])),
        Expanded(child: GridView.builder(
          padding: const EdgeInsets.only(left: 10, right: 10, bottom: 16),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, childAspectRatio: 0.7, crossAxisSpacing: 10, mainAxisSpacing: 10),
          itemCount: _filtered.length,
          itemBuilder: (_, i) {
            final v = _filtered[i];
            return GestureDetector(
              onTap: () => widget.onPlay(v.url, v.name),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(8),
                  child: v.poster.isNotEmpty
                    ? Image.network(v.poster, fit: BoxFit.cover, width: double.infinity,
                        errorBuilder: (_,__,___) => Container(color: kCard, child: const Icon(Icons.movie_rounded, color: Colors.white12, size: 36)))
                    : Container(color: kCard, child: const Icon(Icons.movie_rounded, color: Colors.white12, size: 36)))),
                const SizedBox(height: 4),
                Text(v.name, style: const TextStyle(color: Colors.white70, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
              ]));
          })),
      ]);
  }

  Widget _buildGroupGrid() {
    Map<String,int> countMap = {};
    for (final v in _vods) { countMap[v.categoryId] = (countMap[v.categoryId]??0)+1; }
    final allCats = [IptvCategory('__all__','All Movies | همه فیلم‌ها'), ..._cats];
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(10,10,10,6),
        child: TextField(onChanged: (v) => setState(() { _search=v; if (v.isNotEmpty) { _selCat=null; _applyFilter(); } }),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(hintText: 'جستجوی فیلم...', hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
            prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Colors.white38),
            filled: true, fillColor: kCard,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 8)))),
      Padding(padding: const EdgeInsets.fromLTRB(10,0,10,6),
        child: Row(children: [const Icon(Icons.grid_view_rounded,size:14,color:Colors.white38),const SizedBox(width:6),
          Text('${_cats.length} دسته‌بندی',style:const TextStyle(color:Colors.white38,fontSize:12))])),
      Expanded(child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(10,0,10,20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 2.2, mainAxisSpacing: 10, crossAxisSpacing: 10),
        itemCount: allCats.length,
        itemBuilder: (_, i) {
          final cat = allCats[i];
          final count = cat.id=='__all__' ? _vods.length : (countMap[cat.id]??0);
          return GestureDetector(
            onTap: () => setState(() { _showGrid=false; _selCat=cat.id=='__all__'?null:cat; _search=''; _applyFilter(); if(cat.id=='__all__')_filtered=List.from(_vods); }),
            child: Container(
              decoration: BoxDecoration(color:kCard,borderRadius:BorderRadius.circular(12),border:Border.all(color:kBorder),
                boxShadow:[BoxShadow(color:kAccent.withOpacity(0.08),blurRadius:12,offset:const Offset(0,4))]),
              padding: const EdgeInsets.symmetric(horizontal:12,vertical:10),
              child: Row(children: [
                Container(width:36,height:36,decoration:BoxDecoration(color:kAccent.withOpacity(0.15),borderRadius:BorderRadius.circular(8)),
                  child:Icon(cat.id=='__all__'?Icons.movie_rounded:Icons.folder_rounded,color:kAccent,size:18)),
                const SizedBox(width:10),
                Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[
                  Text(cat.name,style:const TextStyle(color:Colors.white,fontSize:12,fontWeight:FontWeight.w600),maxLines:1,overflow:TextOverflow.ellipsis),
                  Text('$count فیلم',style:const TextStyle(color:Colors.white38,fontSize:10)),
                ])),
              ])));
        })),
    ]);
  }

}

// ── Series ──
class _SeriesTab extends StatefulWidget {
  final IptvAccount account; final void Function(String, String, {List<Map<String,String>>? channels, int chanIdx, bool isLive}) onPlay;
  const _SeriesTab({super.key, required this.account, required this.onPlay});
  @override State<_SeriesTab> createState() => _SeriesTabState();
}
class _SeriesTabState extends State<_SeriesTab> {
  List<IptvCategory> _cats = [];
  List<IptvSeries> _series = [], _filtered = [];
  IptvCategory? _selCat;
  bool _loading = true, _showGrid = true;
  String _search = '';

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _cats = await IptvService.getSeriesCategories(widget.account);
      _series = await IptvService.getSeries(widget.account);
      _applyFilter();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }
  void _applyFilter() {
    var list = _series;
    if (_selCat != null) list = list.where((s) => s.categoryId == _selCat!.id).toList();
    _filtered = _search.isEmpty ? list : list.where((s) => s.name.toLowerCase().contains(_search.toLowerCase())).toList();
  }

  @override Widget build(BuildContext context) {
    if (_showGrid && _cats.isNotEmpty) return _buildGroupGrid();
    return PopScope(
      canPop: _cats.isEmpty,
      onPopInvokedWithResult: (did, __) { if (!did) setState(() { _showGrid=true; _selCat=null; _search=''; _applyFilter(); }); },
      child: _loading ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back', style: TextStyle(color: Colors.white70))),
      ])) : Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(10,10,10,6),
          child: Row(children: [
            if (_cats.isNotEmpty) IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white),
              onPressed: () => setState(() { _showGrid=true; _selCat=null; _search=''; _applyFilter(); }),
              padding: EdgeInsets.zero, constraints: const BoxConstraints()),
            if (_cats.isNotEmpty) const SizedBox(width: 8),
            Expanded(child: TextField(onChanged: (v) => setState(() { _search=v; _applyFilter(); }),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: _selCat?.name ?? 'All Series | همه سریال‌ها',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Colors.white38),
                filled: true, fillColor: kCard,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 8)))),
          ])),
        Expanded(child: GridView.builder(
          padding: const EdgeInsets.only(left: 10, right: 10, top: 6, bottom: 16),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, childAspectRatio: 0.7, crossAxisSpacing: 10, mainAxisSpacing: 10),
          itemCount: _filtered.length,
          itemBuilder: (_, i) {
            final s = _filtered[i];
            return GestureDetector(
              onTap: () => _showEpisodes(s),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(8),
                  child: s.poster.isNotEmpty
                    ? Image.network(s.poster, fit: BoxFit.cover, width: double.infinity,
                        errorBuilder: (_,__,___) => Container(color: kCard, child: const Icon(Icons.video_library_rounded, color: Colors.white12, size: 36)))
                    : Container(color: kCard, child: const Icon(Icons.video_library_rounded, color: Colors.white12, size: 36)))),
                const SizedBox(height: 4),
                Text(s.name, style: const TextStyle(color: Colors.white70, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
              ]));
          })),
      ]));
  }

  Widget _buildGroupGrid() {
    Map<String,int> countMap = {};
    for (final s in _series) { countMap[s.categoryId] = (countMap[s.categoryId]??0)+1; }
    final allCats = [IptvCategory('__all__','All Series | همه سریال‌ها'), ..._cats];
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(10,10,10,6),
        child: TextField(onChanged: (v) { setState(() { _search=v; if(v.isNotEmpty){_showGrid=false;_selCat=null;} }); _applyFilter(); },
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(hintText: 'جستجوی سریال...', hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
            prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Colors.white38),
            filled: true, fillColor: kCard,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 8)))),
      Expanded(child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(10,0,10,20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 2.2, mainAxisSpacing: 10, crossAxisSpacing: 10),
        itemCount: allCats.length,
        itemBuilder: (_, i) {
          final cat = allCats[i];
          final count = cat.id=='__all__' ? _series.length : (countMap[cat.id]??0);
          return GestureDetector(
            onTap: () => setState(() { _showGrid=false; _selCat=cat.id=='__all__'?null:cat; _search=''; _applyFilter(); if(cat.id=='__all__')_filtered=List.from(_series); }),
            child: Container(
              decoration: BoxDecoration(color:kCard,borderRadius:BorderRadius.circular(12),border:Border.all(color:kBorder),
                boxShadow:[BoxShadow(color:kAccent.withOpacity(0.08),blurRadius:12,offset:const Offset(0,4))]),
              padding: const EdgeInsets.symmetric(horizontal:12,vertical:10),
              child: Row(children: [
                Container(width:36,height:36,decoration:BoxDecoration(color:kAccent.withOpacity(0.15),borderRadius:BorderRadius.circular(8)),
                  child:Icon(cat.id=='__all__'?Icons.video_library_rounded:Icons.folder_rounded,color:kAccent,size:18)),
                const SizedBox(width:10),
                Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[
                  Text(cat.name,style:const TextStyle(color:Colors.white,fontSize:12,fontWeight:FontWeight.w600),maxLines:1,overflow:TextOverflow.ellipsis),
                  Text('$count سریال',style:const TextStyle(color:Colors.white38,fontSize:10)),
                ])),
              ])));
        })),
    ]);
  }

  void _showEpisodes(IptvSeries s) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: kCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _EpisodesSheet(account: widget.account, series: s, onPlay: widget.onPlay));
  }
}

class _EpisodesSheet extends StatefulWidget {
  final IptvAccount account; final IptvSeries series;
  final void Function(String, String, {List<Map<String,String>>? channels, int chanIdx, bool isLive}) onPlay;
  const _EpisodesSheet({super.key, required this.account, required this.series, required this.onPlay});
  @override State<_EpisodesSheet> createState() => _EpisodesSheetState();
}
class _EpisodesSheetState extends State<_EpisodesSheet> {
  List<IptvEpisode> _episodes = [];
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try { _episodes = await IptvService.getSeriesEpisodes(widget.account, widget.series.id); } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }
  @override Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: 0.7, maxChildSize: 0.95, expand: false,
    builder: (_, sc) => Column(children: [
      Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Text(widget.series.name, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold))),
      if (_loading) const Expanded(child: Center(child: CircularProgressIndicator()))
      else Expanded(child: ListView.builder(controller: sc, itemCount: _episodes.length,
        itemBuilder: (_, i) {
          final ep = _episodes[i];
          return ListTile(dense: true,
            leading: CircleAvatar(backgroundColor: kAccent.withOpacity(0.2), radius: 18,
              child: Text('${ep.episode}', style: const TextStyle(color: Colors.white, fontSize: 11))),
            title: Text('S${ep.season}E${ep.episode} — ${ep.title}', style: const TextStyle(color: Colors.white, fontSize: 12)),
            onTap: () { Navigator.pop(context); widget.onPlay(ep.url, ep.title); });
        })),
    ]));
}
