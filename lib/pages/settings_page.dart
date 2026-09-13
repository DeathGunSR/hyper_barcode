import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_settings_provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = Provider.of<AppSettings>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Language Section
          Card(
            child: ListTile(
              leading: const Icon(Icons.language),
              title: Text(l10n.settingsLanguage),
              subtitle: Text(settings.locale.languageCode == 'fa' ? 'فارسی' : 'English'),
              trailing: DropdownButton<String>(
                value: settings.locale.languageCode,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'fa', child: Text('فارسی')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    settings.setLocale(value);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Theme Section
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.palette),
                  title: Text(l10n.settingsTheme),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      _buildThemeOption(
                        context,
                        icon: Icons.phone_android,
                        title: l10n.themeSystem,
                        value: ThemeMode.system,
                        groupValue: settings.themeMode,
                        onChanged: (mode) => settings.setThemeMode(mode),
                      ),
                      _buildThemeOption(
                        context,
                        icon: Icons.light_mode,
                        title: l10n.themeLight,
                        value: ThemeMode.light,
                        groupValue: settings.themeMode,
                        onChanged: (mode) => settings.setThemeMode(mode),
                      ),
                      _buildThemeOption(
                        context,
                        icon: Icons.dark_mode,
                        title: l10n.themeDark,
                        value: ThemeMode.dark,
                        groupValue: settings.themeMode,
                        onChanged: (mode) => settings.setThemeMode(mode),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // Label Configuration Section
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.label_outline),
                  title: Text(l10n.settingsLabelConfig),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildNumberField(
                        context,
                        label: l10n.labelColumns,
                        value: settings.labelConfig.labelsPerRow,
                        min: 1,
                        max: 10,
                        onChanged: (value) {
                          settings.setLabelConfig(
                            labelsPerRow: value,
                            labelsPerColumn: settings.labelConfig.labelsPerColumn,
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildNumberField(
                        context,
                        label: l10n.labelRows,
                        value: settings.labelConfig.labelsPerColumn,
                        min: 1,
                        max: 10,
                        onChanged: (value) {
                          settings.setLabelConfig(
                            labelsPerRow: settings.labelConfig.labelsPerRow,
                            labelsPerColumn: value,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // About Section
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(l10n.settingsAbout),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Barcodify v1.0.0',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.appDescription,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required ThemeMode value,
    required ThemeMode groupValue,
    required Function(ThemeMode) onChanged,
  }) {
    return RadioListTile<ThemeMode>(
      value: value,
      groupValue: groupValue,
      onChanged: onChanged,
      leading: Icon(icon),
      title: Text(title),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  Widget _buildNumberField(
    BuildContext context, {
    required String label,
    required int value,
    required int min,
    required int max,
    required Function(int) onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Row(
          children: [
            IconButton(
              onPressed: value > min ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            SizedBox(
              width: 40,
              child: Text(
                value.toString(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              onPressed: value < max ? () => onChanged(value + 1) : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      ],
    );
  }
}
