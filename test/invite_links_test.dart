import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/core/constants/invite_links.dart';

void main() {
  group('inviteUsernameFromUri', () {
    test('reads the handle from a production web invite', () {
      expect(
        inviteUsernameFromUri(Uri.parse('https://ranmap.app/invite/dave')),
        'dave',
      );
    });

    test('tolerates a trailing slash', () {
      expect(
        inviteUsernameFromUri(Uri.parse('https://ranmap.app/invite/dave/')),
        'dave',
      );
    });

    test('reads the handle from a custom-scheme invite', () {
      expect(
        inviteUsernameFromUri(Uri.parse('com.ranmap.app://invite/dave')),
        'dave',
      );
    });

    test('ignores a web link on another host', () {
      expect(
        inviteUsernameFromUri(Uri.parse('https://evil.example/invite/dave')),
        null,
      );
    });

    test('ignores a non-invite path', () {
      expect(
        inviteUsernameFromUri(Uri.parse('https://ranmap.app/about')),
        null,
      );
    });

    test('ignores the OAuth callback on the same scheme', () {
      expect(
        inviteUsernameFromUri(Uri.parse('com.ranmap.app://login-callback')),
        null,
      );
    });

    test('ignores unrelated schemes', () {
      expect(
        inviteUsernameFromUri(Uri.parse('https://example.com/invite/dave')),
        null,
      );
    });
  });

  group('invite links', () {
    test('the custom-scheme link round-trips through the parser', () {
      final link = inviteSchemeLinkFor('dave');
      expect(link, 'com.ranmap.app://invite/dave');
      expect(inviteUsernameFromUri(Uri.parse(link)), 'dave');
    });

    test('a shared link parses back to the same handle', () {
      expect(inviteUsernameFromUri(Uri.parse(inviteLinkFor('dave'))), 'dave');
    });
  });
}
