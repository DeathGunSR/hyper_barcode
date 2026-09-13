import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class LabelConfig {
  int labelsPerRow;
  int labelsPerColumn;
  double labelWidthMm;
  double labelHeightMm;
  double marginTopMm;
  double marginBottomMm;
  double marginLeftMm;
  double marginRightMm;
  double gapHorizontalMm;
  double gapVerticalMm;

  LabelConfig({
    this.labelsPerRow = 3,
    this.labelsPerColumn = 5,
    this.labelWidthMm = 70,
    this.labelHeightMm = 42,
    this.marginTopMm = 10,
    this.marginBottomMm = 10,
    this.marginLeftMm = 5,
    this.marginRightMm = 5,
    this.gapHorizontalMm = 5,
    this.gapVerticalMm = 5,
  });

  int get labelsPerPage => labelsPerRow * labelsPerColumn;

  Map<String, dynamic> toJson() {
    return {
      'labelsPerRow': labelsPerRow,
      'labelsPerColumn': labelsPerColumn,
      'labelWidthMm': labelWidthMm,
      'labelHeightMm': labelHeightMm,
      'marginTopMm': marginTopMm,
      'marginBottomMm': marginBottomMm,
      'marginLeftMm': marginLeftMm,
      'marginRightMm': marginRightMm,
      'gapHorizontalMm': gapHorizontalMm,
      'gapVerticalMm': gapVerticalMm,
    };
  }

  factory LabelConfig.fromJson(Map<String, dynamic> json) {
    return LabelConfig(
      labelsPerRow: json['labelsPerRow'] ?? 3,
      labelsPerColumn: json['labelsPerColumn'] ?? 5,
      labelWidthMm: (json['labelWidthMm'] ?? 70).toDouble(),
      labelHeightMm: (json['labelHeightMm'] ?? 42).toDouble(),
      marginTopMm: (json['marginTopMm'] ?? 10).toDouble(),
      marginBottomMm: (json['marginBottomMm'] ?? 10).toDouble(),
      marginLeftMm: (json['marginLeftMm'] ?? 5).toDouble(),
      marginRightMm: (json['marginRightMm'] ?? 5).toDouble(),
      gapHorizontalMm: (json['gapHorizontalMm'] ?? 5).toDouble(),
      gapVerticalMm: (json['gapVerticalMm'] ?? 5).toDouble(),
    );
  }
}

class AppSettings extends ChangeNotifier {
  final SharedPreferences prefs;
  
  Locale _locale = const Locale('fa', 'IR');
  ThemeMode _themeMode = ThemeMode.system;
  LabelConfig _labelConfig = LabelConfig();

  AppSettings(this.prefs);

  Locale get locale => _locale;
  ThemeMode get themeMode => _themeMode;
  LabelConfig get labelConfig => _labelConfig;

  Future<void> loadSettings() async {
    // Load locale
    final localeCode = prefs.getString('locale') ?? 'fa';
    _locale = Locale(localeCode, localeCode == 'fa' ? 'IR' : 'US');
    
    // Load theme mode
    final themeIndex = prefs.getInt('theme_mode') ?? 0;
    _themeMode = ThemeMode.values[themeIndex];
    
    // Load label config
    final labelConfigJson = prefs.getString('label_config');
    if (labelConfigJson != null) {
      try {
        final json = jsonDecode(labelConfigJson) as Map<String, dynamic>;
        _labelConfig = LabelConfig.fromJson(json);
      } catch (e) {
        debugPrint('Error loading label config: $e');
        _labelConfig = LabelConfig();
      }
    }
    
    notifyListeners();
  }

  Future<void> setLocale(String languageCode) async {
    _locale = Locale(languageCode, languageCode == 'fa' ? 'IR' : 'US');
    await prefs.setString('locale', languageCode);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await prefs.setInt('theme_mode', mode.index);
    notifyListeners();
  }

  Future<void> setLabelConfig({
    int? labelsPerRow,
    int? labelsPerColumn,
    double? labelWidthMm,
    double? labelHeightMm,
  }) async {
    if (labelsPerRow != null) _labelConfig.labelsPerRow = labelsPerRow;
    if (labelsPerColumn != null) _labelConfig.labelsPerColumn = labelsPerColumn;
    if (labelWidthMm != null) _labelConfig.labelWidthMm = labelWidthMm;
    if (labelHeightMm != null) _labelConfig.labelHeightMm = labelHeightMm;
    
    await prefs.setString('label_config', jsonEncode(_labelConfig.toJson()));
    notifyListeners();
  }
}
