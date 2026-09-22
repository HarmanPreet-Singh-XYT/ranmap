import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/util/error_text.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/profile.dart';
import '../../data/services/supabase_service.dart';
import 'social_providers.dart';

class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Friends'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Friends'),
              Tab(text: 'Requests'),
              Tab(text: 'Find people'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _FriendsTab(),
            _RequestsTab(),
            _FindPeopleTab(),
          ],
        ),
      ),
    );
  }
}

class _FriendsTab extends ConsumerWidget {
  const _FriendsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friendsAsync = ref.watch(friendsProvider);

    return friendsAsync.when(
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('No friends yet. Find people in the next tab.', textAlign: TextAlign.center),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final row = rows[i];
            final other = _otherProfile(row);
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text('@${other?['username'] ?? 'unknown'}'),
              trailing: IconButton(
                icon: const Icon(Icons.person_remove_outlined),
                tooltip: 'Remove friend',
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Remove friend?'),
                      content: Text('Remove @${other?['username'] ?? 'this user'} from your friends?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  try {
                    await ref.read(friendRepositoryProvider).remove(row['id'] as String);
                    ref.invalidate(friendsProvider);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
                    }
                  }
                },
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(friendsProvider)),
    );
  }

  Map<String, dynamic>? _otherProfile(Map<String, dynamic> row) {
    final myUid = SupabaseService.currentUser?.id;
    final isRequester = row['requester_id'] == myUid;
    return isRequester
        ? row['addressee'] as Map<String, dynamic>?
        : row['requester'] as Map<String, dynamic>?;
  }
}

class _RequestsTab extends ConsumerWidget {
  const _RequestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incomingAsync = ref.watch(incomingRequestsProvider);
    final outgoingAsync = ref.watch(outgoingRequestsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Incoming', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        incomingAsync.when(
          data: (rows) {
            if (rows.isEmpty) return const Text('No pending requests.');
            return Column(
              children: rows.map((row) {
                final requester = row['requester'] as Map<String, dynamic>?;
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text('@${requester?['username'] ?? 'unknown'}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check_circle, color: Colors.green),
                          onPressed: () async {
                            try {
                              await ref
                                  .read(friendRepositoryProvider)
                                  .respond(friendshipId: row['id'] as String, accept: true);
                              ref.invalidate(incomingRequestsProvider);
                              ref.invalidate(friendsProvider);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(content: Text(friendlyError(e))));
                              }
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel, color: Colors.redAccent),
                          onPressed: () async {
                            try {
                              await ref
                                  .read(friendRepositoryProvider)
                                  .respond(friendshipId: row['id'] as String, accept: false);
                              ref.invalidate(incomingRequestsProvider);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(content: Text(friendlyError(e))));
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(incomingRequestsProvider)),
        ),
        const SizedBox(height: 24),
        Text('Sent', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        outgoingAsync.when(
          data: (rows) {
            if (rows.isEmpty) return const Text('No outgoing requests.');
            return Column(
              children: rows.map((row) {
                final addressee = row['addressee'] as Map<String, dynamic>?;
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text('@${addressee?['username'] ?? 'unknown'}'),
                  trailing: TextButton(
                    onPressed: () async {
                      try {
                        await ref.read(friendRepositoryProvider).remove(row['id'] as String);
                        ref.invalidate(outgoingRequestsProvider);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(friendlyError(e))));
                        }
                      }
                    },
                    child: const Text('Cancel'),
                  ),
                );
              }).toList(),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(outgoingRequestsProvider)),
        ),
      ],
    );
  }
}

class _FindPeopleTab extends ConsumerStatefulWidget {
  const _FindPeopleTab();

  @override
  ConsumerState<_FindPeopleTab> createState() => _FindPeopleTabState();
}

class _FindPeopleTabState extends ConsumerState<_FindPeopleTab> {
  final _controller = TextEditingController();
  String _query = '';
  final Set<String> _requested = {};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(usernameSearchProvider(_query));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _controller,
            decoration: const InputDecoration(labelText: 'Search by username', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: resultsAsync.when(
            data: (results) {
              if (_query.trim().length < 2) {
                return const Center(child: Text('Type at least 2 characters to search.'));
              }
              if (results.isEmpty) {
                return const Center(child: Text('No matches.'));
              }
              return ListView.builder(
                itemCount: results.length,
                itemBuilder: (context, i) {
                  final Profile profile = results[i];
                  final alreadyRequested = _requested.contains(profile.id);
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text('@${profile.username}'),
                    trailing: alreadyRequested
                        ? Text('Requested',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
                        : ElevatedButton(
                            onPressed: () async {
                              try {
                                await ref.read(friendRepositoryProvider).sendRequest(profile.id);
                                setState(() => _requested.add(profile.id));
                                ref.invalidate(outgoingRequestsProvider);
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(content: Text(friendlyError(e))));
                                }
                              }
                            },
                            child: const Text('Add'),
                          ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                ErrorRetry(error: e, onRetry: () => ref.invalidate(usernameSearchProvider(_query))),
          ),
        ),
      ],
    );
  }
}
