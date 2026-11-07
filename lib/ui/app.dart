import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/store.dart';
import 'progress.dart';
import 'theme.dart';
import 'today.dart';
import 'words.dart';

class EzberApp extends StatefulWidget {
  const EzberApp({super.key, required this.store});

  final Store store;

  @override
  State<EzberApp> createState() => _EzberAppState();
}

class _EzberAppState extends State<EzberApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.store.syncPhone());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The app can die any time after this, so the delayed save cannot wait.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(widget.store.flush());
      unawaited(widget.store.syncPhone());
    } else if (state == AppLifecycleState.resumed) {
      // The day may have rolled over while the app sat in the background.
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Ezber',
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        darkTheme: darkTheme,
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // The system bars keep their icons readable on the app's own background.
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: Theme.of(context).brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: child!,
        ),
        home: _Shell(store: widget.store),
      );
}

class _Shell extends StatefulWidget {
  const _Shell({required this.store});

  final Store store;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  var _tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: _tab,
            children: [
              TodayScreen(store: widget.store),
              WordsScreen(store: widget.store),
              ProgressScreen(store: widget.store),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.today_outlined),
              selectedIcon: Icon(Icons.today),
              label: 'Bugün',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'Kelimeler',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'İlerleme',
            ),
          ],
        ),
      );
}
