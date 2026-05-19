import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../main.dart';

class EncryptionService {
  static const _storage = FlutterSecureStorage();
  static const _privateKeyStorageKey = 'liuchat_private_key';

  // ── Key Generation ─────────────────────────────────────────

  /// Call once after user logs in for the first time.
  /// Generates X25519 key pair, saves private key on device,
  /// saves public key to Supabase profiles table.
  static Future<void> initializeKeys() async {
    try {
      final existingKey = await _storage.read(key: _privateKeyStorageKey);

      if (existingKey != null) {
        // Private key exists on device — make sure public key is in Supabase
        final profile = await supabase
            .from('profiles')
            .select('public_key')
            .eq('id', supabase.auth.currentUser!.id)
            .single();

        if (profile['public_key'] != null) return; // All good

        // Public key missing from Supabase — re-upload it
        final privateKeyBytes = base64Decode(existingKey);
        final x25519 = X25519();
        final keyPair = await x25519.newKeyPairFromSeed(privateKeyBytes);
        final publicKey = await keyPair.extractPublicKey();

        await supabase.from('profiles').update({
          'public_key': base64Encode(publicKey.bytes),
        }).eq('id', supabase.auth.currentUser!.id);

        return;
      }

      // No private key on device — generate fresh pair
      final algorithm = X25519();
      final keyPair = await algorithm.newKeyPair();
      final publicKey = await keyPair.extractPublicKey();
      final privateKeyBytes = await keyPair.extractPrivateKeyBytes();

      await _storage.write(
        key: _privateKeyStorageKey,
        value: base64Encode(privateKeyBytes),
      );

      await supabase.from('profiles').update({
        'public_key': base64Encode(publicKey.bytes),
      }).eq('id', supabase.auth.currentUser!.id);

    } catch (e) {
      throw Exception('Failed to initialize encryption keys: $e');
    }
  }

  // ── Encrypt ────────────────────────────────────────────────

  /// Encrypts a message using recipient's public key.
  /// Returns base64 encoded string containing nonce + ciphertext + mac.
  static Future<String> encryptMessage(
    String message,
    String recipientPublicKeyBase64,
  ) async {
    try {
      // Load our private key from secure storage
      final privateKeyBase64 = await _storage.read(key: _privateKeyStorageKey);
      if (privateKeyBase64 == null) {
        throw Exception('Private key not found. Please log out and log in again.');
      }

      final privateKeyBytes = base64Decode(privateKeyBase64);
      final recipientPublicKeyBytes = base64Decode(recipientPublicKeyBase64);

      // Decode recipient public key
      final recipientPublicKey = SimplePublicKey(
        recipientPublicKeyBytes,
        type: KeyPairType.x25519,
      );

      // X25519 key exchange — derive shared secret
      final x25519 = X25519();
      final ourKeyPair = await x25519.newKeyPairFromSeed(privateKeyBytes);
      final sharedSecret = await x25519.sharedSecretKey(
        keyPair: ourKeyPair,
        remotePublicKey: recipientPublicKey,
      );

      // Encrypt with AES-256-GCM using shared secret
      final aesGcm = AesGcm.with256bits();
      final secretKey = await aesGcm.newSecretKeyFromBytes(
        await sharedSecret.extractBytes(),
      );

      final secretBox = await aesGcm.encryptString(
        message,
        secretKey: secretKey,
      );

      // Bundle: nonce (12 bytes) + ciphertext + mac (16 bytes)
      final combined = Uint8List.fromList([
        ...secretBox.nonce,
        ...secretBox.cipherText,
        ...secretBox.mac.bytes,
      ]);

      return base64Encode(combined);
    } catch (e) {
      throw Exception('Encryption failed: $e');
    }
  }

  // ── Decrypt ────────────────────────────────────────────────

  /// Decrypts a message using sender's public key and our private key.
  static Future<String> decryptMessage(
    String encryptedBase64,
    String senderPublicKeyBase64,
  ) async {
    try {
      final combined = base64Decode(encryptedBase64);

      // Split: nonce (12) + ciphertext + mac (16)
      if (combined.length < 28) {
        throw Exception('Invalid encrypted message format');
      }

      final nonce = combined.sublist(0, 12);
      final mac = combined.sublist(combined.length - 16);
      final cipherText = combined.sublist(12, combined.length - 16);

      // Load our private key
      final privateKeyBase64 = await _storage.read(key: _privateKeyStorageKey);
      if (privateKeyBase64 == null) {
        throw Exception('Private key not found');
      }

      final privateKeyBytes = base64Decode(privateKeyBase64);
      final senderPublicKeyBytes = base64Decode(senderPublicKeyBase64);

      // Decode sender public key
      final senderPublicKey = SimplePublicKey(
        senderPublicKeyBytes,
        type: KeyPairType.x25519,
      );

      // X25519 key exchange — derive shared secret
      final x25519 = X25519();
      final ourKeyPair = await x25519.newKeyPairFromSeed(privateKeyBytes);
      final sharedSecret = await x25519.sharedSecretKey(
        keyPair: ourKeyPair,
        remotePublicKey: senderPublicKey,
      );

      // Decrypt with AES-256-GCM
      final aesGcm = AesGcm.with256bits();
      final secretKey = await aesGcm.newSecretKeyFromBytes(
        await sharedSecret.extractBytes(),
      );

      final secretBox = SecretBox(
        cipherText,
        nonce: nonce,
        mac: Mac(mac),
      );

      return await aesGcm.decryptString(secretBox, secretKey: secretKey);
    } catch (e) {
      throw Exception('Decryption failed: $e');
    }
  }

  // ── Helpers ────────────────────────────────────────────────

  /// Fetch a user's public key from Supabase
  static Future<String?> getPublicKey(String userId) async {
    try {
      final profile = await supabase
          .from('profiles')
          .select('public_key')
          .eq('id', userId)
          .single();
      return profile['public_key'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Clear keys from device (call on logout)
  static Future<void> clearKeys() async {
    await _storage.delete(key: _privateKeyStorageKey);
  }
}