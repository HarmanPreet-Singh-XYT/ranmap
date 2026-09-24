import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../core/theme/app_theme.dart';
import '../../core/util/error_text.dart';
import '../premium/paywall.dart';
import '../premium/premium_providers.dart';
import 'chat_providers.dart';
import 'voice_providers.dart';

/// A voice channel for one trip/group: join/leave, mute toggle, and a live
/// participant list. Voice and text share the same channel identity
/// (ChatChannel.roomKey is used as the LiveKit room name).
class VoiceChannelScreen extends ConsumerStatefulWidget {
  final ChatChannel channel;
  final String title;

  const VoiceChannelScreen({super.key, required this.channel, required this.title});

  @override
  ConsumerState<VoiceChannelScreen> createState() => _VoiceChannelScreenState();
}

class _VoiceChannelScreenState extends ConsumerState<VoiceChannelScreen> {
  static const _maxReconnectAttempts = 5;

  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _events;
  bool _connecting = true;
  bool _muted = false;
  bool _reconnecting = false;
  bool _leaving = false;
  bool _joining = false;
  int _reconnectAttempts = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _join();
  }

  @override
  void dispose() {
    _leaving = true;
    unawaited(_teardownRoom());
    super.dispose();
  }

  /// Tears down the current room and its event listener, if any.
  Future<void> _teardownRoom() async {
    _events?.dispose();
    _events = null;
    final room = _room;
    _room = null;
    if (room == null) return;
    room.removeListener(_onRoomChanged);
    try {
      await room.disconnect();
    } catch (_) {}
    try {
      await room.dispose();
    } catch (_) {}
  }

  Future<void> _join({bool initial = true}) async {
    // Guard against overlapping joins (Retry + reconnect timer + initState).
    if (_joining) return;
    _joining = true;
    setState(() {
      if (initial) _connecting = true;
      _error = null;
    });
    await _teardownRoom();

    lk.Room? room;
    try {
      final voiceToken = await ref.read(voiceRepositoryProvider).fetchToken(
            tripId: widget.channel.tripId,
            groupId: widget.channel.groupId,
          );
      room = lk.Room();
      room.addListener(_onRoomChanged);
      await room.connect(voiceToken.url, voiceToken.token);
      // Preserve the user's mute intent across a reconnect instead of forcing
      // the mic on behind a "muted" indicator.
      await room.localParticipant?.setMicrophoneEnabled(!_muted);
      if (!mounted) {
        room.removeListener(_onRoomChanged);
        await room.disconnect();
        await room.dispose();
        return;
      }
      _attachRoomEvents(room);
      setState(() {
        _room = room;
        _connecting = false;
        _reconnecting = false;
        _reconnectAttempts = 0;
      });
    } catch (e) {
      // Tear down the half-open room (and its listener) so a failed connect /
      // mic-enable doesn't leak it — "Retry" would otherwise stack rooms.
      if (room != null) {
        room.removeListener(_onRoomChanged);
        await room.disconnect();
        await room.dispose();
      }
      if (!mounted) return;
      // Voice is a Pro feature: show the paywall (never a generic error, and
      // never a reconnect loop), then return to the channel list.
      if (isPremiumRequired(e)) {
        setState(() {
          _error = friendlyError(e);
          _connecting = false;
          _reconnecting = false;
        });
        await showPaywall(context, feature: PremiumFeature.voice);
        if (mounted) Navigator.of(context).maybePop();
        return;
      }
      // A dropped connection during an auto-reconnect retries again; a failed
      // first join (bad token, not a member, backend down) surfaces an error
      // with a manual Retry instead of looping.
      if (_reconnectAttempts > 0) {
        _scheduleReconnect();
      } else {
        setState(() {
          _error = friendlyError(e);
          _connecting = false;
          _reconnecting = false;
        });
      }
    } finally {
      _joining = false;
    }
  }

  void _attachRoomEvents(lk.Room room) {
    final events = room.createListener();
    events.on<lk.RoomReconnectingEvent>((_) {
      if (mounted) setState(() => _reconnecting = true);
    });
    events.on<lk.RoomReconnectedEvent>((_) {
      if (mounted) setState(() => _reconnecting = false);
    });
    // Fired when LiveKit's own reconnect attempts are exhausted (or the room
    // was closed) — re-join from scratch.
    events.on<lk.RoomDisconnectedEvent>((_) {
      if (!_leaving && mounted) _scheduleReconnect();
    });
    _events = events;
  }

  void _scheduleReconnect() {
    if (_leaving || !mounted) return;
    _reconnectAttempts++;
    if (_reconnectAttempts > _maxReconnectAttempts) {
      setState(() {
        _reconnecting = false;
        _connecting = false;
        _error = 'Lost connection to the voice channel.';
      });
      return;
    }
    setState(() => _reconnecting = true);
    // Exponential backoff: 1s, 2s, 4s, 8s, 16s (capped at 30s).
    final seconds = math.min(30, 1 << (_reconnectAttempts - 1));
    Future.delayed(Duration(seconds: seconds), () {
      if (!_leaving && mounted) _join(initial: false);
    });
  }

  void _onRoomChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleMute() async {
    final room = _room;
    if (room?.localParticipant == null) return;
    final next = !_muted;
    try {
      await room!.localParticipant!.setMicrophoneEnabled(!next);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
      return;
    }
    // The room may have been torn down while the await was in flight.
    if (!mounted) return;
    setState(() => _muted = next);
  }

  Future<void> _leave() async {
    _leaving = true;
    await _teardownRoom();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;

    // "Travel together": this channel is unlocked when ANY member is Pro, even
    // if the current user isn't — surface that so it's clear why it works.
    final channel = widget.channel;
    final proAsync = channel.tripId != null
        ? ref.watch(tripProProvider(channel.tripId!))
        : ref.watch(groupProProvider(channel.groupId!));
    final proUnlocked = proAsync.valueOrNull ?? false;

    return Scaffold(
      appBar: AppBar(title: Text('${widget.title} · Voice')),
      body: _connecting
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: () => _join(), child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : room == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          if (_reconnecting) ...[
                            const SizedBox(height: 12),
                            const Text('Reconnecting…'),
                          ],
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        if (_reconnecting) ...[
                          const LinearProgressIndicator(minHeight: 2),
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text('Reconnecting…'),
                          ),
                        ],
                        if (proUnlocked) const _ProVoiceBanner(),
                        Expanded(child: _ParticipantList(room: room)),
                      ],
                    ),
      floatingActionButton: room == null
          ? null
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton(
                  heroTag: 'mute',
                  onPressed: _toggleMute,
                  backgroundColor: _muted ? Colors.grey : null,
                  child: Icon(_muted ? Icons.mic_off_rounded : Icons.mic_rounded),
                ),
                const SizedBox(width: 16),
                FloatingActionButton(
                  heroTag: 'leave',
                  backgroundColor: Colors.red,
                  onPressed: _leave,
                  child: const Icon(Icons.call_end_rounded),
                ),
              ],
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

class _ProVoiceBanner extends StatelessWidget {
  const _ProVoiceBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppTheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: const Row(
        children: [
          Icon(Icons.workspace_premium_rounded, size: 18, color: AppTheme.primary),
          SizedBox(width: 8),
          Expanded(child: Text('Pro voice — unlocked for everyone here')),
        ],
      ),
    );
  }
}

class _ParticipantList extends StatelessWidget {
  final lk.Room room;

  const _ParticipantList({required this.room});

  @override
  Widget build(BuildContext context) {
    final participants = <lk.Participant>[
      if (room.localParticipant != null) room.localParticipant!,
      ...room.remoteParticipants.values,
    ];

    if (participants.isEmpty) {
      return const Center(child: Text('Connecting…'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: participants.length,
      itemBuilder: (context, i) {
        final participant = participants[i];
        final isLocal = participant is lk.LocalParticipant;
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: participant.isSpeaking
                  ? AppTheme.success
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.person),
            ),
            title: Text(participant.name.isNotEmpty ? participant.name : participant.identity),
            subtitle: Text(isLocal ? 'You' : 'In voice'),
            trailing: Icon(
              participant.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              color: participant.isMuted ? Colors.grey : AppTheme.success,
            ),
          ),
        );
      },
    );
  }
}
