import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class GuestUserManager {
  static const String _guestUserIdKey = "guest_user_id";

  /// Returns existing guest user id or creates a new one if not found
  static Future<String> getOrCreateUserId() async {
    final prefs = await SharedPreferences.getInstance();
    String? userId = prefs.getString(_guestUserIdKey);

    if (userId == null) {
      userId = const Uuid().v4(); // generate new uuid
      await prefs.setString(_guestUserIdKey, userId);
    }

    return userId;
  }

  /// Just get user id (null if not exists)
  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_guestUserIdKey);
  }

  /// Force reset guest user id (rarely used)
  static Future<String> resetUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final newId = const Uuid().v4();
    await prefs.setString(_guestUserIdKey, newId);
    return newId;
  }
}
