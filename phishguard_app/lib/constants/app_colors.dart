import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFFF3F6FC);
  static const card = Color(0xFFFFFFFF);
  static const border = Color(0xFFE5EAF3);
  static const rowLine = Color(0xFFEDF1F6);
  static const ink = Color(0xFF152238);
  static const body = Color(0xFF344256);
  static const muted = Color(0xFF68778D);
  static const inputBorder = Color(0xFFD5DEEA);
  static const primary = Color(0xFF3157D5);
  static const navy = Color(0xFF101B36);
  static const blueSoft = Color(0xFFEAF0FF);
  static const legitBar = Color.fromARGB(255, 3, 255, 171);
  static const phishBar = Color.fromARGB(255, 255, 1, 1);
  static const zoneSafe = Color(0xFFCFEBDD);
  static const zoneWarn = Color(0xFFF6D98F);
  static const zonePhish = Color(0xFFF2B8B2);
  static const errorFg = Color(0xFFA3231B);
  static const errorBg = Color(0xFFFDE8E6);
}

TextStyle mono(double size, {FontWeight? weight, Color? color}) => TextStyle(
      fontFamily: 'monospace',
      fontSize: size,
      fontWeight: weight,
      color: color ?? AppColors.ink,
      height: 1.5,
    );