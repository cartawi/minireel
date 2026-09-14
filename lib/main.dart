import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'app/app.dart';
import 'app/app_controller.dart';
import 'app/platform.dart';
import 'app/theme.dart';
import 'core/config/source_config.dart';
import 'core/network/app_http_client.dart';
import 'data/local/sqlite_app_store.dart';
import 'data/repositories/drama_repository.dart';
import 'data/sources/hongguo/hongguo_adapter.dart';
import 'data/sources/source_adapter.dart';
import 'desktop/desktop_window.dart';
import 'desktop/window_chrome.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'MiniReel',
    ], await rootBundle.loadString('License'));
  });
  initDebugTvFromEnv();
  if (Platform.isWindows) await DesktopWindow.instance.initialize();
  MediaKit.ensureInitialized();
  await detectAndroidTv();
  if (Platform.isAndroid && !isAndroidTV) {
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  }
  runApp(const MiniReelBootstrap());
}

class MiniReelBootstrap extends StatefulWidget {
  const MiniReelBootstrap({super.key});
  @override
  State<MiniReelBootstrap> createState() => _MiniReelBootstrapState();
}

class _MiniReelBootstrapState extends State<MiniReelBootstrap> {
  late Future<AppController> _startup;
  AppController? _app;
  AppHttpClient? _http;

  @override
  void initState() {
    super.initState();
    _startup = _initialize();
  }

  Future<AppController> _initialize() async {
    final raw =
        jsonDecode(await rootBundle.loadString('assets/config/sources.json'))
            as Map<String, dynamic>;
    final config = SourceConfig.fromJson(
      raw['sources']['hongguo'] as Map<String, dynamic>,
    );
    final http = _http = AppHttpClient(config);
    final store = await SqliteAppStore.open();
    try {
      final repository = DramaRepository(
        SourceRegistry([
          if (config.enabled) HongguoAdapter(config, http, store: store),
        ]),
        store,
      );
      final app = AppController(store, repository);
      await app.initialize();
      _app = app;
      if (Platform.isWindows) {
        DesktopWindow.instance.onAppClose = () async {
          await app.flush();
          app.repository.dispose();
          http.close();
          await store.close();
        };
      }
      return app;
    } on Exception {
      await store.close();
      http.close();
      rethrow;
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) DesktopWindow.instance.onAppClose = null;
    final app = _app;
    if (app != null) {
      app.repository.dispose();
      unawaited(app.flush().then((_) => app.store.close()));
      app.dispose();
    }
    _http?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppController>(
    future: _startup,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return MiniReelApp(controller: snapshot.requireData);
      }
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ReelTheme.make(Brightness.dark),
        builder: Platform.isWindows
            ? (context, child) => Overlay.wrap(
                child: Column(
                  children: [
                    const DesktopTitleBar(),
                    Expanded(child: child!),
                  ],
                ),
              )
            : null,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/logo.png', width: 90, height: 120),
                  const SizedBox(height: 22),
                  const Text(
                    'MiniReel',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    snapshot.hasError ? '本地数据暂时无法读取，请检查可用存储空间' : '好故事，随时开场',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 26),
                  if (snapshot.hasError)
                    FilledButton(
                      onPressed: () => setState(() => _startup = _initialize()),
                      child: const Text('重试'),
                    )
                  else
                    const SizedBox(
                      width: 21,
                      height: 21,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
