import 'dart:async';

import 'package:flutter/material.dart';

import '../data/local/app_store.dart';
import '../data/repositories/drama_repository.dart';
import '../domain/models/drama.dart';
import '../domain/models/preferences.dart';
import '../domain/models/remote_key_map.dart';
import '../domain/models/watch_record.dart';

final class AppController extends ChangeNotifier {
  AppController(this.store, this.repository);
  final AppStore store;
  final DramaRepository repository;

  Preferences preferences = const Preferences();
  /// 当前生效的遥控器按键映射（自定义优先，否则默认）。
  RemoteKeyMap get remoteKeyMap =>
      preferences.remoteKeyMap ?? RemoteKeyMap.defaults();
  List<Drama> favorites = [];
  List<WatchRecord> history = [];
  List<String> searches = [];
  String? persistenceError;
  bool _disposed = false;
  Future<void> _writes = Future.value();

  Future<void> initialize() async {
    preferences = await store.readPreferences();
    favorites = await store.readFavorites();
    history = await store.readHistory();
    searches = await store.readSearches();
    await repository.loadCache();
  }

  bool isFavorite(String id) => favorites.any((drama) => drama.id == id);
  WatchRecord? historyOf(String id) {
    for (final record in history) {
      if (record.drama.id == id) return record;
    }
    return null;
  }

  void setPreferences(Preferences value) {
    preferences = value;
    _save(() => store.savePreferences(value));
    notifyListeners();
  }

  bool toggleFavorite(Drama drama) {
    final enabled = !isFavorite(drama.id);
    favorites = [
      if (enabled) drama,
      ...favorites.where((item) => item.id != drama.id),
    ];
    _save(() => store.setFavorite(drama, enabled));
    notifyListeners();
    return enabled;
  }

  void removeFavorites(Iterable<String> ids) {
    final remove = ids.toSet();
    final dramas = favorites
        .where((drama) => remove.contains(drama.id))
        .toList();
    favorites = favorites.where((drama) => !remove.contains(drama.id)).toList();
    for (final drama in dramas) {
      _save(() => store.setFavorite(drama, false));
    }
    notifyListeners();
  }

  void record(WatchRecord record) {
    if (!preferences.rememberProgress) return;
    history = [
      record,
      ...history.where((item) => item.drama.id != record.drama.id),
    ].take(200).toList();
    _save(() => store.saveRecord(record));
    notifyListeners();
  }

  void removeHistory(Iterable<String> ids) {
    final remove = ids.toSet();
    history = history
        .where((record) => !remove.contains(record.drama.id))
        .toList();
    _save(() => store.deleteHistory(remove));
    notifyListeners();
  }

  void addSearch(String text) {
    final query = text.trim();
    if (query.isEmpty) return;
    searches = [
      query,
      ...searches.where((item) => item != query),
    ].take(10).toList();
    final snapshot = List<String>.of(searches);
    _save(() => store.saveSearches(snapshot));
    notifyListeners();
  }

  void clearSearches() {
    searches = [];
    _save(() => store.saveSearches([]));
    notifyListeners();
  }

  void _save(Future<void> Function() operation) {
    _writes = _writes.then((_) => operation()).catchError((Object error) {
      persistenceError = '本地存储空间不足或暂不可用，部分更改未能保存';
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> flush() => _writes;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppController watch(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
