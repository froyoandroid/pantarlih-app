import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mcp_toolkit/mcp_toolkit.dart';
import 'package:path_provider/path_provider.dart';

import 'core/format.dart';
import 'data/storage.dart';
import 'data/store.dart';
import 'data/wilayah.dart';
import 'ui/common.dart';
import 'ui/home.dart';
import 'ui/lokasi_screen.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    if (kDebugMode) {
      // MCP toolkit is agent tooling bound to the VM service. Debug-only:
      // it must not exist in release builds, which promise offline-only.
      MCPToolkitBinding.instance
        ..initialize()
        ..initializeFlutterToolkit();
    }
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      _catatCrash(details.exception, details.stack);
    };
    runApp(const PantarlihApp());
  }, (error, stack) {
    _catatCrash(error, stack);
    if (kDebugMode) {
      MCPToolkitBinding.instance.handleZoneError(error, stack);
    }
  });
}

/// Append the error to a `recovered/crash_<stamp>.log` file next to the app data.
/// Never rethrows: the crash writer must not become the crash source.
void _catatCrash(Object error, StackTrace? stack) {
  try {
    unawaited(() async {
      try {
        final dir = Directory(
            '${(await getApplicationDocumentsDirectory()).path}/recovered');
        await dir.create(recursive: true);
        await File('${dir.path}/crash_${fileStamp()}.log')
            .writeAsString('$error\n\n$stack', flush: true);
      } catch (_) {}
    }());
  } catch (_) {}
}

class PantarlihApp extends StatelessWidget {
  const PantarlihApp({super.key, this.introSudah});
  final Future<bool> Function()? introSudah;
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
      home: StartupScreen(introSudah: introSudah));
}

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key, this.introSudah});
  final Future<bool> Function()? introSudah;
  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  String? error;
  bool busy = false;
  bool cekSesi = true;
  bool langsungBuka = false;
  AppStore? store;

  @override
  void initState() {
    super.initState();
    _bukaSesi();
  }

  Future<void> _bukaSesi() async {
    final cek = widget.introSudah ?? introSudahDilewati;
    final pernah = await cek();
    if (!mounted) return;
    setState(() {
      cekSesi = false;
      langsungBuka = pernah;
    });
    if (pernah) await start();
  }

  Future<void> start({bool recover = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final resolved = await resolveDataRoot();
      if (store == null || store!.root.path != resolved.root.path) {
        // Retry after a failed attempt may resolve a different root (e.g. the
        // user just granted storage permission). A cached store pointing at
        // the old root would keep failing, so reopen on the new root.
        await store?.close();
        store = AppStore(resolved.root);
      }
      if (recover) {
        await store!.rebuild();
      } else {
        await store!.open();
      }
      final wilayah = await WilayahRepo.open();
      final session =
          Session(store!, usingPublic: resolved.usingPublic, wilayah: wilayah);
      await session.pastikanWorkspace();
      await session.selaraskanFolderDesa();
      store = session.store;
      await tandaiIntroSelesai(dataRoot: session.store.root);
      if (!mounted) return;
      final home = HomeScreen(session: session);
      if (!langsungBuka &&
          (session.kodeWilayah == null || session.kodeWilayah!.isEmpty)) {
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
  Widget build(BuildContext context) {
    final loading = cekSesi || (langsungBuka && busy && error == null);
    if (loading) {
      return const Scaffold(
          body: SafeArea(
              child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.fact_check_outlined, size: 68, color: forest),
        SizedBox(height: 24),
        Text('Pantarlih',
            style: TextStyle(
                fontSize: 36, fontWeight: FontWeight.w800, color: forest)),
        SizedBox(height: 28),
        CircularProgressIndicator(),
      ]))));
    }
    return Scaffold(
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
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 14),
                              const Text(
                                  'Data disimpan di folder Documents atau Dokumen. Nama foldernya Pantarlih diikuti nama desa. Berikan izin akses berkas agar jurnal, Excel, dan cadangan tetap bisa diambil lewat USB.',
                                  textAlign: TextAlign.center),
                              const Notice(
                                  'Folder ini berisi data pribadi warga. Lindungi perangkat dan cadangan. Tidak ada pengiriman otomatis ke internet.',
                                  icon: Icons.lock_outline),
                              if (error != null) Notice(error!, error: true),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                  onPressed: busy ? null : start,
                                  icon: const Icon(Icons.arrow_forward),
                                  label: Text(busy
                                      ? 'Membuka data…'
                                      : 'BUKA APLIKASI')),
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
}
