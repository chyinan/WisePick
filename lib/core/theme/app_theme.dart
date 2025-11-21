import 'package:flutter/material.dart';
// import 'package:google_fonts/google_fonts.dart'; // Temporarily disable google_fonts to fix build

class AppTheme {
  static const Color _primaryBrandColor = Color(0xFF2563EB); // Interstellar Blue
  static const Color _secondaryBrandColor = Color(0xFF475569); // Slate
  
  static ThemeData get lightTheme {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: _primaryBrandColor,
      brightness: Brightness.light,
      surface: const Color(0xFFF8FAFC), // Cool gray surface, not pure white
      surfaceContainerLow: Colors.white,
      primary: _primaryBrandColor,
      onPrimary: Colors.white,
      secondary: _secondaryBrandColor,
      error: const Color(0xFFDC2626),
    );

    // Fallback font family
    const String appFontFamily = 'Microsoft YaHei'; 

    final TextTheme textTheme = ThemeData.light().textTheme.apply(
      fontFamily: appFontFamily,
      bodyColor: const Color(0xFF1E293B), // Slate 800
      displayColor: const Color(0xFF0F172A), // Slate 900
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF1F5F9), // Slate 100 background
      textTheme: textTheme,
      fontFamily: appFontFamily,
      
      // AppBar Theme - Minimalist
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: const Color(0xFF0F172A),
          fontSize: 20,
        ),
        iconTheme: const IconThemeData(color: Color(0xFF475569)),
      ),

      // Card Theme
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.withOpacity(0.2), width: 1),
        ),
      ),

      // Button Theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryBrandColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _primaryBrandColor,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          side: const BorderSide(color: _primaryBrandColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),

      // Input Decoration - Clean
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _primaryBrandColor, width: 1.5),
        ),
        hintStyle: TextStyle(color: Colors.grey.withOpacity(0.6)),
      ),

      // Navigation Rail (Sidebar) Theme
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.white,
        selectedIconTheme: IconThemeData(color: _primaryBrandColor),
        unselectedIconTheme: const IconThemeData(color: Color(0xFF94A3B8)),
        selectedLabelTextStyle: TextStyle(
          color: _primaryBrandColor,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: const TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
        labelType: NavigationRailLabelType.all,
        groupAlignment: -0.9, // Top aligned
        indicatorColor: _primaryBrandColor.withOpacity(0.1),
      ),
      
      // Bottom Navigation (Mobile/Tablet fallback)
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: _primaryBrandColor,
        unselectedItemColor: const Color(0xFF94A3B8),
        elevation: 8,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),
      
      dividerTheme: DividerThemeData(
        color: Colors.grey.withOpacity(0.15),
        thickness: 1,
      ),
    );
  }
}
