import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The three possible moods for the parent avatar, driven purely by how the
/// user's monthly spend compares to their budget_threshold.
enum ParentMood {
  neutral, // comfortably under budget
  skeptical, // approaching the threshold (>= 80%)
  furious, // over budget
}

/// Maps a spend ratio (monthlyTotal / budgetThreshold) to a mood.
/// Centralizing this logic means the dashboard, notifications, and any
/// future screen all derive the "how angry is Mom" state the same way.
ParentMood moodForRatio(double ratio) {
  if (ratio >= 1.0) return ParentMood.furious;
  if (ratio >= 0.8) return ParentMood.skeptical;
  return ParentMood.neutral;
}

/// A stern face rendered purely in vector shapes (no external image assets
/// required) so the project runs out-of-the-box. If you'd rather use real
/// illustrated art, drop PNG/SVG files in assets/avatars/ and swap the
/// CustomPaint body below for an Image.asset(_assetForMood(mood)).
class SternAvatar extends StatelessWidget {
  final ParentMood mood;
  final double size;

  const SternAvatar({super.key, required this.mood, this.size = 160});

  // Example of how you'd wire up real art assets instead of CustomPaint:
  // String _assetForMood(ParentMood mood) {
  //   switch (mood) {
  //     case ParentMood.neutral:
  //       return 'assets/avatars/parent_neutral.png';
  //     case ParentMood.skeptical:
  //       return 'assets/avatars/parent_skeptical.png';
  //     case ParentMood.furious:
  //       return 'assets/avatars/parent_furious.png';
  //   }
  // }

  Color get _ringColor {
    switch (mood) {
      case ParentMood.neutral:
        return AppColors.savingsGreen;
      case ParentMood.skeptical:
        return Colors.amber;
      case ParentMood.furious:
        return AppColors.overspendRed;
    }
  }

  String get _caption {
    switch (mood) {
      case ParentMood.neutral:
        return 'Watching...';
      case ParentMood.skeptical:
        return 'Hmm. Suspicious.';
      case ParentMood.furious:
        return 'WHAT DID YOU BUY?!';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _ringColor, width: 4),
            boxShadow: [
              BoxShadow(
                color: _ringColor.withOpacity(0.4),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipOval(
            child: CustomPaint(
              painter: _FacePainter(mood: mood),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            _caption,
            key: ValueKey(mood),
            style: TextStyle(
              color: _ringColor,
              fontWeight: FontWeight.bold,
              fontSize: 16,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// Hand-drawn vector face. Eyebrow angle + mouth curve change with mood so
/// the avatar visibly reacts without needing any image assets.
class _FacePainter extends CustomPainter {
  final ParentMood mood;
  _FacePainter({required this.mood});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final faceRadius = size.width / 2;

    // Face base
    final facePaint = Paint()..color = const Color(0xFFE0B48C);
    canvas.drawCircle(center, faceRadius, facePaint);

    final darkStroke = Paint()
      ..color = Colors.black87
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final eyeY = size.height * 0.42;
    final leftEyeX = size.width * 0.36;
    final rightEyeX = size.width * 0.64;

    // Eyebrows: angle steepens with anger.
    double browTilt;
    switch (mood) {
      case ParentMood.neutral:
        browTilt = 4;
        break;
      case ParentMood.skeptical:
        browTilt = 10;
        break;
      case ParentMood.furious:
        browTilt = 18;
        break;
    }

    canvas.drawLine(
      Offset(leftEyeX - 16, eyeY - 18 - browTilt),
      Offset(leftEyeX + 16, eyeY - 18),
      darkStroke,
    );
    canvas.drawLine(
      Offset(rightEyeX - 16, eyeY - 18),
      Offset(rightEyeX + 16, eyeY - 18 - browTilt),
      darkStroke,
    );

    // Eyes: simple narrowed slits — narrower when angrier.
    final eyeHeight = mood == ParentMood.furious ? 2.5 : 4.0;
    final eyePaint = Paint()..color = Colors.black87;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(leftEyeX, eyeY),
        width: 18,
        height: eyeHeight,
      ),
      eyePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(rightEyeX, eyeY),
        width: 18,
        height: eyeHeight,
      ),
      eyePaint,
    );

    // Mouth: curve flips from a flat skeptical line to a downward frown.
    final mouthPath = Path();
    final mouthY = size.height * 0.68;
    final mouthWidth = size.width * 0.28;
    switch (mood) {
      case ParentMood.neutral:
        // Flat, unimpressed line.
        mouthPath.moveTo(center.dx - mouthWidth, mouthY);
        mouthPath.lineTo(center.dx + mouthWidth, mouthY);
        break;
      case ParentMood.skeptical:
        // Slight frown.
        mouthPath.moveTo(center.dx - mouthWidth, mouthY - 4);
        mouthPath.quadraticBezierTo(
          center.dx,
          mouthY + 6,
          center.dx + mouthWidth,
          mouthY - 4,
        );
        break;
      case ParentMood.furious:
        // Deep scowl.
        mouthPath.moveTo(center.dx - mouthWidth, mouthY - 10);
        mouthPath.quadraticBezierTo(
          center.dx,
          mouthY + 16,
          center.dx + mouthWidth,
          mouthY - 10,
        );
        break;
    }
    canvas.drawPath(mouthPath, darkStroke);
  }

  @override
  bool shouldRepaint(covariant _FacePainter oldDelegate) =>
      oldDelegate.mood != mood;
}
