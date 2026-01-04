import 'package:flutter/material.dart';

/// ویجت برای نمایش متن با استایل پیکسلی
class PixelText extends StatelessWidget {
  final String text;
  final double? fontSize;
  final Color? color;
  final FontWeight? fontWeight;
  final TextAlign? textAlign;

  const PixelText(
    this.text, {
    super.key,
    this.fontSize,
    this.color,
    this.fontWeight,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: textAlign,
      style: TextStyle(
        fontSize: fontSize,
        color: color,
        fontWeight: fontWeight,
        fontFamily: 'monospace', // فونت monospace برای استایل پیکسلی
        letterSpacing: 2.0, // فاصله بین حروف برای استایل پیکسلی
        shadows: [
          // سایه پیکسلی
          Shadow(
            offset: const Offset(2, 2),
            blurRadius: 0,
            color: (color ?? Colors.white).withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }
}

/// دکمه پیکسلی
class PixelButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final double? size;

  const PixelButton({
    super.key,
    required this.child,
    this.onTap,
    this.color,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          // حاشیه پیکسلی به جای گرد
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.3),
            width: 3,
          ),
          boxShadow: [
            // سایه پیکسلی
            BoxShadow(
              offset: const Offset(4, 4),
              blurRadius: 0,
              color: Colors.black.withValues(alpha: 0.4),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}
