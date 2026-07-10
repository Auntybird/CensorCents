import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps device-level biometrics (Face ID / fingerprint) for the optional
/// app-lock feature. Everything here is on-device — no server involved, no
/// account data leaves the phone. The "is app lock enabled" preference is
/// stored locally via SharedPreferences rather than in Supabase, since it's
/// a per-device setting, not account data.
class BiometricService {
  BiometricService._internal();
  static final BiometricService instance = BiometricService._internal();

  static const _prefsKey = 'app_lock_enabled';

  final LocalAuthentication _auth = LocalAuthentication();

  /// True if EITHER biometrics (fingerprint/Face ID) OR some other
  /// device-level auth (PIN/pattern/passcode) is available. This must be OR,
  /// not AND — a device with a PIN set but no fingerprint enrolled should
  /// still count as "supported", since `authenticate()` falls back to the
  /// device credential in that case. Matches the pattern in local_auth's own
  /// docs: `canCheckBiometrics || await isDeviceSupported()`.
  Future<bool> get isDeviceSupported async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (_) {
      return false;
    }
  }

  Future<bool> get isEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, enabled);
  }

  String? lastError;

  /// Prompts Face ID / fingerprint / device PIN. Returns false (rather than
  /// throwing) on any failure or cancellation so callers can just show a
  /// "try again" state — check [lastError] afterwards for why it failed.
  ///
  /// Deliberately omits the `options:` argument (AuthenticationOptions) —
  /// it's optional with sensible defaults, and skipping it avoids depending
  /// on that type resolving correctly across local_auth versions.
  Future<bool> authenticate() async {
    lastError = null;
    try {
      final result = await _auth.authenticate(localizedReason: 'Unlock CensorCents');
      if (!result) lastError = 'Authentication was cancelled or did not match.';
      return result;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }
}