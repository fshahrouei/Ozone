// lib/modules/healthAdvisor/widgets/tabs/health_saved_tab.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/health_advisor_controller.dart';
import '../../models/health_result_summary.dart';
import '../health_saved_card.dart';
import '../forecast_now_bridge.dart';

class HealthSavedTab extends StatefulWidget {
  const HealthSavedTab({super.key});

  @override
  State<HealthSavedTab> createState() => _HealthSavedTabState();
}

class _HealthSavedTabState extends State<HealthSavedTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<HealthAdvisorController>().fetchSavedPoints();
    });
  }

  Future<void> _refresh(HealthAdvisorController ctrl) async {
    await ctrl.fetchSavedPoints(
      search: ctrl.lastSearch,
      hasLocation: ctrl.lastHasLocation,
      sort: ctrl.appliedSort,
      page: 1,
      perPage: ctrl.perPage,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<HealthAdvisorController>(
      builder: (context, ctrl, _) {
        final items = ctrl.items;

        return Scaffold(
          backgroundColor: const Color(0xFFE3F2FD),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () => _refresh(ctrl),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                itemCount: _effectiveCount(items.length, ctrl),
                itemBuilder: (context, index) {
                  if (ctrl.isFetchingList && items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (ctrl.errorMessage != null && items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          ctrl.errorMessage!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  if (!ctrl.isFetchingList && items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('No saved records yet')),
                    );
                  }

                  final HealthResultSummary item = items[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: HealthSavedCard(
                      item: item,
                      isDeleting: ctrl.isDeleting,
                      onForecastNow: () {
                        final lat = item.location.lat;
                        final lon = item.location.lon;
                        if (lat == null || lon == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('No coordinates for this record')),
                          );
                          return;
                        }
                        ForecastNowBridge.open(
                          context,
                          lat: double.parse(lat.toStringAsFixed(4)),
                          lon: double.parse(lon.toStringAsFixed(4)),
                          tHours: 0,
                        );
                      },
                      onConfirmAndDelete: () async {
                        final ok = await ctrl.deleteSavedPoint(item.id ?? -1);
                        if (!ok && ctrl.errorMessage != null && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(ctrl.errorMessage!)),
                          );
                        }
                        return ok;
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  int _effectiveCount(int itemsLen, HealthAdvisorController ctrl) {
    if (ctrl.isFetchingList && itemsLen == 0) return 1;
    if (ctrl.errorMessage != null && itemsLen == 0) return 1;
    if (!ctrl.isFetchingList && itemsLen == 0) return 1;
    return itemsLen;
  }
}
