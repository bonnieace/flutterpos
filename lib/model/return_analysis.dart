enum ReturnRiskLevel {
  low,
  medium,
  high,
}

extension RiskLevelExtension on ReturnRiskLevel {
  String get displayName {
    switch (this) {
      case ReturnRiskLevel.low:
        return 'Low Risk';
      case ReturnRiskLevel.medium:
        return 'Medium Risk';
      case ReturnRiskLevel.high:
        return 'High Risk';
    }
  }

  int get colorValue {
    switch (this) {
      case ReturnRiskLevel.low:
        return 0xFF4CAF50; // Green
      case ReturnRiskLevel.medium:
        return 0xFFFFC107; // Amber
      case ReturnRiskLevel.high:
        return 0xFFF44336; // Red
    }
  }
}

class ReturnRiskAnalysis {
  final String returnId;
  final int overallRiskScore; // 0-100
  final ReturnRiskLevel riskLevel;
  final List<String> flags; // Specific risk reasons
  final DateTime analysisTimestamp;

  ReturnRiskAnalysis({
    required this.returnId,
    required this.overallRiskScore,
    required this.riskLevel,
    required this.flags,
    required this.analysisTimestamp,
  });

  bool get isFlagged => riskLevel != ReturnRiskLevel.low;

  String get riskSummary {
    if (flags.isEmpty) {
      return 'No suspicious patterns detected';
    }
    return flags.join(', ');
  }

  Map<String, dynamic> toMap() {
    return {
      'returnId': returnId,
      'overallRiskScore': overallRiskScore,
      'riskLevel': riskLevel.toString(),
      'flags': flags,
      'analysisTimestamp': analysisTimestamp.toIso8601String(),
    };
  }
}
