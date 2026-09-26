/// Shared client-side input limits and checks. These are UX-level guards —
/// give the user immediate, specific feedback — not the source of truth;
/// RLS/CHECK constraints on the server remain authoritative.
library;

/// Usernames: letters, digits, underscore — no spaces/emoji/control chars, so
/// what's stored is always a clean `@handle`.
const int kUsernameMinLength = 3;
const int kUsernameMaxLength = 24;
final RegExp kUsernamePattern = RegExp(r'^[a-zA-Z0-9_]+$');

/// The character class for the *input formatter* on username fields. It must be
/// unanchored: `FilteringTextInputFormatter.allow` keeps only the matched spans,
/// so feeding it the anchored [kUsernamePattern] would wipe the whole field the
/// moment a single disallowed character (space, emoji) is typed.
final RegExp kUsernameInputFormatter = RegExp(r'[A-Za-z0-9_]');

/// Trip / group / stop names: short, free-text labels shown in list rows.
const int kNameMaxLength = 60;

/// Free-text notes (stop notes, place notes).
const int kNotesMaxLength = 500;

/// Chat messages: matches the AI assistant's server-side cap so a long
/// message is rejected client-side instead of round-tripping.
const int kChatMessageMaxLength = 4000;

/// Display name / social handles on the profile screen.
const int kDisplayNameMaxLength = 60;
const int kSocialHandleMaxLength = 60;

/// Password bounds. Supabase/bcrypt silently truncates at 72 bytes, so cap the
/// accepted length client-side to keep "what you typed" == "what's checked".
const int kPasswordMinLength = 8;
const int kPasswordMaxLength = 72;

/// A trip expense in dollars. Zero/negative are rejected separately; this
/// just keeps a typo like an extra digit from creating an absurd expense.
const double kExpenseMaxAmount = 1000000;

/// A phone verification OTP code: exactly the length the Twilio Verify service
/// is configured for (its default is 6). Keep this in sync with the digit-box
/// count on the verification screen and the service's setting.
const int kOtpLength = 6;
final RegExp kOtpPattern = RegExp('^\\d{$kOtpLength}\$');

/// A phone number in E.164 international format, e.g. +15551234567.
final RegExp kPhonePattern = RegExp(r'^\+[1-9]\d{6,14}$');

/// A pragmatic email format check — not fully RFC 5322, just enough to catch
/// obvious typos before a round-trip to Supabase Auth.
final RegExp kEmailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// Validates a username, returning an error message or null when valid.
String? usernameError(String value) {
  final trimmed = value.trim();
  if (trimmed.length < kUsernameMinLength) {
    return 'Username must be at least $kUsernameMinLength characters';
  }
  if (trimmed.length > kUsernameMaxLength) {
    return 'Username must be $kUsernameMaxLength characters or fewer';
  }
  if (!kUsernamePattern.hasMatch(trimmed)) {
    return 'Username can only contain letters, numbers, and underscores';
  }
  return null;
}

/// Validates a required short name field (trip title, group name, stop name).
String? nameError(String value, {String label = 'This field'}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '$label is required';
  if (trimmed.length > kNameMaxLength) {
    return '$label must be $kNameMaxLength characters or fewer';
  }
  return null;
}

/// Validates an optional notes field.
String? notesError(String value) {
  if (value.length > kNotesMaxLength) {
    return 'Notes must be $kNotesMaxLength characters or fewer';
  }
  return null;
}

/// Validates a chat/assistant message body.
String? messageError(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null; // Callers separately gate empty sends.
  if (trimmed.length > kChatMessageMaxLength) {
    return 'Message must be $kChatMessageMaxLength characters or fewer';
  }
  return null;
}

/// Validates an email address format.
String? emailError(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'Enter your email address';
  if (!kEmailPattern.hasMatch(trimmed)) return 'Enter a valid email address';
  return null;
}

/// Validates a phone number in E.164 international format.
String? phoneError(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'Enter your phone number';
  if (!kPhonePattern.hasMatch(trimmed)) {
    return 'Enter your number in international format, e.g. +15551234567';
  }
  return null;
}

/// Validates a new password. [requireDigit] mirrors the sign-up screen's
/// strength rule; the change-password flow only enforces the length.
String? passwordError(String value, {bool requireDigit = true}) {
  if (value.length < kPasswordMinLength) {
    return 'Password must be at least $kPasswordMinLength characters';
  }
  if (value.length > kPasswordMaxLength) {
    return 'Password must be $kPasswordMaxLength characters or fewer';
  }
  if (requireDigit && !RegExp(r'\d').hasMatch(value)) {
    return 'Password must contain at least one number';
  }
  return null;
}

/// Validates a trip-expense amount already parsed to a double.
String? expenseAmountError(double? amount) {
  if (amount == null) return 'Enter a valid amount';
  if (amount <= 0) return 'Amount must be greater than zero';
  if (amount > kExpenseMaxAmount) return 'Amount is too large';
  return null;
}

/// Validates an OTP code before it's sent to the verification endpoint.
String? otpCodeError(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'Enter the verification code';
  if (!kOtpPattern.hasMatch(trimmed)) return 'Enter the numeric code you received';
  return null;
}
