import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';
import 'dart:async';

import 'core/local_store.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
bool _hasSupabase = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: FyTheme.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  if (_supabaseUrl.startsWith('https://') && _supabaseAnonKey.isNotEmpty) {
    try {
      await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseAnonKey);
      _hasSupabase = true;
    } catch (_) {
      _hasSupabase = false;
    }
  }
  runApp(const FyfaceApp());
}

class FyTheme {
  static const bg = Color(0xFF0F1115);
  static const surface = Color(0xFF1B1F27);
  static const elevated = Color(0xFF232833);
  static const border = Color(0xFF2A303D);
  static const blue = Color(0xFF3B82F6);
  static const blueLight = Color(0xFF60A5FA);
  static const text = Color(0xFFF9FAFB);
  static const muted = Color(0xFF9CA3AF);
  static const faint = Color(0xFF6B7280);
  static const green = Color(0xFF10B981);
  static const orange = Color(0xFFF59E0B);
  static const purple = Color(0xFF8B5CF6);

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(primary: blue, surface: surface),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
          bodyColor: text,
          displayColor: text,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: elevated,
          hintStyle: const TextStyle(color: faint),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: blue, width: 1.5)),
        ),
      );
}

class FyfaceApp extends StatelessWidget {
  const FyfaceApp({super.key});
  static final _router = GoRouter(
    redirect: (context, state) {
      if (!_hasSupabase) return null;
      final signedIn = Supabase.instance.client.auth.currentSession != null;
      final atLogin = state.matchedLocation == '/auth/login';
      if (!signedIn && !atLogin) return '/auth/login';
      if (signedIn && atLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', pageBuilder: (context, state) => _fadePage(state, const FyfaceHome())),
      GoRoute(path: '/auth/login', pageBuilder: (context, state) => _fadePage(state, const LoginScreen())),
    ],
    errorBuilder: (context, state) => const Scaffold(body: Center(child: Text('Page introuvable'))),
  );
  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Fyface',
        debugShowCheckedModeBanner: false,
        theme: FyTheme.dark,
        routerConfig: _router,
      );
}

CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) => CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
        child: child,
      ),
    );

class DocumentItem {
  DocumentItem(this.name, this.category, this.date, this.icon, this.color, {this.size = 'PDF · 2,4 Mo', this.localPath});
  final String name, category, date, size;
  final String? localPath;
  final IconData icon;
  final Color color;
}

class FyfaceHome extends StatefulWidget {
  const FyfaceHome({super.key});
  @override
  State<FyfaceHome> createState() => _FyfaceHomeState();
}

class _FyfaceHomeState extends State<FyfaceHome> {
  int _tab = 0;
  bool _offline = false;
  StreamSubscription<List<ConnectivityResult>>? _networkSubscription;
  final _code = TextEditingController();
  final Set<String> _sharedDocuments = {'Curriculum vitæ', 'Diplôme de licence'};
  final List<DocumentItem> _documents = [
    DocumentItem('Curriculum vitæ', 'Candidature', 'Modifié hier', Icons.description_rounded, FyTheme.blue),
    DocumentItem('Diplôme de licence', 'Diplôme', 'Ajouté le 12 mai', Icons.school_rounded, FyTheme.purple),
    DocumentItem('Attestation de travail', 'Attestation', 'Ajouté le 04 mai', Icons.verified_user_rounded, FyTheme.green),
  ];

  @override
  void initState() {
    super.initState();
    _watchConnectivity();
    _restoreDocuments();
  }

  Future<void> _watchConnectivity() async {
    final connectivity = Connectivity();
    try {
      final current = await connectivity.checkConnectivity();
      if (mounted) setState(() => _offline = current.isEmpty || current.contains(ConnectivityResult.none));
      if (!_offline) _syncPendingDocuments();
      _networkSubscription = connectivity.onConnectivityChanged.listen((results) {
        final offline = results.isEmpty || results.contains(ConnectivityResult.none);
        if (mounted) setState(() => _offline = offline);
        if (!offline) _syncPendingDocuments();
      }, onError: (_) {
        if (mounted) setState(() => _offline = true);
      });
    } catch (_) {
      if (mounted) setState(() => _offline = true);
    }
  }

