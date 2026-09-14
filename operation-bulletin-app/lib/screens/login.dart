import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _pin = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _err;

  Future<void> _login() async {
    final pin = _pin.text.trim();
    if (pin.length < 4) {
      setState(() => _err = 'Enter your PIN (at least 4 digits).');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    final err = await context.read<AppState>().login(pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _err = err;
    });
    if (err != null) _pin.selection = TextSelection(baseOffset: 0, extentOffset: _pin.text.length);
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final hint = st.loginHint;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kSeed, Color(0xFF115E59), Color(0xFF134E4A)])),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 92, height: 92,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(26)),
                  child: const Icon(Icons.insights_rounded, color: Colors.white, size: 48),
                ),
                const SizedBox(height: 18),
                const Text('Operation Bulletin', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                const SizedBox(height: 4),
                Text('Star Global · Production Bulletin', style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(22), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 30, offset: const Offset(0, 12))]),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('Enter your PIN', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      hint.isNotEmpty ? '$hint has no access. Use your PIN.' : 'Ask MIS / Management if you don\'t have one.',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _pin,
                      autofocus: true,
                      obscureText: !_show,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 10),
                      onSubmitted: (_) => _login(),
                      decoration: InputDecoration(
                        hintText: '••••',
                        hintStyle: TextStyle(letterSpacing: 10, color: Theme.of(context).colorScheme.outline),
                        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                        suffixIcon: IconButton(icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded), onPressed: () => setState(() => _show = !_show)),
                        errorText: _err,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _login,
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('Login'),
                    ),
                  ]),
                ),
                const SizedBox(height: 22),
                Text('Star Global · MIS', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
