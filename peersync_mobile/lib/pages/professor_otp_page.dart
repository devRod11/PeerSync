import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../theme/app_colors.dart';

class ProfessorOtpPage extends StatefulWidget {
  final VoidCallback onVerified;
  final VoidCallback onSignOut;

  const ProfessorOtpPage({
    super.key,
    required this.onVerified,
    required this.onSignOut,
  });

  @override
  State<ProfessorOtpPage> createState() => _ProfessorOtpPageState();
}

class _ProfessorOtpPageState extends State<ProfessorOtpPage> {
  final TextEditingController _codeController = TextEditingController();

  bool _isRequesting = false;
  bool _isVerifying = false;
  bool _codeRequested = false;

  int _resendSeconds = 0;
  Timer? _resendTimer;

  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _requestCode();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();

    setState(() {
      _resendSeconds = 60;
    });

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_resendSeconds <= 1) {
        timer.cancel();

        setState(() {
          _resendSeconds = 0;
        });
      } else {
        setState(() {
          _resendSeconds--;
        });
      }
    });
  }

  Future<void> _requestCode() async {
    if (_isRequesting || _resendSeconds > 0) return;

    setState(() {
      _isRequesting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await ApiService.requestProfessorOtp();

      if (!mounted) return;

      setState(() {
        _codeRequested = true;
        _successMessage =
            'A verification code has been sent to your registered email.';
      });

      _startResendCooldown();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = _readableError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRequesting = false;
        });
      }
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();

    if (code.length != 6 || !RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _errorMessage = 'Please enter the complete 6-digit verification code.';
        _successMessage = null;
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await ApiService.verifyProfessorOtp(code);

      if (!mounted) return;

      widget.onVerified();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = _readableError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isVerifying = false;
        });
      }
    }
  }

  String _readableError(Object error) {
    if (error is ApiException) {
      return error.message;
    }

    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = _isRequesting || _isVerifying;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A2342),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.verified_user_outlined,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),

                  const SizedBox(height: 28),

                  const Text(
                    'Professor Verification',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 10),

                  const Text(
                    'An additional verification step is required '
                    'before you can access the Professor workspace. '
                    'Enter the 6-digit code sent to your registered email.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 30),

                  const Text(
                    'Verification code',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 9),

                  TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    enabled: !isBusy && _codeRequested,
                    maxLength: 6,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    onSubmitted: (_) {
                      if (!isBusy && _codeRequested) {
                        _verifyCode();
                      }
                    },
                    decoration: const InputDecoration(
                      hintText: 'Enter 6-digit code',
                      counterText: '',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),

                  const SizedBox(height: 18),

                  if (_errorMessage != null) ...[
                    _MessagePanel(message: _errorMessage!, isError: true),
                    const SizedBox(height: 14),
                  ],

                  if (_successMessage != null) ...[
                    _MessagePanel(message: _successMessage!, isError: false),
                    const SizedBox(height: 14),
                  ],

                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: isBusy || !_codeRequested ? null : _verifyCode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A2342),
                        foregroundColor: Colors.white,
                      ),
                      child: _isVerifying
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Verify and continue'),
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextButton(
                    onPressed: isBusy || _resendSeconds > 0
                        ? null
                        : _requestCode,
                    child: Text(
                      _isRequesting
                          ? 'Sending verification code...'
                          : _resendSeconds > 0
                          ? 'Resend code in ${_resendSeconds}s'
                          : 'Resend verification code',
                    ),
                  ),

                  const SizedBox(height: 22),

                  const Divider(),

                  TextButton.icon(
                    onPressed: isBusy ? null : widget.onSignOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessagePanel extends StatelessWidget {
  final String message;
  final bool isError;

  const _MessagePanel({required this.message, required this.isError});

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppColors.danger : AppColors.success;

    final background = isError
        ? AppColors.dangerSurface
        : AppColors.successSurface;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: color,
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
