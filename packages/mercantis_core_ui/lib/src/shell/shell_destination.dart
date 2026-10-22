import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One primary destination in the phone bottom bar. Unlike a
/// [WorkspaceDescriptor] (a whole module), a destination is any location the
/// host wants one tap away — a workspace (`/w/home`), a record list
/// (`/list/Customer`) or a task screen (`/w/sales/pos-till`) — so a product can
/// shape its phone surface around jobs to be done rather than its module map.
class ShellDestination {
  const ShellDestination({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.location,
    this.matchPrefixes = const [],
    this.semanticsHint,
  });

  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Where a tap goes.
  final String location;

  /// Extra location prefixes that count as "inside" this destination, so the
  /// bar keeps it selected while the user drills in (e.g. `/form/Customer/`
  /// for a Customers tab whose [location] is `/list/Customer`).
  final List<String> matchPrefixes;

  /// Optional screen-reader hint read after the label.
  final String? semanticsHint;

  bool matches(String current) {
    // The router may hand over a percent-encoded location
    // (`/list/Sales%20Invoice`); compare decoded paths.
    final loc = Uri.decodeFull(current);
    for (final p in [location, ...matchPrefixes]) {
      if (loc == p || loc.startsWith(p.endsWith('/') ? p : '$p/') ||
          loc.startsWith('$p?')) {
        return true;
      }
    }
    return false;
  }
}

/// The most phone bottom-bar slots a host may fill. The shell always adds a
/// fifth "More" slot, so the bar never shows more than five destinations.
const kMaxPhonePrimaryDestinations = 4;

/// The phone bottom bar's primary destinations. `null` (the default) keeps the
/// legacy behaviour: the first visible workspaces, then "More". Hosts override
/// this to give the phone a task-shaped surface; every visible workspace stays
/// reachable from the "More" sheet.
final phoneDestinationsProvider =
    Provider<List<ShellDestination>?>((_) => null);
