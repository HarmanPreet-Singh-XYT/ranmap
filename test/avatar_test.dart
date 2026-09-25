import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ranmap/core/constants/avatars.dart';
import 'package:ranmap/core/widgets/avatar_view.dart';

void main() {
  test('randomAvatarSeed produces distinct 12-char hex seeds', () {
    final seeds = {for (var i = 0; i < 50; i++) randomAvatarSeed()};
    expect(seeds.length, 50, reason: 'seeds should not collide');
    expect(
      seeds.every((s) => s.length == 12 && RegExp(r'^[0-9a-f]{12}$').hasMatch(s)),
      isTrue,
      reason: 'seeds are DB-safe lowercase hex',
    );
  });

  test('avatarSeedCandidates includes the current pick and is distinct', () {
    final candidates = avatarSeedCandidates(count: 12, include: 'keepme');
    expect(candidates.length, 12);
    expect(candidates.first, 'keepme');
    expect(candidates.toSet().length, 12);
  });

  test('Multiavatar SVG generation is deterministic and non-empty', () {
    final first = AvatarView.svgFor('abc123');
    expect(first, isNotEmpty);
    // Same seed -> same avatar (identicon), different seed -> different markup.
    expect(AvatarView.svgFor('abc123'), equals(first));
    expect(AvatarView.svgFor('different'), isNot(equals(first)));
  });

  test('custom (uploaded) avatar ids round-trip through the prefix helpers', () {
    const path = 'uid-123/avatar-1.png';
    final id = customAvatarId(path);
    expect(id, 'custom:uid-123/avatar-1.png');
    expect(isCustomAvatar(id), isTrue);
    expect(customAvatarPath(id), path);

    // Seeds are anything without the prefix — including legacy values, which
    // is what makes this backward compatible with no migration.
    expect(isCustomAvatar('abc123'), isFalse);
    expect(isCustomAvatar(kDefaultAvatarSeed), isFalse);
    expect(isCustomAvatar('fox'), isFalse);
  });

  test('avatarSeedCandidates never includes a custom avatar id', () {
    final candidates = avatarSeedCandidates(count: 6, include: customAvatarId('u/a.png'));
    expect(candidates.length, 6);
    expect(candidates.any(isCustomAvatar), isFalse);
  });

  test('customAvatarUrl targets the public avatars bucket', () {
    // Trailing slash in the configured URL must not produce a double slash.
    dotenv.testLoad(fileInput: 'SUPABASE_URL=https://proj.supabase.co/');
    expect(
      customAvatarUrl('uid-1/a.png'),
      'https://proj.supabase.co/storage/v1/object/public/avatars/uid-1/a.png',
    );
  });
}
