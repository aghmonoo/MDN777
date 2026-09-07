/// The staff document slots, shared by the upload UI and the PDF export.
class DocumentSlot {
  const DocumentSlot(this.fieldPath, this.label);

  /// Key under `users/{uid}.documents`.
  final String fieldPath;

  /// Human label, including the Front/Back suffix where relevant.
  final String label;
}

class DocumentTypes {
  DocumentTypes._();

  /// key -> label, and how many sides the document has.
  static const List<Map<String, dynamic>> types = [
    {'key': 'passportCi', 'label': 'Passport / CI Photo', 'pages': 1},
    {'key': 'visa', 'label': 'Visa Photo', 'pages': 1},
    {'key': 'workPermitPaper', 'label': 'Work Permit Paper', 'pages': 1},
    {'key': 'workPermitCard', 'label': 'Work Permit Card', 'pages': 2},
    {'key': 'days90Paper', 'label': '90 Days Paper', 'pages': 1},
    {'key': 'tm30', 'label': 'TM30', 'pages': 1},
    {'key': 'pinkCard', 'label': 'Pink Card', 'pages': 2},
  ];

  /// Every individual image slot, in the order they appear in the app.
  static List<DocumentSlot> get slots {
    final out = <DocumentSlot>[];
    for (final t in types) {
      final key = t['key'] as String;
      final label = t['label'] as String;
      if ((t['pages'] as int) == 1) {
        out.add(DocumentSlot(key, label));
      } else {
        out.add(DocumentSlot('${key}Front', '$label (Front)'));
        out.add(DocumentSlot('${key}Back', '$label (Back)'));
      }
    }
    return out;
  }

  /// Slots the user has actually uploaded something for.
  static List<DocumentSlot> filled(Map<String, dynamic>? documents) {
    final docs = documents ?? const {};
    return slots.where((s) {
      final url = docs[s.fieldPath];
      return url is String && url.isNotEmpty;
    }).toList();
  }
}
