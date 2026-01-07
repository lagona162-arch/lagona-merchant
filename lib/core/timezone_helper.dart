/// Helper class for timezone operations
/// Uses PHT (Philippine Time, UTC+8) as the standard timezone
class TimezoneHelper {
  /// PHT is UTC+8
  static const int phtOffsetHours = 8;

  /// Get current time in PHT (Philippine Time, UTC+8)
  static DateTime nowPHT() {
    final utcNow = DateTime.now().toUtc();
    return utcNow.add(Duration(hours: phtOffsetHours));
  }

  /// Convert a DateTime to PHT
  static DateTime toPHT(DateTime dateTime) {
    final utc = dateTime.toUtc();
    return utc.add(Duration(hours: phtOffsetHours));
  }

  /// Convert PHT DateTime to UTC for database storage
  static DateTime phtToUTC(DateTime phtDateTime) {
    return phtDateTime.subtract(Duration(hours: phtOffsetHours)).toUtc();
  }

  /// Get current time in UTC (for database storage)
  /// Database stores in UTC, but we calculate expiration times in PHT
  static DateTime nowUTC() {
    return DateTime.now().toUtc();
  }
}

