import 'package:flutter/material.dart';

import '../../core/theme/brand_palette.dart';

/// One of the four bento tiles on a feature-tour page.
sealed class TourTile {
  const TourTile();
}

/// A photographic tile with an optional frosted badge.
class TourPhoto extends TourTile {
  const TourPhoto(
    this.asset, {
    this.badgeIcon,
    this.badgeLabel,
    this.badgeDot = false,
    this.badgeAccent = false,
  });

  final String asset;
  final IconData? badgeIcon;
  final String? badgeLabel;

  /// Shows a small pulsing leading dot in the badge.
  final bool badgeDot;

  /// Fills the badge grass-green (used for the "settled" confirmation).
  final bool badgeAccent;
}

/// A pastel stat / illustration tile.
class TourStat extends TourTile {
  const TourStat({
    required this.color,
    required this.icon,
    this.iconColor,
    this.eyebrow,
    this.title,
    this.subtitle,
    this.subtitleIcon,
    this.chip,
    this.chipIcon,
    this.trailing,
    this.trailingColor,
    this.dotColor,
    this.liveDot = false,
    this.big,
  });

  final Color color;
  final IconData icon;
  final Color? iconColor;

  /// Small uppercase label, prefixed with a status dot.
  final String? eyebrow;
  final String? title;
  final String? subtitle;
  final IconData? subtitleIcon;

  /// A pill-shaped value chip (e.g. "Stops synced").
  final String? chip;
  final IconData? chipIcon;

  /// A small pill in the top-right (e.g. "PTT", "ZERO-LAG").
  final String? trailing;
  final Color? trailingColor;

  final Color? dotColor;

  /// Replaces the trailing pill with a live status dot.
  final bool liveDot;

  /// A large headline figure (e.g. "18" / "ms ping") in place of [title].
  final ({String value, String unit})? big;
}