  Future<void> _restoreDocuments() async {
    try {
      final rows = await LocalStore.instance.documents();
      if (!mounted || rows.isEmpty) return;
      setState(() {
        for (final row in rows.reversed) {
          _documents.insert(0, DocumentItem(
            row['name'] as String,
            row['category'] as String,
            'Enregistré sur cet appareil',
            Icons.description_rounded,
            FyTheme.blue,
            localPath: row['local_path'] as String?,
          ));
        }
      });
    } catch (_) {
      if (mounted) _message('Impossible de charger les documents locaux.');
    }
  }

  Future<void> _syncPendingDocuments() async {
    if (!_hasSupabase) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final pending = await LocalStore.instance.pendingDocuments();
      for (final row in pending) {
        final id = row['id'] as String;
        final localPath = row['local_path'] as String?;
        if (localPath == null || !await File(localPath).exists()) continue;
        final extension = localPath.contains('.') ? localPath.split('.').last.toLowerCase() : 'bin';
        final storagePath = '${user.id}/$id.$extension';
        final mime = switch (extension) {
          'pdf' => 'application/pdf',
          'jpg' || 'jpeg' => 'image/jpeg',
          'png' => 'image/png',
          _ => 'application/octet-stream',
        };
        final client = Supabase.instance.client;
        await client.storage.from('fyface-documents').upload(
          storagePath,
          File(localPath),
          fileOptions: FileOptions(contentType: mime, upsert: true),
        );
        await client.from('documents').upsert({
          'id': id,
          'owner_id': user.id,
          'name': row['name'],
          'category': row['category'],
          'storage_path': storagePath,
          'mime_type': mime,
        });
        await LocalStore.instance.markDocumentSynced(id, storagePath, user.id);
      }
    } catch (_) {
      // Keep pending records in SQLite; the connectivity listener retries later.
    }
  }

  @override
  void dispose() { _code.dispose(); _networkSubscription?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _homePage(),
      _documentsPage(),
      _accessPage(),
      _profilePage(),
    ];
    return Scaffold(
      body: SafeArea(child: Column(children: [
        if (_offline) _offlineBanner(),
        Expanded(child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
          child: KeyedSubtree(key: ValueKey(_tab), child: pages[_tab]),
        )),
      ])),
      bottomNavigationBar: _navigation(),
      floatingActionButton: _tab < 2 ? FloatingActionButton(
        onPressed: _addDocument,
        backgroundColor: FyTheme.blue,
        foregroundColor: Colors.white,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: const Icon(Icons.add_rounded, size: 28),
      ) : null,
    );
  }

  Widget _navigation() => Container(
    decoration: const BoxDecoration(color: FyTheme.bg, border: Border(top: BorderSide(color: FyTheme.border))),
    child: NavigationBar(
      height: 70,
      backgroundColor: FyTheme.bg,
      indicatorColor: FyTheme.blue.withValues(alpha: .16),
      selectedIndex: _tab,
      onDestinationSelected: (i) => setState(() => _tab = i),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard_rounded), label: 'Accueil'),
        NavigationDestination(icon: Icon(Icons.folder_open_outlined), selectedIcon: Icon(Icons.folder_rounded), label: 'Documents'),
        NavigationDestination(icon: Icon(Icons.key_outlined), selectedIcon: Icon(Icons.key_rounded), label: 'Accès'),
        NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profil'),
      ],
    ),
  );

  Widget _homePage() => ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 100), children: [
    _topBar(),
    const SizedBox(height: 26),
    const Text('Bonjour, Aïcha 👋', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700, letterSpacing: -.6)),
    const SizedBox(height: 5),
    const Text('Tous tes documents importants, au même endroit.', style: TextStyle(color: FyTheme.muted, fontSize: 13)),
    const SizedBox(height: 22),
    _shareCard(),
    const SizedBox(height: 22),
    Row(children: [Expanded(child: _statCard(Icons.folder_rounded, '${_documents.length}', 'Documents', FyTheme.blue)), const SizedBox(width: 12), Expanded(child: _statCard(Icons.remove_red_eye_outlined, '12', 'Consultations', FyTheme.green))]),
    const SizedBox(height: 26),
    _sectionTitle('Documents récents', 'Tout voir', () => setState(() => _tab = 1)),
    const SizedBox(height: 11),
    ..._documents.take(3).map((d) => _documentTile(d)),
    const SizedBox(height: 20),
    _sectionTitle('Dernières consultations', 'Historique', () => setState(() => _tab = 2)),
    const SizedBox(height: 11),
    _accessLog('Mariam K.', 'Curriculum vitæ · Diplôme', 'Aujourd’hui, 10:42', FyTheme.purple),
    _accessLog('Cabinet RH Bénin', 'Curriculum vitæ', 'Hier, 16:08', FyTheme.blue),
  ]).animate().fadeIn(duration: 260.ms);

  Widget _topBar() => Row(children: [
    Container(width: 42, height: 42, decoration: BoxDecoration(color: FyTheme.blue.withValues(alpha: .16), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.shield_rounded, color: FyTheme.blueLight)),
    const SizedBox(width: 10),
    const Text('fyface', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -.8)),
    const Spacer(),
    IconButton(onPressed: () => _message(_offline ? 'Tes documents locaux restent disponibles hors connexion.' : 'Connexion réseau disponible.'), tooltip: _offline ? 'Hors connexion' : 'Connecté', icon: Icon(_offline ? Icons.cloud_off_rounded : Icons.cloud_done_outlined, color: _offline ? FyTheme.orange : FyTheme.muted)),
    Container(width: 38, height: 38, decoration: BoxDecoration(color: FyTheme.purple.withValues(alpha: .22), borderRadius: BorderRadius.circular(14)), child: const Center(child: Text('AD', style: TextStyle(color: FyTheme.blueLight, fontWeight: FontWeight.bold, fontSize: 12)))),
  ]);

  Widget _shareCard() => Container(
    padding: const EdgeInsets.all(19),
    decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF1D4ED8), Color(0xFF2563EB), Color(0xFF3B82F6)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(22), boxShadow: [BoxShadow(color: FyTheme.blue.withValues(alpha: .20), blurRadius: 25, offset: const Offset(0, 12))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Icon(Icons.lock_outline_rounded, size: 17, color: Colors.white70), const SizedBox(width: 7), const Text('TON ESPACE SÉCURISÉ', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.1)), const Spacer(), Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(20)), child: const Text('●  Protégé', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)))]),
      const SizedBox(height: 15),
      const Text('Partage tes documents\nen toute confiance.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20, height: 1.2, letterSpacing: -.35)),
      const SizedBox(height: 17),
      Row(children: [
        Expanded(child: Container(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12), decoration: BoxDecoration(color: Colors.black.withValues(alpha: .16), borderRadius: BorderRadius.circular(13)), child: const Row(children: [Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 20), SizedBox(width: 9), Text('FY-8K2M-94', style: TextStyle(color: Colors.white, fontFamily: 'monospace', letterSpacing: 1.3, fontWeight: FontWeight.w700, fontSize: 14)), Spacer(), Icon(Icons.copy_rounded, size: 16, color: Colors.white70)]))),
        const SizedBox(width: 9),
        Material(color: Colors.white, borderRadius: BorderRadius.circular(13), child: InkWell(onTap: _shareCode, borderRadius: BorderRadius.circular(13), child: const Padding(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 13), child: Row(children: [Icon(Icons.ios_share_rounded, size: 16, color: FyTheme.blue), SizedBox(width: 6), Text('Partager', style: TextStyle(color: FyTheme.blue, fontWeight: FontWeight.w700, fontSize: 12))])))),
      ]),
      const SizedBox(height: 9),
      const Text('Gère les documents visibles depuis l’onglet Accès.', style: TextStyle(color: Colors.white70, fontSize: 11)),
    ]),
  );

  Widget _statCard(IconData icon, String value, String label, Color color) => Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: FyTheme.surface, border: Border.all(color: FyTheme.border), borderRadius: BorderRadius.circular(18)), child: Row(children: [Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 19)), const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)), Text(label, style: const TextStyle(fontSize: 11, color: FyTheme.muted))]) ]));

  Widget _sectionTitle(String title, String action, VoidCallback onTap) => Row(children: [Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))), TextButton(onPressed: onTap, style: TextButton.styleFrom(foregroundColor: FyTheme.blueLight, padding: EdgeInsets.zero), child: Text(action, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)))]);

  Widget _documentTile(DocumentItem d) => Container(margin: const EdgeInsets.only(bottom: 9), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: FyTheme.surface, border: Border.all(color: FyTheme.border), borderRadius: BorderRadius.circular(16)), child: Row(children: [Container(width: 43, height: 43, decoration: BoxDecoration(color: d.color.withValues(alpha: .14), borderRadius: BorderRadius.circular(13)), child: Icon(d.icon, color: d.color, size: 21)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)), const SizedBox(height: 3), Text('${d.category}  ·  ${d.date}', style: const TextStyle(color: FyTheme.muted, fontSize: 10))])), const Icon(Icons.more_horiz_rounded, color: FyTheme.faint)]));

  Widget _accessLog(String name, String docs, String date, Color color) => Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11), decoration: BoxDecoration(color: FyTheme.surface, border: Border.all(color: FyTheme.border), borderRadius: BorderRadius.circular(15)), child: Row(children: [CircleAvatar(radius: 19, backgroundColor: color.withValues(alpha: .18), child: Text(name[0], style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13))), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)), const SizedBox(height: 3), Text(docs, style: const TextStyle(color: FyTheme.muted, fontSize: 10))])), Column(crossAxisAlignment: CrossAxisAlignment.end, children: [const Icon(Icons.check_circle_rounded, color: FyTheme.green, size: 15), const SizedBox(height: 3), Text(date, style: const TextStyle(color: FyTheme.faint, fontSize: 9))]) ]));

  Widget _documentsPage() => ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 100), children: [
    _topBar(), const SizedBox(height: 27), const Text('Mes documents', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700)), const SizedBox(height: 5), const Text('Tes pièces conservées en toute sécurité.', style: TextStyle(color: FyTheme.muted, fontSize: 13)), const SizedBox(height: 20),
    const TextField(decoration: InputDecoration(prefixIcon: Icon(Icons.search_rounded, color: FyTheme.faint), hintText: 'Rechercher un document')),
    const SizedBox(height: 15), Wrap(spacing: 8, children: ['Tout', 'Diplômes', 'CV', 'Attestations'].map((s) => Chip(label: Text(s, style: const TextStyle(fontSize: 11)), backgroundColor: s == 'Tout' ? FyTheme.blue.withValues(alpha: .18) : FyTheme.surface, side: BorderSide(color: s == 'Tout' ? FyTheme.blue.withValues(alpha: .4) : FyTheme.border))).toList()),
    const SizedBox(height: 9), ..._documents.map((d) => _documentTile(d)),
    const SizedBox(height: 10), OutlinedButton.icon(onPressed: _addDocument, icon: const Icon(Icons.add_rounded), label: const Text('Ajouter un document'), style: OutlinedButton.styleFrom(foregroundColor: FyTheme.blueLight, side: const BorderSide(color: FyTheme.border), padding: const EdgeInsets.symmetric(vertical: 15))),
  ]);

  Widget _accessPage() => ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 40), children: [
    _topBar(), const SizedBox(height: 27), const Text('Accès & partage', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700)), const SizedBox(height: 5), const Text('Choisis les pièces visibles avec ton code.', style: TextStyle(color: FyTheme.muted, fontSize: 13)), const SizedBox(height: 19),
    OutlinedButton.icon(onPressed: _openCode, icon: const Icon(Icons.key_rounded), label: const Text('Saisir un code reçu'), style: OutlinedButton.styleFrom(foregroundColor: FyTheme.blueLight, side: const BorderSide(color: FyTheme.border), padding: const EdgeInsets.symmetric(vertical: 14))),
    _shareCard(), const SizedBox(height: 22), const Text('Documents partagés', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)), const SizedBox(height: 11),
    ..._documents.map((d) => _permissionTile(d)), const SizedBox(height: 19),
    const Text('Historique de consultation', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)), const SizedBox(height: 11),
    _accessLog('Mariam K.', 'Curriculum vitæ · Diplôme', 'Aujourd’hui, 10:42', FyTheme.purple), _accessLog('Cabinet RH Bénin', 'Curriculum vitæ', 'Hier, 16:08', FyTheme.blue), _accessLog('Code FY-4P8X', 'Attestation de travail', '02 juin, 09:15', FyTheme.orange),
    const SizedBox(height: 10), const Text('Un code peut être désactivé à tout moment. Chaque accès est enregistré.', textAlign: TextAlign.center, style: TextStyle(color: FyTheme.faint, fontSize: 11)),
  ]);

  Widget _permissionTile(DocumentItem d) => Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), decoration: BoxDecoration(color: FyTheme.surface, border: Border.all(color: FyTheme.border), borderRadius: BorderRadius.circular(15)), child: Row(children: [Icon(d.icon, color: d.color, size: 19), const SizedBox(width: 10), Expanded(child: Text(d.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))), Switch(value: _sharedDocuments.contains(d.name), activeThumbColor: FyTheme.blue, onChanged: (v) => setState(() { if (v) { _sharedDocuments.add(d.name); } else { _sharedDocuments.remove(d.name); } }))]));

  Widget _profilePage() => ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 40), children: [
    _topBar(), const SizedBox(height: 28), Center(child: Column(children: [CircleAvatar(radius: 40, backgroundColor: FyTheme.purple.withValues(alpha: .2), child: const Text('AD', style: TextStyle(color: FyTheme.blueLight, fontSize: 24, fontWeight: FontWeight.w700))), const SizedBox(height: 11), const Text('Aïcha Dossou', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 19)), const SizedBox(height: 4), const Text('aicha.dossou@email.com', style: TextStyle(color: FyTheme.muted, fontSize: 12))])), const SizedBox(height: 25),
    _settingRow(Icons.person_outline_rounded, 'Informations personnelles', 'Nom, email, téléphone'), _settingRow(Icons.lock_outline_rounded, 'Sécurité et connexion', 'Mot de passe, authentification'), _settingRow(Icons.notifications_none_rounded, 'Notifications', 'Alertes de consultation'), _settingRow(Icons.cloud_outlined, 'Synchronisation', 'SQLite · Supabase'), _settingRow(Icons.help_outline_rounded, 'Aide et assistance', 'Questions fréquentes'),
    const SizedBox(height: 18), OutlinedButton.icon(onPressed: () async { final router = GoRouter.of(context); if (_hasSupabase) await Supabase.instance.client.auth.signOut(); router.go('/auth/login'); }, icon: const Icon(Icons.logout_rounded), label: const Text('Se déconnecter'), style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFEF4444), side: const BorderSide(color: FyTheme.border), padding: const EdgeInsets.symmetric(vertical: 15))),
    const SizedBox(height: 15), const Center(child: Text('Fyface · Version 1.0.0', style: TextStyle(color: FyTheme.faint, fontSize: 10))),
  ]);

  Widget _settingRow(IconData icon, String title, String subtitle) => Container(margin: const EdgeInsets.only(bottom: 9), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: FyTheme.surface, border: Border.all(color: FyTheme.border), borderRadius: BorderRadius.circular(15)), child: Row(children: [Icon(icon, color: FyTheme.blueLight, size: 20), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(color: FyTheme.muted, fontSize: 10))])), const Icon(Icons.chevron_right_rounded, color: FyTheme.faint)]));

  Widget _offlineBanner() => Container(width: double.infinity, color: FyTheme.orange.withValues(alpha: .16), padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.cloud_off_rounded, size: 14, color: FyTheme.orange), SizedBox(width: 8), Text('Hors connexion · modifications gardées sur cet appareil', style: TextStyle(color: FyTheme.orange, fontSize: 11, fontWeight: FontWeight.w600))]));

  Future<void> _addDocument() async {
    final result = await showModalBottomSheet<AddDocumentResult>(context: context, isScrollControlled: true, backgroundColor: FyTheme.surface, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))), builder: (ctx) => const AddDocumentSheet());
    if (result == null || !mounted) return;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final id = const Uuid().v4();
      final source = File(result.path);
      if (await source.length() > 10 * 1024 * 1024) {
        _message('Le fichier dépasse la limite de 10 Mo.');
        return;
      }
      final extension = result.path.contains('.') ? '.${result.path.split('.').last}' : '';
      final storedPath = '${directory.path}${Platform.pathSeparator}$id$extension';
      await source.copy(storedPath);
      final now = DateTime.now().toIso8601String();
      await LocalStore.instance.saveDocument({
        'id': id,
        'owner_id': 'local-demo',
        'name': result.name,
        'category': result.category,
        'local_path': storedPath,
        'storage_path': null,
        'created_at': now,
        'updated_at': now,
        'sync_state': 'pending',
        'is_shared': 0,
      });
      setState(() => _documents.insert(0, DocumentItem(result.name, result.category, 'À l’instant', Icons.description_rounded, FyTheme.blue, localPath: storedPath)));
      _message('Document enregistré sur cet appareil.');
      _syncPendingDocuments();
    } catch (_) {
      _message('Le document n’a pas pu être enregistré. Réessaie.');
    }
  }

  void _shareCode() => showModalBottomSheet<void>(context: context, backgroundColor: FyTheme.surface, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))), builder: (ctx) => Padding(padding: const EdgeInsets.fromLTRB(22, 26, 22, 35), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.qr_code_2_rounded, size: 42, color: FyTheme.blueLight), const SizedBox(height: 12), const Text('Ton code de partage', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)), const SizedBox(height: 8), const Text('Transmets ce code à la personne qui doit consulter tes documents.', textAlign: TextAlign.center, style: TextStyle(color: FyTheme.muted, fontSize: 12)), const SizedBox(height: 18), const SelectableText('FY-8K2M-94', style: TextStyle(fontFamily: 'monospace', color: FyTheme.blueLight, letterSpacing: 3, fontWeight: FontWeight.bold, fontSize: 22)), const SizedBox(height: 17), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () { Clipboard.setData(const ClipboardData(text: 'FY-8K2M-94')); Navigator.pop(ctx); _message('Code copié dans le presse-papiers'); }, icon: const Icon(Icons.copy_rounded), label: const Text('Copier le code')))])));

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));

  void _openCode() {
    showModalBottomSheet<void>(context: context, isScrollControlled: true, backgroundColor: FyTheme.surface, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))), builder: (ctx) => Padding(padding: EdgeInsets.fromLTRB(22, 25, 22, MediaQuery.of(ctx).viewInsets.bottom + 25), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Consulter des documents', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 19)), const SizedBox(height: 7), const Text('Saisis le code partagé par son propriétaire.', style: TextStyle(color: FyTheme.muted, fontSize: 12)), const SizedBox(height: 17), TextField(controller: _code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(prefixIcon: Icon(Icons.key_rounded, color: FyTheme.blueLight), hintText: 'Ex. FY-8K2M-94')), const SizedBox(height: 13), SizedBox(width: double.infinity, child: FilledButton(onPressed: () { Navigator.pop(ctx); if (_code.text.trim().isEmpty) { _message('Saisis un code pour continuer.'); return; } _message('Vérification du code : connexion Supabase à configurer.'); }, child: const Text('Afficher les documents')))])));
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _registering = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() { _email.dispose(); _password.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_hasSupabase) {
      setState(() => _error = 'Supabase n’est pas configuré. Utilise les valeurs de lancement décrites dans le README.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final auth = Supabase.instance.client.auth;
      if (_registering) {
        await auth.signUp(email: _email.text.trim(), password: _password.text);
        if (!mounted) return;
        setState(() => _error = 'Compte créé. Vérifie ton courriel pour confirmer ton adresse.');
      } else {
        await auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
        if (mounted) context.go('/');
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Connexion impossible. Vérifie ta connexion et réessaie.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 48, height: 48, decoration: BoxDecoration(color: FyTheme.blue.withValues(alpha: .16), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.shield_rounded, color: FyTheme.blueLight, size: 26)),
      const SizedBox(height: 26), Text(_registering ? 'Créer un compte' : 'Bon retour 👋', style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w700, letterSpacing: -.6)),
      const SizedBox(height: 7), Text(_registering ? 'Crée ton espace Fyface sécurisé.' : 'Connecte-toi à ton espace Fyface.', style: const TextStyle(color: FyTheme.muted, fontSize: 13)),
      const SizedBox(height: 25),
      Form(key: _formKey, child: Column(children: [
        TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(prefixIcon: Icon(Icons.email_outlined, color: FyTheme.faint), labelText: 'Adresse e-mail'), validator: (v) => v == null || !v.contains('@') ? 'Saisis une adresse e-mail valide.' : null),
        const SizedBox(height: 12), TextFormField(controller: _password, obscureText: true, decoration: const InputDecoration(prefixIcon: Icon(Icons.lock_outline, color: FyTheme.faint), labelText: 'Mot de passe'), validator: (v) => v == null || v.length < 8 ? '8 caractères minimum.' : null),
        if (_error != null) ...[const SizedBox(height: 12), Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: FyTheme.orange.withValues(alpha: .10), borderRadius: BorderRadius.circular(12)), child: Text(_error!, style: const TextStyle(color: FyTheme.orange, fontSize: 12)))],
        const SizedBox(height: 17), SizedBox(width: double.infinity, child: FilledButton(onPressed: _loading ? null : _submit, style: FilledButton.styleFrom(backgroundColor: FyTheme.blue, padding: const EdgeInsets.symmetric(vertical: 16)), child: _loading ? const SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_registering ? 'Créer mon compte' : 'Se connecter'))),
      ])),
      const SizedBox(height: 13), Center(child: TextButton(onPressed: () => setState(() { _registering = !_registering; _error = null; }), child: Text(_registering ? 'J’ai déjà un compte' : 'Créer un compte Fyface', style: const TextStyle(color: FyTheme.blueLight)))),
      if (!_hasSupabase) const Padding(padding: EdgeInsets.only(top: 20), child: Text('Aperçu de conception : connecte Supabase pour activer l’authentification et la synchronisation.', textAlign: TextAlign.center, style: TextStyle(color: FyTheme.faint, fontSize: 11))),
    ]))))),
  );
}

