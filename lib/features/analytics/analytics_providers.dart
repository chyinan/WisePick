import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'analytics_models.dart';
import 'analytics_service.dart';

/// 数据分析服务 Provider
final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return AnalyticsService();
});

/// 当前选择的时间范围 Provider
final selectedTimeRangeProvider = StateProvider<AnalyticsDateRange>((ref) {
  return AnalyticsDateRange.lastMonth();
});

/// 消费结构分析数据 Provider
final consumptionStructureProvider = FutureProvider.autoDispose<ConsumptionStructure>((ref) async {
  final service = ref.watch(analyticsServiceProvider);
  final timeRange = ref.watch(selectedTimeRangeProvider);
  
  return service.getConsumptionStructure(timeRange: timeRange);
});

/// 用户偏好分析数据 Provider
final userPreferencesProvider = FutureProvider.autoDispose<UserPreferences>((ref) async {
  final service = ref.watch(analyticsServiceProvider);
  
  return service.getUserPreferences();
});

/// 购物时间分析数据 Provider
final shoppingTimeAnalysisProvider = FutureProvider.autoDispose<ShoppingTimeAnalysis>((ref) async {
  final service = ref.watch(analyticsServiceProvider);
  final timeRange = ref.watch(selectedTimeRangeProvider);
  
  return service.getShoppingTimeAnalysis(timeRange: timeRange);
});

/// 购物报告生成 Provider (使用 family 支持不同时间范围)
final shoppingReportProvider = FutureProvider.autoDispose.family<ShoppingReport, AnalyticsDateRange>((ref, timeRange) async {
  final service = ref.watch(analyticsServiceProvider);
  
  return service.generateReport(timeRange: timeRange);
});

/// 报告导出状态 Provider
final reportExportStateProvider = StateNotifierProvider<ReportExportNotifier, ReportExportState>((ref) {
  return ReportExportNotifier(ref.watch(analyticsServiceProvider));
});

/// 报告导出状态
class ReportExportState {
  final bool isExporting;
  final String? exportedFilePath;
  final String? errorMessage;

  const ReportExportState({
    this.isExporting = false,
    this.exportedFilePath,
    this.errorMessage,
  });

  ReportExportState copyWith({
    bool? isExporting,
    String? exportedFilePath,
    String? errorMessage,
  }) {
    return ReportExportState(
      isExporting: isExporting ?? this.isExporting,
      exportedFilePath: exportedFilePath ?? this.exportedFilePath,
      errorMessage: errorMessage,
    );
  }
}

/// 报告导出状态管理器
class ReportExportNotifier extends StateNotifier<ReportExportState> {
  final AnalyticsService _service;

  ReportExportNotifier(this._service) : super(const ReportExportState());

  /// 导出报告为PDF
  Future<void> exportToPdf(ShoppingReport report) async {
    state = state.copyWith(isExporting: true, errorMessage: null);
    
    try {
      final filePath = await _service.exportReportToPdf(report);
      state = state.copyWith(
        isExporting: false,
        exportedFilePath: filePath,
      );
    } catch (e) {
      state = state.copyWith(
        isExporting: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// 重置状态
  void reset() {
    state = const ReportExportState();
  }
}

/// 分析页面当前选中的Tab索引
final analyticsTabIndexProvider = StateProvider<int>((ref) => 0);

/// 图表类型选择 Provider (用于切换不同的图表视图)
enum ChartType { pie, bar, line }

final categoryChartTypeProvider = StateProvider<ChartType>((ref) => ChartType.pie);
final priceRangeChartTypeProvider = StateProvider<ChartType>((ref) => ChartType.bar);

/// 刷新所有分析数据
void refreshAnalyticsData(WidgetRef ref) {
  ref.invalidate(consumptionStructureProvider);
  ref.invalidate(userPreferencesProvider);
  ref.invalidate(shoppingTimeAnalysisProvider);
}
