import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/settings.dart';
import '../state/app_state.dart';
import 'prefs.dart';

/// Per-domain chains: which exit each domain's traffic takes, instead of the
/// connection's own exit node. Stored in `device.domainExits` (domain → choice);
/// the VPN engine applies the choices as Xray routing rules, so no native change
/// was needed: Xray sniffs the domain and its rules run before the catch-all.
///
/// A choice is 'default' (the connection's exit), 'worker' (the connection itself,
/// no extra hop), 'psiphon', 'tor', or 'chain:<id>' (a saved chain proxy). Only
/// one of Psiphon/Tor can run as an extra exit process: when domains use both,
/// Tor runs and the Psiphon domains follow the connection's exit. A domain also
/// covers its subdomains.
class PerDomainChainsPage extends StatefulWidget {
  const PerDomainChainsPage({super.key});

  @override
  State<PerDomainChainsPage> createState() => _PerDomainChainsPageState();
}

class _PerDomainChainsPageState extends State<PerDomainChainsPage> {
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
        setExit(domain, picked);
      }
    }

    Future<void> addDomain() async {
      final controller = TextEditingController();
      var choice = 'tor';
      final result = await showDialog<(String, String)?>(
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
                    Navigator.of(context).pop((controller.text, choice)),
              ),
              const SizedBox(height: 8),
              StatefulBuilder(
                builder: (context, setDialogState) => RadioGroup<String>(
                  groupValue: choice,
                  onChanged: (v) =>
                      setDialogState(() => choice = v ?? choice),
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        value: 'worker',
                        title: const Text('Connection only'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 0,
                        ),
                      ),
                      RadioListTile<String>(
                        value: 'psiphon',
                        title: const Text('Psiphon'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 0,
                        ),
                      ),
                      RadioListTile<String>(
                        value: 'tor',
                        title: const Text('Tor'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 0,
                        ),
                      ),
                      if (chains.isNotEmpty)
                        for (final chain in chains)
                          RadioListTile<String>(
                            value: 'chain:${chain.id}',
                            title: Text(chain.name),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 0,
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop((controller.text, choice)),
              child: const Text('Add'),
            ),
          ],
        ),
      );
      if (result == null) return;
      final domain = result.$1
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
      setExit(domain, result.$2);
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
              'Choose an exit per domain. Other domains follow the '
              "connection's exit, so only the domains listed here take the "
              'extra hop. One domain also covers its subdomains.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Text(
              'Only one of Psiphon or Tor can run as the extra exit. When '
              'domains use both, Tor runs and the Psiphon domains follow the '
              "connection's exit.",
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
