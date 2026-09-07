/// Column layout for the payslip import/export sheets.
///
/// The importer matches on the header text rather than a fixed position, so
/// columns can be reordered or added without breaking older sheets. The
/// legacy positions are kept as a fallback for sheets with no header row.
class PayslipFields {
  PayslipFields._();

  /// Paid per day of training, for staff who have no basic salary yet.
  static const double trainingDayRate = 500;

  /// Days used to prorate a public holiday from the basic salary.
  static const double monthDays = 30;

  /// Header, in the order the template is written.
  static const List<String> headers = [
    'employeeId',
    'username',
    'displayName',
    'department',
    'bankName',
    'accountNumber',
    'accountHolderName',
    'month',
    'basicSalary',
    'allowance',
    'kpiBonus',
    'otHours',
    'otAmount',
    'publicHolidayDays',
    'trainingDays',
    'socialSecurity',
    'leaveDeduction',
    'lateMinutes',
    'lateAmount',
    'customReason',
    'customAmount',
  ];

  /// Alternative spellings accepted in an uploaded sheet.
  static const Map<String, List<String>> aliases = {
    'employeeId': ['employeeid', 'staffid', 'id'],
    'username': ['username', 'user'],
    'displayName': ['displayname', 'name', 'fullname'],
    'department': ['department', 'dept'],
    'bankName': ['bankname', 'bank'],
    'accountNumber': ['accountnumber', 'accountno', 'accno'],
    'accountHolderName': ['accountholdername', 'accountholder'],
    'month': ['month', 'period'],
    'basicSalary': ['basicsalary', 'basic', 'salary'],
    'allowance': ['allowance', 'allowances'],
    'kpiBonus': ['kpibonus', 'kpi', 'bonus'],
    'otHours': ['othours', 'ot', 'overtimehours'],
    'otAmount': ['otamount', 'overtimeamount', 'overtime'],
    'publicHolidayDays': [
      'publicholidaydays',
      'publicholiday',
      'publicholidays',
      'holidaydays',
      'holiday',
      'ph',
    ],
    'trainingDays': [
      'trainingdays',
      'training',
      'trainingday',
    ],
    'socialSecurity': ['socialsecurity', 'ssb', 'social'],
    'leaveDeduction': ['leavededuction', 'leave'],
    'lateMinutes': ['lateminutes', 'late', 'latemin', 'latemins'],
    'lateAmount': ['lateamount', 'latededuction'],
    'customReason': ['customreason', 'custom', 'reason', 'remark', 'note'],
    'customAmount': ['customamount', 'customvalue', 'adjustment', 'amount'],
  };

  /// Positions used by sheets exported before the header lookup existed.
  static const Map<String, int> legacyIndex = {
    'employeeId': 0,
    'username': 1,
    'displayName': 2,
    'department': 3,
    'bankName': 4,
    'accountNumber': 5,
    'accountHolderName': 6,
    'month': 7,
    'basicSalary': 8,
    'allowance': 9,
    'kpiBonus': 10,
    'otHours': 11,
    'otAmount': 12,
    'socialSecurity': 13,
    'leaveDeduction': 14,
    'lateMinutes': 15,
    'lateAmount': 16,
  };

  /// Reduces a header cell to a comparable key.
  static String normalise(String raw) =>
      raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Maps each field to the column it occupies in [headerRow].
  static Map<String, int> resolve(List<String> headerRow) {
    final found = <String, int>{};

    for (var i = 0; i < headerRow.length; i++) {
      final key = normalise(headerRow[i]);
      if (key.isEmpty) continue;
      aliases.forEach((field, names) {
        if (found.containsKey(field)) return;
        if (names.contains(key)) found[field] = i;
      });
    }

    // A sheet with no recognisable header falls back to the old layout.
    // Once headers are recognised they are trusted on their own: guessing a
    // position for a missing column would read someone else's numbers.
    if (found.length < 3) return Map<String, int>.from(legacyIndex);
    return found;
  }
}