class AddDocumentResult {
  const AddDocumentResult(this.name, this.category, this.path);
  final String name;
  final String category;
  final String path;
}

class AddDocumentSheet extends StatefulWidget {
  const AddDocumentSheet({super.key});
  @override
  State<AddDocumentSheet> createState() => _AddDocumentSheetState();
}

class _AddDocumentSheetState extends State<AddDocumentSheet> {
  final _name = TextEditingController();
  String _category = 'Diplôme';
  String? _selectedPath;
  String? _selectedFileName;
  bool _picking = false;
  @override
  void dispose() { _name.dispose(); super.dispose(); }

  Future<void> _pickFile() async {
    setState(() => _picking = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      );
      final file = picked?.files.single;
      if (file != null && file.path != null) {
        setState(() {
          _selectedPath = file.path;
          _selectedFileName = file.name;
          if (_name.text.trim().isEmpty) _name.text = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
        });
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible d’ouvrir le sélecteur de fichiers.')));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(padding: EdgeInsets.fromLTRB(22, 25, 22, MediaQuery.of(context).viewInsets.bottom + 25), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Ajouter un document', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 19)), const SizedBox(height: 6), const Text('Importe une pièce depuis ton téléphone.', style: TextStyle(color: FyTheme.muted, fontSize: 12)), const SizedBox(height: 17), InkWell(onTap: _picking ? null : _pickFile, borderRadius: BorderRadius.circular(16), child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 20), decoration: BoxDecoration(color: FyTheme.elevated, border: Border.all(color: FyTheme.border), borderRadius: BorderRadius.circular(16)), child: Column(children: [Icon(_selectedPath == null ? Icons.cloud_upload_outlined : Icons.check_circle_outline_rounded, color: FyTheme.blueLight, size: 26), const SizedBox(height: 7), Text(_picking ? 'Ouverture…' : (_selectedFileName ?? 'Choisir un fichier'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)), const SizedBox(height: 3), const Text('PDF, JPG ou PNG · 10 Mo max.', style: TextStyle(color: FyTheme.faint, fontSize: 10))]))), const SizedBox(height: 13), TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nom du document', hintText: 'Ex. Diplôme de licence')), const SizedBox(height: 11), DropdownButtonFormField<String>(initialValue: _category, decoration: const InputDecoration(labelText: 'Catégorie'), items: ['Diplôme', 'Candidature', 'Attestation', 'Identité', 'Autre'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(), onChanged: (v) => setState(() => _category = v ?? _category)), const SizedBox(height: 16), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () { if (_selectedPath == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choisis un fichier à importer.'))); return; } if (_name.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Donne un nom au document.'))); return; } Navigator.pop(context, AddDocumentResult(_name.text.trim(), _category, _selectedPath!)); }, icon: const Icon(Icons.add_rounded), label: const Text('Ajouter à mes documents')))]));
}
