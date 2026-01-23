import 'package:flutter/material.dart';
import '../analytics_models.dart';

/// 用户偏好分析卡片组件
/// 
/// 展示用户购物偏好：品类、价格区间、平台偏好、购物频率等
class PreferencesCard extends StatelessWidget {
  final UserPreferences preferences;

  const PreferencesCard({
    super.key,
    required this.preferences,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 偏好品类
        _buildSection(
          context: context,
          title: '偏好品类',
          icon: Icons.category_outlined,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: preferences.preferredCategories.map((category) {
              return Chip(
                label: Text(
                  category,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                backgroundColor: colorScheme.primaryContainer,
                side: BorderSide.none,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 24),

        // 价格偏好
        _buildSection(
          context: context,
          title: '价格偏好',
          icon: Icons.attach_money,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '¥${preferences.pricePreference.minPrice.toStringAsFixed(0)} - ¥${preferences.pricePreference.maxPrice.toStringAsFixed(0)}',
                style: textTheme.titleMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _buildPriceRangeBar(context),
              const SizedBox(height: 8),
              Text(
                preferences.pricePreference.description,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // 平台偏好
        _buildSection(
          context: context,
          title: '平台偏好',
          icon: Icons.store_outlined,
          child: Row(
            children: preferences.platformRanking.asMap().entries.map((entry) {
              final index = entry.key;
              final platform = entry.value;
              final isFirst = index == 0;

              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: isFirst 
                            ? colorScheme.primary 
                            : colorScheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: textTheme.bodySmall?.copyWith(
                            color: isFirst 
                                ? colorScheme.onPrimary 
                                : colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      platform,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: isFirst ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 24),

        // 购物频率
        _buildSection(
          context: context,
          title: '购物频率',
          icon: Icons.schedule_outlined,
          child: Text(
            preferences.shoppingFrequency,
            style: textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
        ),

        const SizedBox(height: 24),

        // 用户标签
        _buildSection(
          context: context,
          title: '购物画像',
          icon: Icons.person_outline,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: preferences.userTags.map((tag) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: colorScheme.outline),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '#$tag',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSection({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }

  Widget _buildPriceRangeBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    // 计算平均价格在区间内的位置
    final range = preferences.pricePreference.maxPrice - preferences.pricePreference.minPrice;
    final position = range > 0 
        ? (preferences.pricePreference.averagePrice - preferences.pricePreference.minPrice) / range 
        : 0.5;

    return Column(
      children: [
        Container(
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(
              colors: [
                colorScheme.primaryContainer,
                colorScheme.primary,
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Stack(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '¥${preferences.pricePreference.minPrice.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '¥${preferences.pricePreference.maxPrice.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            Positioned(
              left: position * 200, // 简化计算
              child: Column(
                children: [
                  Icon(
                    Icons.arrow_drop_down,
                    color: colorScheme.primary,
                    size: 16,
                  ),
                  Text(
                    '均价',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
