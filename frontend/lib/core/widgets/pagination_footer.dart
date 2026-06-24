import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PaginationFooter extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final int totalItems;
  final int pageSize;
  final ValueChanged<int> onPageChanged;
  final bool isLoading;

  const PaginationFooter({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
    required this.pageSize,
    required this.onPageChanged,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final startItem = ((currentPage - 1) * pageSize) + 1;
    final endItem = (currentPage * pageSize).clamp(0, totalItems);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Text(
            totalItems > 0
                ? 'Showing $startItem–$endItem of $totalItems'
                : 'No items',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          if (isLoading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Row(
              children: [
                _PageButton(
                  icon: Icons.first_page,
                  onPressed: currentPage > 1 ? () => onPageChanged(1) : null,
                ),
                _PageButton(
                  icon: Icons.chevron_left,
                  onPressed: currentPage > 1
                      ? () => onPageChanged(currentPage - 1)
                      : null,
                ),
                ...buildPageNumbers(),
                _PageButton(
                  icon: Icons.chevron_right,
                  onPressed: currentPage < totalPages
                      ? () => onPageChanged(currentPage + 1)
                      : null,
                ),
                _PageButton(
                  icon: Icons.last_page,
                  onPressed: currentPage < totalPages
                      ? () => onPageChanged(totalPages)
                      : null,
                ),
              ],
            ),
        ],
      ),
    );
  }

  List<Widget> buildPageNumbers() {
    final pages = <Widget>[];
    final start = (currentPage - 2).clamp(1, totalPages);
    final end = (currentPage + 2).clamp(1, totalPages);

    for (int i = start; i <= end; i++) {
      pages.add(_PageNumberButton(
        page: i,
        isActive: i == currentPage,
        onPressed: () => onPageChanged(i),
      ));
    }
    return pages;
  }
}

class _PageButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _PageButton({required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      onPressed: onPressed,
      color: onPressed != null ? AppColors.primary : AppColors.textDisabled,
      splashRadius: 20,
    );
  }
}

class _PageNumberButton extends StatelessWidget {
  final int page;
  final bool isActive;
  final VoidCallback onPressed;

  const _PageNumberButton({
    required this.page,
    required this.isActive,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isActive
              ? null
              : Border.all(color: AppColors.border),
        ),
        child: Center(
          child: Text(
            '$page',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isActive ? AppColors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
