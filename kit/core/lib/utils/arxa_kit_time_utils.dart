/// Utility class providing time-related helper functions.
class ArxaKitTimeUtils {
  ArxaKitTimeUtils._();

  /// Returns a greeting based on the current time of day.
  ///
  /// Time ranges and corresponding greetings:
  /// - 4:00 AM to 7:59 AM: "Early Bird"
  /// - 8:00 AM to 11:59 AM: "Good Morning"
  /// - 12:00 PM to 4:59 PM: "Good Afternoon"
  /// - 5:00 PM to 8:59 PM: "Good Evening"
  /// - 9:00 PM to 3:59 AM: "Night Owl"
  ///
  /// @param [DateTime? dateTime] Optional date time for testing, defaults to current time
  /// @return [String] The appropriate greeting based on time of day
  static String getTimeBasedGreeting({DateTime? dateTime}) {
    final now = dateTime ?? DateTime.now();
    final hour = now.hour;

    if (hour >= 4 && hour < 8) {
      return 'Early Bird';
    } else if (hour >= 8 && hour < 12) {
      return 'Good Morning';
    } else if (hour >= 12 && hour < 17) {
      return 'Good Afternoon';
    } else if (hour >= 17 && hour < 21) {
      return 'Good Evening';
    } else {
      return 'Night Owl';
    }
  }

  /// Returns a personalized greeting based on time of day with the given name.
  ///
  /// @param [String name] The name to include in the greeting
  /// @param [DateTime? dateTime] Optional date time for testing, defaults to current time
  /// @return [String] Personalized greeting with name
  static String getPersonalizedGreeting(String name, {DateTime? dateTime}) {
    final greeting = getTimeBasedGreeting(dateTime: dateTime);
    return '$greeting, $name!';
  }
}
