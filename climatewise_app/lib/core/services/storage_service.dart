import 'package:shared_preferences/shared_preferences.dart';

/// StorageService
///
/// A helper class to persist and manage unlocked planets
/// using [SharedPreferences]. Data is stored as a list of
/// planet IDs (stringified).
class StorageService {
  static const String _unlockedKey = 'unlocked_planets';

  /// Unlocks a planet by adding its [planetId] to the
  /// unlocked planets list if not already present.
  static Future<void> unlockPlanet(int planetId) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> unlocked = prefs.getStringList(_unlockedKey) ?? [];
    if (!unlocked.contains(planetId.toString())) {
      unlocked.add(planetId.toString());
      await prefs.setStringList(_unlockedKey, unlocked);
    }
  }

  /// Checks if a given [planetId] is already unlocked.
  static Future<bool> isPlanetUnlocked(int planetId) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> unlocked = prefs.getStringList(_unlockedKey) ?? [];
    return unlocked.contains(planetId.toString());
  }

  /// Resets all unlocked planets.
  /// Useful for debugging or starting fresh.
  static Future<void> resetAllUnlockedPlanets() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_unlockedKey);
  }

  /// Retrieves all unlocked planet IDs as a list of [int].
  /// Returns an empty list if none are unlocked.
  static Future<List<int>> getAllUnlockedPlanets() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> unlocked = prefs.getStringList(_unlockedKey) ?? [];
    return unlocked.map((id) => int.tryParse(id) ?? 0).toList();
  }
}
