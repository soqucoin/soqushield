import 'package:flutter/material.dart';

/// SoquShield Arrival-Aesthetic color system.
/// Inspired by the muted, desaturated palette of Arrival (2016):
/// misty grays, matte obsidian, glass surfaces, and living-ink accents.
class SoquColors {
  SoquColors._();

  // ── Backgrounds ──
  static const void_ = Color(0xFF0E0F12);          // Deep obsidian
  static const surface = Color(0xFF1A1B20);         // Elevated surface
  static const card = Color(0xFF222329);            // Card panels
  static const cardElevated = Color(0xFF2A2B32);    // Elevated cards

  // ── Status Colors (muted, desaturated) ──
  static const guardian = Color(0xFF94A3B8);       // Slate blue — primary UI
  static const threat = Color(0xFFF87171);         // Muted red — danger
  static const admin = Color(0xFFFBBF24);          // Amber — warnings
  static const grid = Color(0xFF4ADE80);           // Muted green — safe
  static const iso = Color(0xFFF0F2F5);            // Ice — data displays
  static const system = Color(0xFF818CF8);         // Indigo — quests, quantum
  static const corrupted = Color(0xFFFB923C);      // Orange — alerts

  // ── Arrival Tones (replaces neon accents) ──
  static const neonCyan    = Color(0xFF94A3B8);    // Mapped to slate (primary)
  static const neonMagenta = Color(0xFFF87171);    // Mapped to muted red
  static const neonGreen   = Color(0xFF4ADE80);    // Mapped to muted green
  static const neonYellow  = Color(0xFFFBBF24);    // Mapped to amber
  static const neonPurple  = Color(0xFF818CF8);    // Mapped to indigo

  // ── Text (WCAG AA compliant on void_ background) ──
  static const textPrimary = Color(0xFFF0F2F5);    // Near-white
  static const textSecondary = Color(0xFFA3B1C6);  // Readable slate
  static const textMuted = Color(0xFF8895A7);       // Visible muted (5.5:1)

  // ── Glass & Ink ──
  static const glass = Color(0xFFD2D6DE);          // Glass surface text
  static const ice = Color(0xFFF0F2F5);            // Ice — hero emphasis
  static const inkDark = Color(0xFF0D0E10);        // Deep ink
  static const inkMid = Color(0xFF505258);         // Mid-tone ink
  static const fog = Color(0xFF484B54);            // Visible border/divider
  static const stone = Color(0xFF9EA1A9);          // Stone — readable secondary

  // ── Glow effects (subtle, desaturated) ──
  static const guardianGlow = Color(0x2094A3B8);
  static const gridGlow = Color(0x204ADE80);
  static const threatGlow = Color(0x20F87171);
  static const adminGlow = Color(0x20FBBF24);
  static const systemGlow = Color(0x20818CF8);
  static const neonCyanGlow = Color(0x1594A3B8);
  static const neonMagentaGlow = Color(0x15F87171);
  static const neonGreenGlow = Color(0x154ADE80);

  // ── Overlay ──
  static const hexGrid = Color(0x08FFFFFF);        // 3% white subtle pattern

  // ── Semantic aliases ──
  static const safe = grid;                        // Green — success/confirmed
  static const warning = admin;                    // Amber — caution
  static const danger = threat;                    // Red — error/critical
  static const quantum = system;                   // Indigo — quantum/privacy

  // ── Fallout × Arrival Accents ──
  static const pipGreen = Color(0xFF39FF14);       // Terminal glow
  static const vaultAmber = Color(0xFFFFB000);     // Radiation/warning
  static const terminalCyan = Color(0xFF00E5FF);   // Data readouts, scan lines
  static const scanline = Color(0x08FFFFFF);       // CRT scanline (3% white)
}
