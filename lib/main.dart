import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/haptics.dart';
import 'widgets/slide_switch.dart';

/// Single [Haptics] instance, shared by the whole app as the Pulsar SDK asks.
final Haptics haptics = Haptics();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Preloads the presets so the first pull of the switch is not late.
  await haptics.init();
  runApp(const BlockSwitchApp());
}

class BlockSwitchApp extends StatelessWidget {
  const BlockSwitchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Block Switch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0D10),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Persisted keys. The real blocked state moves to the platform channel in
  // phase 2; for now it lives here so the switch survives a restart.
  static const String _kBlocked = 'blocked';
  static const String _kResistance = 'dev_resistance';
  static const String _kHapticIntensity = 'dev_haptic_intensity';

  SharedPreferences? _prefs;

  bool _blocked = false;
  double _resistance = 0.6;
  double _hapticIntensity = 1.0;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _blocked = prefs.getBool(_kBlocked) ?? false;
      _resistance = prefs.getDouble(_kResistance) ?? 0.6;
      _hapticIntensity = prefs.getDouble(_kHapticIntensity) ?? 1.0;
      haptics.intensity = _hapticIntensity;
    });
  }

  void _onSwitched(bool blocked) {
    setState(() => _blocked = blocked);
    _prefs?.setBool(_kBlocked, blocked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Spacer(),
              Text(
                _blocked ? 'Instagram is blocked' : 'Instagram is allowed',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _blocked
                    ? 'Pull the switch all the way to let it back in.'
                    : 'Slide across to block it.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Color(0xFF8A919E)),
              ),
              const SizedBox(height: 40),
              SlideSwitch(
                value: _blocked,
                onChanged: _onSwitched,
                haptics: haptics,
                resistance: _resistance,
              ),
              const Spacer(),
              if (kDebugMode) _buildDevPanel(),
            ],
          ),
        ),
      ),
    );
  }

  /// Debug-only tuning controls. Never built in a release build.
  Widget _buildDevPanel() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF14181E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'DEV',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF5B6472),
            ),
          ),
          _devSlider(
            label: 'Resistance',
            value: _resistance,
            onChanged: (v) {
              setState(() => _resistance = v);
              _prefs?.setDouble(_kResistance, v);
            },
          ),
          _devSlider(
            label: 'Haptic intensity',
            value: _hapticIntensity,
            onChanged: (v) {
              setState(() => _hapticIntensity = v);
              haptics.intensity = v;
              _prefs?.setDouble(_kHapticIntensity, v);
            },
          ),
        ],
      ),
    );
  }

  Widget _devSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 118,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF8A919E)),
          ),
        ),
        Expanded(
          child: Slider(value: value, onChanged: onChanged),
        ),
        SizedBox(
          width: 34,
          child: Text(
            value.toStringAsFixed(2),
            style: const TextStyle(
              fontSize: 12,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              color: Color(0xFFB7BFCC),
            ),
          ),
        ),
      ],
    );
  }
}
