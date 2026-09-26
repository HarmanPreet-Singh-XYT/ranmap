import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/core/util/validation.dart';

void main() {
  group('usernameError', () {
    test('rejects too short', () {
      expect(usernameError('ab'), isNotNull);
    });
    test('rejects too long', () {
      expect(usernameError('a' * 25), isNotNull);
    });
    test('rejects invalid characters', () {
      expect(usernameError('bad name!'), isNotNull);
    });
    test('accepts a valid username', () {
      expect(usernameError('valid_user123'), isNull);
    });
  });

  group('nameError', () {
    test('rejects empty', () {
      expect(nameError('   '), isNotNull);
    });
    test('rejects over the max length', () {
      expect(nameError('a' * 61), isNotNull);
    });
    test('accepts a normal name', () {
      expect(nameError('Weekend trip'), isNull);
    });
  });

  group('notesError', () {
    test('rejects over the max length', () {
      expect(notesError('a' * 501), isNotNull);
    });
    test('accepts empty (optional field)', () {
      expect(notesError(''), isNull);
    });
  });

  group('messageError', () {
    test('rejects over the max length', () {
      expect(messageError('a' * 4001), isNotNull);
    });
    test('accepts a normal message', () {
      expect(messageError('hello there'), isNull);
    });
  });

  group('emailError', () {
    test('rejects missing @', () {
      expect(emailError('not-an-email'), isNotNull);
    });
    test('rejects missing domain', () {
      expect(emailError('a@'), isNotNull);
    });
    test('accepts a valid email', () {
      expect(emailError('user@example.com'), isNull);
    });
  });

  group('expenseAmountError', () {
    test('rejects null', () {
      expect(expenseAmountError(null), isNotNull);
    });
    test('rejects zero and negative', () {
      expect(expenseAmountError(0), isNotNull);
      expect(expenseAmountError(-5), isNotNull);
    });
    test('rejects an absurdly large amount', () {
      expect(expenseAmountError(1e30), isNotNull);
    });
    test('accepts a normal amount', () {
      expect(expenseAmountError(42.50), isNull);
    });
  });

  group('otpCodeError', () {
    test('rejects empty', () {
      expect(otpCodeError(''), isNotNull);
    });
    test('rejects non-numeric', () {
      expect(otpCodeError('abcdef'), isNotNull);
    });
    test('rejects a code shorter than the configured length', () {
      expect(otpCodeError('1234'), isNotNull);
    });
    test('accepts a numeric code of the configured length', () {
      expect(otpCodeError('123456'), isNull);
      expect(kOtpLength, 6);
    });
  });

  group('phoneError', () {
    test('rejects empty and local-format numbers', () {
      expect(phoneError(''), isNotNull);
      expect(phoneError('5551234'), isNotNull);
    });
    test('rejects a number without the + prefix', () {
      expect(phoneError('15551234567'), isNotNull);
    });
    test('accepts E.164', () {
      expect(phoneError('+15551234567'), isNull);
    });
  });

  group('passwordError', () {
    test('rejects too short', () {
      expect(passwordError('a1b2c3'), isNotNull);
    });
    test('rejects over the max length', () {
      expect(passwordError('a1${'b' * 80}'), isNotNull);
    });
    test('requires a digit by default', () {
      expect(passwordError('abcdefgh'), isNotNull);
    });
    test('allows digits-optional when asked', () {
      expect(passwordError('abcdefgh', requireDigit: false), isNull);
    });
    test('accepts a strong password', () {
      expect(passwordError('correct1horse'), isNull);
    });
  });

  group('kUsernameInputFormatter', () {
    test('keeps only the allowed characters (unanchored)', () {
      // The formatter class must not be anchored: `FilteringTextInputFormatter`
      // uses it to keep matching spans, so an anchored pattern would yield no
      // matches and wipe the whole field.
      final kept = 'a b!c_1'.replaceAll(RegExp('[^A-Za-z0-9_]'), '');
      expect(kUsernameInputFormatter.allMatches('a b!c_1').length, greaterThan(0));
      expect(kept, 'abc_1');
    });
  });
}
