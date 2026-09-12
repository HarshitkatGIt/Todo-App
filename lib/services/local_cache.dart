import 'package:shared_preferences/shared_preferences.dart';

class LocalCache {
  static const _key = 'cached_state_json';

  Future<void> save(String rawJson) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, rawJson);
  }

  Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }
}
