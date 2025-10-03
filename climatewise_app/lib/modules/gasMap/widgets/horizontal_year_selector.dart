import 'package:flutter/material.dart';

class HorizontalYearSelector extends StatefulWidget {
  final int selectedYear;
  final Function(int) onYearSelected;
  final List<int> years;
  final double height;

  const HorizontalYearSelector({
    super.key,
    required this.selectedYear,
    required this.onYearSelected,
    required this.years,
    this.height = 30,
  });

  @override
  _HorizontalYearSelectorState createState() => _HorizontalYearSelectorState();
}

class _HorizontalYearSelectorState extends State<HorizontalYearSelector> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelected();
    });
  }

  @override
  void didUpdateWidget(covariant HorizontalYearSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedYear != widget.selectedYear ||
        oldWidget.years != widget.years) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSelected();
      });
    }
  }

  void _scrollToSelected() {
    if (widget.years.isEmpty) return;
    final index = widget.years.indexOf(widget.selectedYear);
    if (index < 0) return;

    double buttonWidth = 50;
    double spacing = 8;
    double screenWidth = MediaQuery.of(context).size.width;

    double offset = index * (buttonWidth + spacing) - (screenWidth - buttonWidth) / 2;

    if (_scrollController.hasClients) {
      offset = offset.clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: widget.years.isEmpty
          ? const Center(
              child: Text(
                'Loading...',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            )
          : ListView.separated(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              itemCount: widget.years.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final year = widget.years[index];
                final isSelected = year == widget.selectedYear;
                return GestureDetector(
                  onTap: () => widget.onYearSelected(year),
                  child: Container(
                    width: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.black87 : Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.black26),
                    ),
                    child: Text(
                      '$year',
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
