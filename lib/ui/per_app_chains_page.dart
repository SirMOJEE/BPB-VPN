import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/settings.dart';
import '../services/vpn_channel.dart';
import '../state/app_state.dart';

/// Per-app chains: whether each app's traffic goes through the chain (the
/// connection's exit) or not. Stored in `device.perAppProxy.exits` (package
/// name → choice). NOTE: the tunnel does not apply per-app choices yet —
/// Xray's tun inbound cannot see which app traffic belongs to; that needs a
/// native per-app dispatch layer. The domain chains do work in the tunnel.
///
/// A choice is 'default' (through the chain: the connection's exit, whatever
/// it is — Psiphon, Tor or a chain proxy) or 'worker' (no chain: the
/// connection itself, no extra hop).
///
/// Long-press an app to select several at once, then set one exit for all of them.
/// The ⋮ menu sets all apps at once (through chain / no chain).
class PerAppChainsPage extends StatefulWidget {
  const PerAppChainsPage({super.key});

  @override
  State<PerAppChainsPage> createState() => _PerAppChainsPageState();
}

class _PerAppChainsPageState extends State<PerAppChainsPage> {
  late final Future<List<InstalledApp>> _apps = VpnChannel.installedApps();
  String _query = '';
  bool _showSystem = true;

  /// Packages selected for a bulk exit change. Empty = normal (single-app) mode.
  final Set<String> _selected = {};

  /// Apps currently visible (after the search/system filters), as last rendered.
  /// Used by "Select all" and by the bulk exit picker.
  List<InstalledApp> _visibleApps = [];

  void _toggle(String pkg) {
    setState(() {
      if (_selected.contains(pkg)) {
        _selected.remove(pkg);
      } else {
        _selected.add(pkg);
      }
    });
  }

  /// The exit label for [value], with the saved chains' names.
  static String _label(String value, List<ChainProxy> chains) =>
      switch (value) {
        'default' => 'Through chain',
        'worker' => 'No chain',
        // Older installs may hold a specific exit; it still shows.
        'psiphon' => 'Psiphon',
        'tor' => 'Tor',
        final v when v.startsWith('chain:') =>
          chains
                  .where((c) => c.id == v.substring('chain:'.length))
                  .firstOrNull
                  ?.name ??
              'Chain proxy (removed)',
        _ => 'Through chain',
      };

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final exits = state.device.perAppExits;
    final chains = state.profile.chains;
    final selecting = _selected.isNotEmpty;

    void setExits(Iterable<String> pkgs, String value) {
      final next = Map<String, String>.from(exits);
      for (final pkg in pkgs) {
        if (value == 'default') {
          next.remove(pkg);
        } else {
          next[pkg] = value;
        }
      }
      state.write('device.perAppProxy.exits', next);
    }

