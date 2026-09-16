import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mcp_toolkit/mcp_toolkit.dart';

import 'data/storage.dart';
import 'data/store.dart';
import 'data/wilayah.dart';
import 'ui/common.dart';
import 'ui/home.dart';
import 'ui/lokasi_screen.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();

    MCPToolkitBinding.instance
      ..initialize()
      ..initializeFlutterToolkit();
    runApp(const PantarlihApp());
  },
      (error, stack) =>
          MCPToolkitBinding.instance.handleZoneError(error, stack));
}

class PantarlihApp extends StatelessWidget {
  const PantarlihApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
      title: 'Pantarlih Kalitorong',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: canvas,
        colorScheme: ColorScheme.fromSeed(
            seedColor: forest, primary: forest, surface: canvas),
        appBarTheme: const AppBarTheme(
            backgroundColor: canvas,
            foregroundColor: forest,
            centerTitle: false),
        cardTheme: CardThemeData(
            elevation: 0,
            color: Colors.white,
            margin: const EdgeInsets.symmetric(vertical: 5),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE2E5DD)))),
        inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
        filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(minimumSize: const Size(48, 52))),
        outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52))),
        textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48))),
      ),
      home: const StartupScreen());
}

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});
  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  String? error;
  bool busy = false;
  AppStore? store;
  Future<void> start({bool recover = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final resolved = await resolveDataRoot();
      store ??= AppStore(resolved.root);
      if (recover) {
        await store!.rebuild();
      } else {
        await store!.open();
      }
      final wilayah = await WilayahRepo.open();
      final session =
          Session(store!, usingPublic: resolved.usingPublic, wilayah: wilayah);
      await session.load();
      if (!mounted) return;
      final home = HomeScreen(session: session);
      if (session.kodeWilayah == null || session.kodeWilayah!.isEmpty) {
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => LokasiScreen(
                    session: session, allowSkip: true, nextPage: home)));
      } else {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => home));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
          child: Center(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Icon(Icons.fact_check_outlined,
                                size: 68, color: forest),
                            const SizedBox(height: 24),
                            const Text('Pantarlih',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w800,
                                    color: forest)),
                            const Text('PENDATAAN DPS OFFLINE',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    letterSpacing: 1.7, fontSize: 12)),
                            const SizedBox(height: 30),
                            const Text('Siap mendata, bahkan tanpa sinyal.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 14),
                            const Text(
                                'Data disimpan di Documents/PantarlihKalitorong. Berikan izin akses berkas agar jurnal, Excel, dan cadangan tetap bisa diambil lewat USB.',
                                textAlign: TextAlign.center),
                            const Notice(
                                'Folder ini berisi data pribadi warga. Lindungi perangkat dan cadangan. Tidak ada pengiriman otomatis ke internet.',
                                icon: Icons.lock_outline),
                            if (error != null) Notice(error!, error: true),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                                onPressed: busy ? null : start,
                                icon: const Icon(Icons.arrow_forward),
                                label: Text(
                                    busy ? 'Membuka data…' : 'BUKA APLIKASI')),
                            if (error != null && store != null)
                              TextButton(
                                  onPressed: busy
                                      ? null
                                      : () async {
                                          if (await confirm(
                                              context,
                                              'Pulihkan database?',
                                              'Database lama dipertahankan di folder recovered. Jurnal akan diputar ulang.',
                                              action: 'PULIHKAN')) {
                                            await start(recover: true);
                                          }
                                        },
                                  child:
                                      const Text('Bangun ulang dari jurnal')),
                          ]))))));
}
