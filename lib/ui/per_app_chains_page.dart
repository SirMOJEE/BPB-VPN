import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/settings.dart';
import '../services/vpn_channel.dart';
import '../state/app_state.dart';

/// Per-app chains: which exit each app's traffic takes, instead of the connection's
/// own exit node. Stored in `device.perAppProxy.exits` (package name → choice); the VPN
/// engine applies the choices (per-app routing).
///
/// A choice is 'default' (the connection's exit), 'worker' (the connection itself, no
/// extra hop), 'psiphon', 'tor', or 'chain:<id>' (a saved chain proxy).
class PerAppChainsPage extends StatefulWidget {
  const PerAppChainsPage({super.key});

  @override
  State<PerAppChainsPage> createState() => _PerAppChainsPageState();
}

class _PerAppChainsPageState extends State<PerAppChainsPage> {
  late final Future<List<InstalledApp>> _apps = VpnChannel.installedApps();
  String _query = '';
  bool _showSystem = true;

  /// The exit label for [value], with the saved chains' names.
  static String _label(String value, List<ChainProxy> chains) =>
      switch (value) {
        'default' => 'Follow connection exit',
        'worker' => 'Connection only',
        'psiphon' => 'Psiphon',
        'tor' => 'Tor',
        final v when v.startsWith('chain:') =>
          chains
                  .where((c) => c.id == v.substring('chain:'.length))
                  .firstOrNull
                  ?.name ??
              'Chain proxy (removed)',
        _ => 'Follow connection exit',
      };

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final exits = state.device.perAppExits;
    final chains = state.profile.chains;

    void setExit(String pkg, String value) {
      final next = Map<String, String>.from(exits);
      if (value == 'default') {
        next.remove(pkg);
      } else {
        next[pkg] = value;
      }
      state.write('device.perAppProxy.exits', next);
    }

    Future<void> pickExit(InstalledApp app) async {
      final current = exits[app.packageName] ?? 'default';
      final picked = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(app.label),
          children: [
            RadioGroup<String>(
              groupValue: current,
              onChanged: (v) => Navigator.of(context).pop(v),
              child: Column(
                children: [
                  RadioListTile<String>(
                    value: 'default',
                    title: const Text('Follow connection exit'),
                    subtitle: const Text('Same exit as the connection'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  RadioListTile<String>(
                    value: 'worker',
                    title: const Text('Connection only'),
                    subtitle: const Text('No extra hop, e.g. MASQUE only'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  RadioListTile<String>(
                    value: 'psiphon',
                    title: const Text('Psiphon'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  RadioListTile<String>(
                    value: 'tor',
                    title: const Text('Tor'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  if (chains.isNotEmpty)
                    for (final chain in chains)
                      RadioListTile<String>(
                        value: 'chain:${chain.id}',
                        title: Text(chain.name),
                        subtitle: const Text('Chain proxy'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                      ),
                  if (chains.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        'No chain proxies yet. Add one in Settings → Chain proxies.',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
      if (picked != null && picked != current) {
        setExit(app.packageName, picked);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Per-app chains'),
        actions: [
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
                  state.write('device.perAppProxy.exits', <String, String>{});
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
        ],
      ),
      body: Column(
        spacing: 10,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Choose an exit per app. Apps without a choice follow the '
              "connection's exit. Only apps routed through the VPN are affected.",
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
                return ListView.builder(
                  itemCount: apps.length,
                  itemBuilder: (context, i) {
                    final app = apps[i];
                    final custom = exits.containsKey(app.packageName);
                    return ListTile(
                      leading: app.icon == null
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
                      onTap: () => pickExit(app),
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