    Future<void> pickExit(List<InstalledApp> apps) async {
      // Preselect the shared exit when all picked apps agree; otherwise none.
      final String? current = apps.length == 1
          ? exits[apps.single.packageName] ?? 'default'
          : () {
              final values = apps
                  .map((a) => exits[a.packageName] ?? 'default')
                  .toSet();
              return values.length == 1 ? values.single : null;
            }();
      final picked = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(
            apps.length == 1 ? apps.single.label : '${apps.length} apps',
          ),
          children: [
            RadioGroup<String>(
              groupValue: current,
              onChanged: (v) => Navigator.of(context).pop(v),
              child: Column(
                children: [
                  RadioListTile<String>(
                    value: 'default',
                    title: const Text('Through chain'),
                    subtitle: const Text(
                      "Uses the connection's exit node",
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  RadioListTile<String>(
                    value: 'worker',
                    title: const Text('No chain'),
                    subtitle: const Text(
                      'Direct through the connection, no extra hop',
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
      if (picked != null) {
        setExits(apps.map((a) => a.packageName), picked);
        if (selecting) setState(() => _selected.clear());
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: selecting
            ? IconButton(
                tooltip: 'Cancel selection',
                icon: const Icon(Symbols.close_rounded),
                onPressed: () => setState(() => _selected.clear()),
              )
            : null,
        title: Text(
          selecting ? '${_selected.length} selected' : 'Per-app chains',
        ),
        actions: [
          if (selecting) ...[
            TextButton(
              onPressed: () =>
                  setState(() => _selected.addAll(
                    _visibleApps.map((a) => a.packageName),
                  )),
              child: const Text('Select all'),
            ),
            IconButton(
              tooltip: 'Set exit for selected',
              icon: const Icon(Symbols.alt_route_rounded),
              onPressed: () {
                final apps = _visibleApps
                    .where((a) => _selected.contains(a.packageName))
                    .toList();
                if (apps.isNotEmpty) pickExit(apps);
              },
            ),
          ] else ...[
            if (exits.isNotEmpty)
              IconButton(
                tooltip: 'Reset all to default',
                icon: const Icon(Symbols.delete_outline_rounded),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Reset per-app chains?'),
                      content: const Text(
                        'Every app follows the connection exit again.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    state.write(
                      'device.perAppProxy.exits',
                      <String, String>{},
                    );
                  }
                },
              ),
            IconButton(
              tooltip: _showSystem ? 'Hide system apps' : 'Show system apps',
              icon: Icon(
                _showSystem ? Symbols.android_rounded : Symbols.apps_rounded,
              ),
              onPressed: () => setState(() => _showSystem = !_showSystem),
            ),
            PopupMenuButton<String>(
              tooltip: 'Set all apps at once',
              icon: const Icon(Symbols.more_vert_rounded),
              onSelected: (value) async {
                final all = await _apps;
                if (!context.mounted) return;
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(
                      value == 'worker'
                          ? 'No chain for all apps?'
                          : 'Chain for all apps?',
                    ),
                    content: const Text(
                      'You can still change single apps after that.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  setExits(
                    all.map((a) => a.packageName),
                    value == 'worker' ? 'worker' : 'default',
                  );
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'default',
                  child: Text('All through chain'),
                ),
                PopupMenuItem(
                  value: 'worker',
                  child: Text('All no chain'),
                ),
              ],
            ),
          ],
        ],
      ),
      body: Column(
        spacing: 10,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Choose whether each app goes through the chain — the '
              "connection's exit node, whatever it is. Apps without a choice "
              "follow the connection's exit. Long-press to select several "
              'apps at once, then set one exit for all of them. The ⋮ menu '
              'sets all apps at once. Only apps routed through the VPN are '
              'affected.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Symbols.search_rounded),
                hintText: 'Search apps',
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<InstalledApp>>(
              future: _apps,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Could not list apps: ${snapshot.error}'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final apps =
                    snapshot.data!
                        .where(
                          (a) =>
                              _showSystem ||
                              !a.isSystem ||
                              exits.containsKey(a.packageName),
                        )
                        .where(
                          (a) =>
                              _query.isEmpty ||
                              a.label.toLowerCase().contains(_query) ||
                              a.packageName.toLowerCase().contains(_query),
                        )
                        .toList()
                      // Apps with a custom exit first.
                      ..sort((a, b) {
                        final ca = exits.containsKey(a.packageName) ? 0 : 1;
                        final cb = exits.containsKey(b.packageName) ? 0 : 1;
                        return ca != cb
                            ? ca - cb
                            : a.label.toLowerCase().compareTo(
                                b.label.toLowerCase(),
                              );
                      });
                _visibleApps = apps;
                return ListView.builder(
                  itemCount: apps.length,
                  itemBuilder: (context, i) {
                    final app = apps[i];
                    final custom = exits.containsKey(app.packageName);
                    final selected = _selected.contains(app.packageName);
                    return ListTile(
                      selected: selected,
                      leading: selecting
                          ? Checkbox(
                              value: selected,
                              onChanged: (_) => _toggle(app.packageName),
                            )
                          : app.icon == null
                          ? const Icon(Symbols.android_rounded, size: 40)
                          : Image.memory(
                              app.icon!,
                              width: 40,
                              height: 40,
                              gaplessPlayback: true,
                            ),
                      title: Text(app.label),
                      subtitle: Text(
                        app.packageName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _label(
                              exits[app.packageName] ?? 'default',
                              chains,
                            ),
                            style: TextStyle(
                              color: custom
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Symbols.chevron_right_rounded, size: 20),
                        ],
                      ),
                      onTap: () => selecting
                          ? _toggle(app.packageName)
                          : pickExit([app]),
                      onLongPress: () => _toggle(app.packageName),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