/// A highlight row beneath the collage.
class TourFeature {
  const TourFeature({
    required this.icon,
    required this.title,
    required this.body,
    this.iconBg,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color? iconBg;
  final Color? iconColor;
}

/// A single page of the pre-auth feature tour.
class TourPage {
  const TourPage({
    required this.step,
    required this.sectionLabel,
    required this.tag,
    required this.headline,
    required this.body,
    required this.tiles,
    required this.features,
    required this.nextLabel,
  });

  /// e.g. `01 / 05`.
  final String step;

  /// Small label shown opposite the step counter.
  final String sectionLabel;
  final String tag;
  final String headline;
  final String body;

  /// Exactly four tiles, laid out 2×2 in reading order.
  final List<TourTile> tiles;
  final List<TourFeature> features;

  /// Label for the advance CTA on this page.
  final String nextLabel;
}

Color _tint(Color base, double alpha) => base.withValues(alpha: alpha);

/// The five-page "feature tour" shown once, before the welcome screen.
final List<TourPage> kTourPages = [
  TourPage(
    step: '01 / 05',
    sectionLabel: 'Convoy Sync',
    tag: 'Convoy Sync & HUD',
    headline: 'Never Lose Your Pack',
    body: 'Real-time 3D telemetry and position tracking for group road trips. If someone drops behind or takes a detour, instant radar lock guides them back smoothly.',
    nextLabel: 'Next: Audio Comms',
    tiles: [
      TourPhoto('assets/images/tour/convoy_coast.jpg', badgeLabel: 'Convoy'),
      TourStat(
        color: BrandColors.accentPeach,
        icon: Icons.directions_car_rounded,
        iconColor: BrandColors.textHeadline,
        eyebrow: 'Live Convoy',
        title: 'Mesh Active',
        liveDot: true,
      ),
      TourStat(
        color: BrandColors.accentMint,
        icon: Icons.explore_rounded,
        iconColor: BrandColors.primary,
        eyebrow: '3D Tracking',
        title: 'Precision tracking',
        liveDot: true,
      ),
      TourPhoto(
        'assets/images/tour/cabin_nav.jpg',
        badgeIcon: Icons.social_distance_rounded,
        badgeLabel: 'Safe-gap alerts',
      ),
    ],
    features: const [
      TourFeature(
        icon: Icons.sensors_rounded,
        title: 'Sub-Second GPS Updates',
        body: 'Telemetry synced across lead car, pack, and chase scout.',
      ),
      TourFeature(
        icon: Icons.shield_rounded,
        title: 'Adaptive Safe Gap Distance',
        body:
            'Dynamic speed pacing alerts if someone falls out of convoy line.',
      ),
    ],
  ),
  TourPage(
    step: '02 / 05',
    sectionLabel: 'Connected Audio',
    tag: 'Crew Comms',
    headline: 'Walkie-Talkie in Your Pocket',
    body: 'One-touch Push-to-Talk audio built straight into your driving view. Keep both hands firmly on the wheel while chatting with your entire convoy hands-free.',
    nextLabel: 'Next: Smart Pitstops',
    tiles: [
      TourStat(
        color: _tint(BrandColors.accentSky, 0.5),
        icon: Icons.graphic_eq_rounded,
        iconColor: BrandColors.primary,
        title: 'Convoy channel',
        subtitle: 'Everyone hears you',
        trailing: 'PTT',
        liveDot: true,
      ),
      const TourPhoto(
        'assets/images/tour/camper_friends.jpg',
        badgeIcon: Icons.groups_rounded,
        badgeLabel: 'Lead Van',
      ),
      const TourPhoto(
        'assets/images/tour/coastal_forest.jpg',
        badgeIcon: Icons.navigation_rounded,
        badgeLabel: 'Pacific Crest',
      ),
      TourStat(
        color: _tint(BrandColors.accentPeach, 0.6),
        icon: Icons.headphones_rounded,
        iconColor: BrandColors.onTertiaryContainer,
        title: 'Low-latency audio',
        subtitle: 'AI Noise Gate',
        subtitleIcon: Icons.check_circle_rounded,
        trailing: 'ZERO-LAG',
        trailingColor: BrandColors.onTertiaryContainer,
      ),
    ],
    features: [
      TourFeature(
        icon: Icons.mic_rounded,
        title: 'Ultra Low-Latency LiveKit',
        body: 'Automated road noise gate and highway wind cancellation.',
        iconBg: BrandColors.secondaryFixed,
      ),
      TourFeature(
        icon: Icons.volume_down_rounded,
        title: 'Smart Audio Ducking',
        body: 'Seamlessly lowers music volume the instant a fellow driver speaks.',
        iconBg: BrandColors.neutralButton,
      ),
    ],
  ),
  TourPage(
    step: '03 / 05',
    sectionLabel: 'Itinerary & Pitstops',
    tag: 'Itinerary & Pitstops',
    headline: 'Stops for the Whole Pack',
    body: 'Never argue about where to pull over. RanMap syncs scenic turnouts, EV superchargers, and crowd-voted foodie stops directly into every driver’s route.',
    nextLabel: 'Next: Offline Mesh',
    tiles: [
      TourPhoto(
        'assets/images/tour/bakery.jpg',
        badgeIcon: Icons.local_cafe_rounded,
        badgeLabel: 'Scenic stop',
      ),
      TourStat(
        color: BrandColors.secondaryFixed,
        icon: Icons.turn_right_rounded,
        iconColor: BrandColors.primary,
        eyebrow: 'Crew Stops',
        title: 'Artisan Roast & View',
        chip: 'Stops synced',
        liveDot: true,
      ),
      TourStat(
        color: BrandColors.accentPeach,
        icon: Icons.ev_station_rounded,
        iconColor: BrandColors.tertiary,
        eyebrow: 'Charge & Fuel',
        title: 'High-Power Fast Charge',
        chip: 'Charging stops',
        chipIcon: Icons.bolt_rounded,
      ),
      TourPhoto(
        'assets/images/tour/overlook_crew.jpg',
        badgeIcon: Icons.group_rounded,
        badgeLabel: '4 in Convoy',
      ),
    ],
    features: const [
      TourFeature(
        icon: Icons.how_to_vote_rounded,
        title: 'Synchronized Pitstop Voting',
        body: 'Crew members vote on upcoming stops; routes update automatically across all cars.',
      ),
      TourFeature(
        icon: Icons.battery_charging_full_rounded,
        title: 'Range-Aware Route Timing',
        body: 'Itinerary automatically factors in vehicle range and slowest car battery levels.',
      ),
    ],
  ),
  TourPage(
    step: '04 / 05',
    sectionLabel: 'Road Hazards',
    tag: 'Road Hazards & Safety',
    headline: 'Ahead of the Pack,\nFree from Surprises.',
    body: 'Spot debris, stopped cars, and sudden speed traps before you reach them. When lead vehicles flag a hazard or detour, your entire convoy gets warned with distance countdowns.',
    nextLabel: 'Next: Shared Expenses',
    tiles: [
      TourPhoto(
        'assets/images/tour/canyon.jpg',
        badgeIcon: Icons.cloud_download_rounded,
        badgeLabel: 'Offline Corridor',
      ),
      TourStat(
        color: BrandColors.accentLavender,
        icon: Icons.fmd_bad_rounded,
        iconColor: BrandColors.primary,
        eyebrow: 'Speed & Hazards',
        title: 'Lead Car Radar',
        subtitle: 'Zero Surprise Delays',
        liveDot: true,
      ),
      TourStat(
        color: BrandColors.hazardContainer,
        icon: Icons.warning_rounded,
        iconColor: BrandColors.error,
        eyebrow: 'Road Hazard',
        title: 'Hazard alerts',
        subtitle: 'Shared by the lead car',
        dotColor: BrandColors.error,
      ),
      TourPhoto(
        'assets/images/tour/tunnel.jpg',
        badgeIcon: Icons.sync_rounded,
        badgeLabel: 'Convoy Synced',
      ),
    ],
    features: [
      TourFeature(
        icon: Icons.radar_rounded,
        title: 'Lead Car Hazard Radar',
        body: 'Lead vehicles broadcast one-tap road alerts—from potholes and wildlife to construction—with live audio chimes and distance countdowns.',
      ),
      TourFeature(
        icon: Icons.travel_explore_rounded,
        title: 'Offline Cached Route Maps',
        body: 'Download complete trip corridors before you roll out, and navigate with zero cellular bars.',
        iconBg: BrandColors.accentPeach,
        iconColor: BrandColors.tertiary,
      ),
    ],
  ),
  TourPage(
    step: '05 / 05',
    sectionLabel: 'Trip Ledger & Vault',
    tag: 'Expense & Memories',
    headline: 'Split Fairly, Drive Freely',
    body: 'Fuel, highway tolls, national park passes, and roadside snacks tallied automatically. One tap calculates equal settlements so no one owes a penny after the trip.',
    nextLabel: 'Get Started',
    tiles: [
      const TourPhoto(
        'assets/images/tour/golden_crew.jpg',
        badgeIcon: Icons.favorite_rounded,
        badgeLabel: 'Trip memories',
      ),
      TourStat(
        color: _tint(BrandColors.accentMint, 0.3),
        icon: Icons.receipt_long_rounded,
        iconColor: BrandColors.primary,
        eyebrow: 'Split Expenses',
        chip: 'Zero Debt Math',
        trailing: 'Live Split',
      ),
      TourStat(
        color: _tint(BrandColors.accentPeach, 0.5),
        icon: Icons.photo_library_rounded,
        iconColor: BrandColors.tertiary,
        eyebrow: 'Trip Vault',
        chip: 'Shared album',
        trailing: 'Cloud Sync',
        trailingColor: BrandColors.tertiary,
      ),
      const TourPhoto(
        'assets/images/tour/tailgate.jpg',
        badgeIcon: Icons.check_circle_rounded,
        badgeLabel: 'Settle up fast',
        badgeAccent: true,
      ),
    ],
    features: [
      TourFeature(
        icon: Icons.price_check_rounded,
        title: 'Automated Equal Settlements',
        body: 'Multi-currency ledger with 1-tap balance clearing via Apple Pay & Venmo.',
        iconBg: BrandColors.secondaryFixed,
        iconColor: BrandColors.onSecondaryFixedVariant,
      ),
      TourFeature(
        icon: Icons.auto_awesome_motion_rounded,
        title: 'Collaborative Photo Timeline',
        body: 'Route-stamped photos uploaded by all pilots into a single shared album.',
        iconBg: BrandColors.accentPeach,
        iconColor: BrandColors.onTertiaryFixedVariant,
      ),
    ],
  ),
];
