import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/settings.dart';
import '../state/app_state.dart';
import 'prefs.dart';

/// Per-domain chains: whether each domain's traffic goes through the chain
/// (the connection's exit) or direct, instead of following the connection.
/// Stored in `device.domainExits` (domain → choice); the VPN engine applies
/// the choices as Xray routing rules, so no native change was needed: Xray
/// sniffs the domain and its rules run before the catch-all.
///
/// A choice is 'default' (through the chain: the connection's exit, whatever
/// it is) or 'worker' (no chain: the connection itself, no extra hop). A
/// domain also covers its subdomains.
class PerDomainChainsPage extends StatefulWidget {
  const PerDomainChainsPage({super.key});

  @override
  State<PerDomainChainsPage> createState() => _PerDomainChainsPageState();
}

class _PerDomainChainsPageState extends State<PerDomainChainsPage> {
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
    final exits = state.device.domainExits;
    final chains = state.profile.chains;

    void setExit(String domain, String value) {
      final next = Map<String, String>.from(exits);
      if (value == 'default') {
        next.remove(domain);
      } else {
        next[domain] = value;
      }
      state.write('device.domainExits', next);
    }

    Future<void> pickExit(String domain, String current) async {
      final picked = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(domain),
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
      if (picked != null && picked != current) {
        setExit(domain, picked);
      }
    }

    Future<void> addDomain() async {
      final controller = TextEditingController();
      final result = await showDialog<String?>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Add domain'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'example.com',
                  isDense: true,
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) =>
                    Navigator.of(context).pop(controller.text),
              ),
              const SizedBox(height: 8),
              const Text(
                "The domain goes direct, without the connection's exit.",
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Add'),
            ),
          ],
        ),
      );
      if (result == null) return;
      final domain = result
          .trim()
          .toLowerCase()
          .replaceFirst(RegExp(r'^https?://'), '')
          .split('/')
          .first
          .replaceFirst(RegExp(r'^www\.'), '');
      if (!isDomain(domain)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('That does not look like a domain.'),
            ),
          );
        }
        return;
      }
      setExit(domain, 'worker');
    }

    final domains = exits.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Domain chains'),
        actions: [
          if (exits.isNotEmpty)
            IconButton(
              tooltip: 'Reset all to default',
              icon: const Icon(Symbols.delete_outline_rounded),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Reset domain chains?'),
                    content: const Text(
                      'Every domain follows the connection exit again.',
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
                  state.write('device.domainExits', <String, String>{});
                }
              },
            ),
        ],
      ),
      body: Column(
        spacing: 10,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Domains listed here go direct, without the connection\'s '
              "exit. Other domains follow the connection's exit. One domain "
              'also covers its subdomains.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: addDomain,
              icon: const Icon(Symbols.add_rounded),
              label: const Text('Add domain'),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: domains.isEmpty
                ? const Center(
                    child: Text('No domains yet. Add one above.'),
                  )
                : ListView.builder(
                    itemCount: domains.length,
                    itemBuilder: (context, i) {
                      final domain = domains[i];
                      final value = exits[domain] ?? 'default';
                      return ListTile(
                        title: Text(domain),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _label(value, chains),
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(
                                Symbols.delete_outline_rounded,
                              ),
                              onPressed: () => setExit(domain, 'default'),
                            ),
                          ],
                        ),
                        onTap: () => pickExit(domain, value),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
