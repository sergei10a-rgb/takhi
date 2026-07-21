// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'package:crypto/crypto.dart';

class NostrEvent {
  final String? id;
  final String pubkey;
  final int createdAt;
  final int kind;
  final List<List<String>> tags;
  final String content;
  final String? sig;

  /// [tags] is defensively copied into an unmodifiable list so a
  /// [NostrEvent] cannot be mutated after construction (e.g. via a
  /// reference to the list a caller passed in).
  NostrEvent({
    this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required List<List<String>> tags,
    required this.content,
    this.sig,
  }) : tags = List.unmodifiable(tags);

  NostrEvent copyWith({String? id, String? sig}) => NostrEvent(
        id: id ?? this.id,
        pubkey: pubkey,
        createdAt: createdAt,
        kind: kind,
        tags: tags,
        content: content,
        sig: sig ?? this.sig,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'pubkey': pubkey,
        'created_at': createdAt,
        'kind': kind,
        'tags': tags,
        'content': content,
        'sig': sig,
      };
}

String computeEventId(NostrEvent e) {
  // NIP-01: sha256 of the UTF-8 of the compact JSON array
  // [0, pubkey, created_at, kind, tags, content] with no extra whitespace.
  final serialized =
      jsonEncode([0, e.pubkey, e.createdAt, e.kind, e.tags, e.content]);
  final digest = sha256.convert(utf8.encode(serialized));
  return digest.toString();
}
