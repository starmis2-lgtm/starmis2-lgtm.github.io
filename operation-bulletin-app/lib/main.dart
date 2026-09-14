import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'api.dart';
import 'screens/entry.dart';
import 'screens/home.dart';
import 'screens/login.dart';
import 'screens/my_pending.dart';
import 'screens/production.dart';
import 'screens/settings.dart';
import 'state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  final state = AppState(Api());
  runApp(ChangeNotifierProvider.value(value: state, child: const OpBulletinApp()));
  state.init();
}

const kSeed = Color(0xFF0F766E);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: kSeed, brightness: brightness);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness, fontFamily: 'Inter');
  return base.copyWith(
    visualDensity: VisualDensity.compact,
    textTheme: base.textTheme.apply(fontFamily: 'Inter'),
    scaffoldBackgroundColor: brightness == Brightness.light ? const Color(0xFFF4F6F8) : scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: brightness == Brightness.light ? const Color(0xFFF4F6F8) : scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 52,
      titleTextStyle: TextStyle(fontFamily: 'Inter', fontSize: 19, fontWeight: FontWeight.w700, color: scheme.onSurface, letterSpacing: -0.2),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6))),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: scheme.primary, width: 1.6)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      isDense: true,
      labelStyle: const TextStyle(fontSize: 13),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 60,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(fontSize: 11, fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500)),
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
    ),
    chipTheme: base.chipTheme.copyWith(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)), labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), labelPadding: const EdgeInsets.symmetric(horizontal: 2)),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), textStyle: const TextStyle(fontWeight: FontWeight.w700))),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5), space: 1),
  );
}

class OpBulletinApp extends StatelessWidget {
  const OpBulletinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Operation Bulletin',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const RootGate(),
    );
  }
}

class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    if (!st.booted) return const SplashScreen();
    if (st.needLogin || st.data == null) return const LoginScreen();
    return const Shell();
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSeed,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84, height: 84,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(24)),
            child: const Icon(Icons.insights_rounded, color: Colors.white, size: 44),
          ),
          const SizedBox(height: 18),
          const Text('Operation Bulletin', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 28),
          const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)),
        ]),
      ),
    );
  }
}

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon, this.page);
  final String label;
  final IconData icon, selectedIcon;
  final Widget page;
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  List<_Dest> _dests(AppState st) => [
        if (st.showHome) const _Dest('Home', Icons.home_outlined, Icons.home_rounded, HomeScreen()),
        if (st.showProduction) const _Dest('Production', Icons.factory_outlined, Icons.factory_rounded, ProductionScreen()),
        if (st.showEntry) const _Dest('Entry', Icons.edit_note_outlined, Icons.edit_note_rounded, EntryScreen()),
        const _Dest('My Pending', Icons.pending_actions_outlined, Icons.pending_actions_rounded, MyPendingScreen()),
        if (st.showSettings) const _Dest('Settings', Icons.settings_outlined, Icons.settings_rounded, SettingsScreen()),
      ];

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final dests = _dests(st);
    // Honor tab switch requests from other screens.
    final req = st.requestedTab;
    if (req != null) {
      st.requestedTab = null;
      final i = dests.indexWhere((d) => d.label == ['Home', 'Production', 'Entry', 'My Pending', 'Settings'][req]);
      if (i >= 0) WidgetsBinding.instance.addPostFrameCallback((_) => setState(() => _index = i));
    }
    if (_index >= dests.length) _index = 0;
    return Scaffold(
      body: IndexedStack(index: _index, children: dests.map((d) => d.page).toList()),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: dests.map((d) => NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label)).toList(),
      ),
    );
  }
}

/// Tab indexes used with AppState.requestedTab.
class Tabs {
  static const home = 0, production = 1, entry = 2, myPending = 3, settings = 4;
}
