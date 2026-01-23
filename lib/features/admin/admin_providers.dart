import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'admin_models.dart';
import 'admin_service.dart';

/// 管理员服务 Provider
final adminServiceProvider = Provider<AdminService>((ref) {
  return AdminService();
});

/// 当前选择的时间范围 Provider
final adminTimeRangeProvider = StateProvider<AdminStatsTimeRange>((ref) {
  return AdminStatsTimeRange.lastWeek;
});

/// 用户统计数据 Provider
final userStatisticsProvider = FutureProvider.autoDispose<UserStatistics>((ref) async {
  final service = ref.watch(adminServiceProvider);
  final timeRange = ref.watch(adminTimeRangeProvider);
  
  return service.getUserStatistics(timeRange: timeRange);
});

/// 系统统计数据 Provider
final systemStatisticsProvider = FutureProvider.autoDispose<SystemStatistics>((ref) async {
  final service = ref.watch(adminServiceProvider);
  final timeRange = ref.watch(adminTimeRangeProvider);
  
  return service.getSystemStatistics(timeRange: timeRange);
});

/// 搜索热词统计 Provider
final searchKeywordStatsProvider = FutureProvider.autoDispose<SearchKeywordStats>((ref) async {
  final service = ref.watch(adminServiceProvider);
  final timeRange = ref.watch(adminTimeRangeProvider);
  
  return service.getSearchKeywordStats(timeRange: timeRange);
});

/// 当前选中的Tab Provider
final adminTabIndexProvider = StateProvider<int>((ref) => 0);

/// 刷新统计数据
void refreshAdminStats(WidgetRef ref) {
  ref.invalidate(userStatisticsProvider);
  ref.invalidate(systemStatisticsProvider);
  ref.invalidate(searchKeywordStatsProvider);
}

/// 数据导出状态
class ExportState {
  final bool isExporting;
  final String? exportedPath;
  final String? error;

  const ExportState({
    this.isExporting = false,
    this.exportedPath,
    this.error,
  });
}

/// 数据导出状态 Provider
final exportStateProvider = StateNotifierProvider<ExportStateNotifier, ExportState>((ref) {
  return ExportStateNotifier(ref.watch(adminServiceProvider));
});

class ExportStateNotifier extends StateNotifier<ExportState> {
  final AdminService _service;

  ExportStateNotifier(this._service) : super(const ExportState());

  Future<void> exportData({
    required String dataType,
    required AdminStatsTimeRange timeRange,
    required String format,
  }) async {
    state = const ExportState(isExporting: true);
    
    try {
      final path = await _service.exportData(
        dataType: dataType,
        timeRange: timeRange,
        format: format,
      );
      state = ExportState(exportedPath: path);
    } catch (e) {
      state = ExportState(error: e.toString());
    }
  }

  void reset() {
    state = const ExportState();
  }
}
