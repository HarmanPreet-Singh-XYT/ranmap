import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/data/models/group.dart';

void main() {
  group('Group.fromJson', () {
    test('reads the group fields including invites', () {
      final group = Group.fromJson(const {
        'id': 'g1',
        'name': 'Weekend crew',
        'owner_id': 'u1',
        'description': 'Ride out on Saturdays',
        'avatar_id': 'abcdef012345',
        'invite_code': '3f9a1c2b4d5e',
        'invite_requires_approval': true,
      });

      expect(group.id, 'g1');
      expect(group.name, 'Weekend crew');
      expect(group.ownerId, 'u1');
      expect(group.description, 'Ride out on Saturdays');
      expect(group.avatarId, 'abcdef012345');
      expect(group.inviteCode, '3f9a1c2b4d5e');
      expect(group.inviteRequiresApproval, isTrue);
    });

    test('falls back to safe defaults when the optional fields are absent', () {
      final group = Group.fromJson(const {
        'id': 'g2',
        'name': 'Solo',
        'owner_id': 'u2',
      });

      expect(group.description, isNull);
      expect(group.avatarId, 'default');
      expect(group.inviteCode, isNull);
      expect(group.inviteRequiresApproval, isFalse);
    });
  });

  group('groupRoleFromString', () {
    test('maps known roles and defaults the rest to member', () {
      expect(groupRoleFromString('owner'), GroupRole.owner);
      expect(groupRoleFromString('admin'), GroupRole.admin);
      expect(groupRoleFromString('member'), GroupRole.member);
      expect(groupRoleFromString(null), GroupRole.member);
      expect(groupRoleFromString('garbage'), GroupRole.member);
    });
  });

  group('joinGroupResultFromString', () {
    test('maps every server outcome', () {
      expect(joinGroupResultFromString('joined'), JoinGroupResult.joined);
      expect(joinGroupResultFromString('pending'), JoinGroupResult.pending);
      expect(
        joinGroupResultFromString('already_member'),
        JoinGroupResult.alreadyMember,
      );
      expect(
        joinGroupResultFromString('already_requested'),
        JoinGroupResult.alreadyRequested,
      );
      expect(joinGroupResultFromString('not_found'), JoinGroupResult.notFound);
      expect(
        joinGroupResultFromString('anything-else'),
        JoinGroupResult.notFound,
      );
    });
  });

  group('GroupInvitePreview.fromJson', () {
    test('reads the preview and defaults membership to none', () {
      final preview = GroupInvitePreview.fromJson(const {
        'group_id': 'g1',
        'name': 'Weekend crew',
        'description': 'Ride out',
        'avatar_id': 'abc',
        'member_count': 4,
        'requires_approval': true,
      });

      expect(preview.groupId, 'g1');
      expect(preview.memberCount, 4);
      expect(preview.requiresApproval, isTrue);
      expect(preview.membership, 'none');
    });
  });
}
