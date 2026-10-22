/// Pure-Dart conversion between Firestore REST values and Dart values.
///
/// Kept separate from [FirestoreRestService] so local SQLite/catalogue logic
/// can use the same wire-format rules without importing its HTTP/UI runtime.
class FirestoreValueCodec {
  static Map<String, dynamic> decodeFields(Object? raw) {
    if (raw is! Map) return const {};
    return raw.map((key, value) => MapEntry('$key', decodeValue(value)));
  }

  static dynamic decodeValue(dynamic value) {
    if (value is! Map) return value;
    if (value.containsKey('stringValue')) return value['stringValue'];
    if (value.containsKey('booleanValue')) return value['booleanValue'];
    if (value.containsKey('integerValue')) {
      return int.tryParse('${value['integerValue']}') ?? 0;
    }
    if (value.containsKey('doubleValue')) {
      return (value['doubleValue'] as num).toDouble();
    }
    if (value.containsKey('timestampValue')) {
      return DateTime.tryParse('${value['timestampValue']}');
    }
    if (value.containsKey('nullValue')) return null;
    if (value['arrayValue'] is Map) {
      final values = (value['arrayValue'] as Map)['values'];
      if (values is List) return values.map(decodeValue).toList();
      return <dynamic>[];
    }
    if (value['mapValue'] is Map) {
      return decodeFields((value['mapValue'] as Map)['fields']);
    }
    return value;
  }

  static Map<String, dynamic> encodeFields(Map<String, dynamic> fields) =>
      fields.map((key, value) => MapEntry(key, encodeValue(value)));

  static Map<String, dynamic> encodeValue(dynamic value) {
    if (value == null) return {'nullValue': null};
    if (value is bool) return {'booleanValue': value};
    if (value is int) return {'integerValue': '$value'};
    if (value is num) return {'doubleValue': value};
    if (value is DateTime) {
      return {'timestampValue': value.toUtc().toIso8601String()};
    }
    if (value is List) {
      return {
        'arrayValue': {'values': value.map(encodeValue).toList()},
      };
    }
    if (value is Map<String, dynamic>) {
      return {
        'mapValue': {'fields': encodeFields(value)},
      };
    }
    return {'stringValue': '$value'};
  }
}
