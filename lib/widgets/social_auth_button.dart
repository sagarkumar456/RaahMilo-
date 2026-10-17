import 'package:flutter/material.dart';
import '../core/app_colors.dart';

class SocialAuthButton extends StatelessWidget {
  final String label;
  final Widget leading;
  final VoidCallback onTap;

  const SocialAuthButton({
    super.key,
    required this.label,
    required this.leading,
    required this.onTap,
  });

  factory SocialAuthButton.google({required VoidCallback onTap}) {
    return SocialAuthButton(
      label: 'Continue with Google',
      leading: _GoogleLogo(),
      onTap: onTap,
    );
  }

  factory SocialAuthButton.phone({required VoidCallback onTap}) {
    return SocialAuthButton(
      label: 'Continue with Phone',
      leading: const Icon(Icons.phone_iphone_rounded, color: AppColors.textPrimary, size: 20),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 1.2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            leading,
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(
        painter: _GoogleLogoPainter(),
      ),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double stroke = w * 0.22;

    // Red (top)
    final redPaint = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(
      Rect.fromLTWH(stroke / 2, stroke / 2, w - stroke, h - stroke),
      3.14 * 1.15,
      3.14 * 0.7,
      false,
      redPaint,
    );

    // Yellow (left)
    final yellowPaint = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(
      Rect.fromLTWH(stroke / 2, stroke / 2, w - stroke, h - stroke),
      3.14 * 0.75,
      3.14 * 0.45,
      false,
      yellowPaint,
    );

    // Green (bottom)
    final greenPaint = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(
      Rect.fromLTWH(stroke / 2, stroke / 2, w - stroke, h - stroke),
      3.14 * 0.15,
      3.14 * 0.6,
      false,
      greenPaint,
    );

    // Blue (right & crossbar)
    final bluePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(
      Rect.fromLTWH(stroke / 2, stroke / 2, w - stroke, h - stroke),
      -0.3,
      0.6,
      false,
      bluePaint,
    );

    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(w * 0.45, h * 0.38, w * 0.55, stroke),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
