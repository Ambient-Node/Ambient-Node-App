import 'dart:io';
import 'package:flutter/material.dart';

class AppTopBar extends StatelessWidget {
  final String deviceName;
  final String subtitle;
  final bool connected;
  final VoidCallback onConnectToggle;
  final String? userImagePath;

  const AppTopBar({
    super.key,
    required this.deviceName,
    required this.subtitle,
    required this.connected,
    required this.onConnectToggle,
    this.userImagePath,
  });

  // Nature Theme Colors
  static const Color _textDark = Color(0xFF2D3142);
  static const Color _textGrey = Color(0xFF9095A5);
  static const Color _activeGreen = Color(0xFF4CAF50); // Nature Green
  static const Color _bgGreen = Color(0xFFE8F5E9);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 1. Profile & Info
          Expanded(
            child: Row(
              children: [
                _buildProfileAvatar(),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        deviceName,
                        style: const TextStyle(
                          color: _textDark,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Sen',
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: _textGrey,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Sen',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. Connection Status Chip (Nature Style)
          const SizedBox(width: 12),
          _buildConnectionChip(),
        ],
      ),
    );
  }

  Widget _buildProfileAvatar() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: userImagePath != null
            ? Image.file(
          File(userImagePath!),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildDefaultAvatar(),
        )
            : _buildDefaultAvatar(),
      ),
    );
  }

  Widget _buildDefaultAvatar() {
    return const Center(
      child: Icon(Icons.spa_rounded, color: _activeGreen, size: 24), // 나뭇잎 아이콘
    );
  }

  Widget _buildConnectionChip() {
    return GestureDetector(
      onTap: onConnectToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: connected ? _bgGreen : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: connected ? _activeGreen.withOpacity(0.3) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: connected ? _activeGreen : Colors.grey.shade400,
                boxShadow: connected
                    ? [BoxShadow(color: _activeGreen.withOpacity(0.5), blurRadius: 6)]
                    : [],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              connected ? "Online" : "Offline",
              style: TextStyle(
                fontFamily: 'Sen',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: connected ? _textDark : _textGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}