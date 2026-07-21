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

  /// Reconstructs a [NostrEvent] from the NIP-01 JSON shape produced by
  /// [toJson] (or received from a relay). Used when an event is embedded
  /// inside another event's content -- e.g. NIP-59 seals/gift wraps -- and
  /// needs to be parsed back out after NIP-44 decryption.
  ///
  /// [json] is untrusted input in that use case: it comes from decrypting
  /// data supplied by whoever encrypted it, not from a value this process
  /// produced itself. Every field is therefore type-checked explicitly and
  /// a [FormatException] -- never an uncaught [TypeError] -- is thrown on
  /// any mismatch, so callers can rely on `on Exception` to filter out
  /// malformed events without a crafted payload crashing the isolate.
  factory NostrEvent.fromJson(Map<String, dynamic> json) => NostrEvent(
        id: _optionalString(json, 'id'),
        pubkey: _requiredString(json, 'pubkey'),
        createdAt: _requiredInt(json, 'created_at'),
        kind: _requiredInt(json, 'kind'),
        tags: _requiredTags(json, 'tags'),
        content: _requiredString(json, 'content'),
        sig: _optionalString(json, 'sig'),
      );
}

String _requiredString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is String) return value;
  throw FormatException("NostrEvent.fromJson: '$field' must be a String, got "
      '${value.runtimeType}');
}

String? _optionalString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException(
      "NostrEvent.fromJson: '$field' must be a String or null, got "
      '${value.runtimeType}');
}

int _requiredInt(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is int) return value;
  throw FormatException("NostrEvent.fromJson: '$field' must be an int, got "
      '${value.runtimeType}');
}

List<List<String>> _requiredTags(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! List) {
    throw FormatException("NostrEvent.fromJson: '$field' must be a List, got "
        '${value.runtimeType}');
  }
  return value.map((tag) {
    if (tag is! List) {
      throw FormatException(
          "NostrEvent.fromJson: '$field' entries must be a List, got "
          '${tag.runtimeType}');
    }
    return tag.map((x) {
      if (x is! String) {
        throw FormatException(
            "NostrEvent.fromJson: '$field' entries must contain only "
            'Strings, got ${x.runtimeType}');
      }
      return x;
    }).toList();
  }).toList();
}

String computeEventId(NostrEvent e) {
  // NIP-01: sha256 of the UTF-8 of the compact JSON array
  // [0, pubkey, created_at, kind, tags, content] with no extra whitespace.
  final serialized =
      jsonEncode([0, e.pubkey, e.createdAt, e.kind, e.tags, e.content]);
  final digest = sha256.convert(utf8.encode(serialized));
  return digest.toString();
}
