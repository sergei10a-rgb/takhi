// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'identity_service.dart';

final keyStoreProvider = Provider<KeyStore>((_) => SecureKeyStore());
final identityServiceProvider = Provider<IdentityService>(
  (ref) => IdentityService(ref.read(keyStoreProvider)),
);
final currentIdentityProvider = FutureProvider<Identity?>(
  (ref) => ref.read(identityServiceProvider).load(),
);
