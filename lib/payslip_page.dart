import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme.dart';

class PaySlipPage extends StatelessWidget {
  const PaySlipPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final username = user?.email?.split('@').first ?? '';

    return Container(
      color: AppTheme.background,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('payslips')
            .where('username', isEqualTo: username)
            .orderBy('issuedDate', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _emptyState();
          }

          final docs = snapshot.data!.docs;
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              return _buildPayslipCard(context, data);
            },
          );
        },
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primarySoft, AppTheme.primaryLight],
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.receipt_long,
              size: 44,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No payslips yet',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Your monthly payslips will appear here',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayslipCard(BuildContext context, Map<String, dynamic> data) {
    final basicSalary = (data['basicSalary'] ?? 0).toDouble();
    final allowance = (data['allowance'] ?? 0).toDouble();
    final kpiBonus = (data['kpiBonus'] ?? 0).toDouble();
    final otHours = (data['otHours'] ?? 0).toDouble();
    final otAmount = (data['otAmount'] ?? 0).toDouble();
    final socialSecurity = (data['socialSecurity'] ?? 0).toDouble();
    final leaveDeduction = (data['leaveDeduction'] ?? 0).toDouble();
    final lateMinutes = (data['lateMinutes'] ?? 0).toDouble();
    final lateAmount = (data['lateAmount'] ?? 0).toDouble();
    final netSalary = (data['netSalary'] ?? 0).toDouble();

    final totalEarnings = basicSalary + allowance + kpiBonus + otAmount;
    final totalDeductions = socialSecurity + leaveDeduction + lateAmount;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border, width: 0.5),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — gradient
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            decoration: const BoxDecoration(
              gradient: AppTheme.heroGradient,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                    ),
                  ),
                  child: const Icon(
                    Icons.receipt_long,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['month'] ?? '-',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        data['displayName'] ?? '',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle,
                          size: 12, color: Color(0xFF10B981)),
                      SizedBox(width: 4),
                      Text(
                        'PAID',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF047857),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Net salary big
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            decoration: const BoxDecoration(
              color: AppTheme.primarySurface,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'NET SALARY',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Take home',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
                Text(
                  '฿ ${_formatNumber(netSalary)}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Earnings
                _miniLabel('EARNINGS', AppTheme.greenIcon),
                const SizedBox(height: 10),
                _row('Basic Salary', basicSalary, false),
                _row('Allowance', allowance, false),
                _row('KPI Bonus', kpiBonus, false),
                _row(
                  'Over Time${otHours > 0 ? " (${_formatHours(otHours)} hrs)" : ""}',
                  otAmount,
                  false,
                ),
                _subtotal('Total Earnings', totalEarnings,
                    AppTheme.greenIcon),
                const SizedBox(height: 20),
                // Deductions
                _miniLabel('DEDUCTIONS', const Color(0xFFDC2626)),
                const SizedBox(height: 10),
                _row('Social Security', socialSecurity, true),
                _row('Leave', leaveDeduction, true),
                _row(
                  'Late Minutes${lateMinutes > 0 ? " (${lateMinutes.toStringAsFixed(0)} min)" : ""}',
                  lateAmount,
                  true,
                ),
                _subtotal('Total Deductions', totalDeductions,
                    const Color(0xFFDC2626)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniLabel(String text, Color color) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _row(String label, double value, bool isDeduction) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Text(
            '${isDeduction && value > 0 ? "- " : ""}฿ ${_formatNumber(value)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDeduction && value > 0
                  ? const Color(0xFFDC2626)
                  : AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _subtotal(String label, double value, Color color) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.only(top: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          Text(
            '฿ ${_formatNumber(value)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _formatHours(double h) =>
      h % 1 == 0 ? h.toStringAsFixed(0) : h.toStringAsFixed(1);

  String _formatNumber(double value) {
    final isNegative = value < 0;
    final absValue = value.abs();
    final formatted = absValue.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (match) => '${match[1]},',
        );
    return isNegative ? '-$formatted' : formatted;
  }
}