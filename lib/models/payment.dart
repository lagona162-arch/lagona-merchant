class PaymentReceipt {
  final String id;
  final String deliveryId;
  final String? screenshotUrl;
  final String referenceNumber;
  final String payerName;
  final double amount;
  final DateTime createdAt;
  final PaymentStatus status;

  PaymentReceipt({
    required this.id,
    required this.deliveryId,
    this.screenshotUrl,
    required this.referenceNumber,
    required this.payerName,
    required this.amount,
    required this.createdAt,
    this.status = PaymentStatus.pending,
  });

  factory PaymentReceipt.fromJson(Map<String, dynamic> json) {
    return PaymentReceipt(
      id: json['id'] as String,
      deliveryId: json['delivery_id'] as String,
      screenshotUrl: json['screenshot_url'] as String?,
      referenceNumber: json['reference_number'] as String,
      payerName: json['payer_name'] as String,
      amount: (json['amount'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
      status: PaymentStatusExtension.fromString(
        json['status'] as String? ?? 'pending',
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'delivery_id': deliveryId,
      'screenshot_url': screenshotUrl,
      'reference_number': referenceNumber,
      'payer_name': payerName,
      'amount': amount,
      'created_at': createdAt.toIso8601String(),
      'status': status.value,
    };
  }
}

enum PaymentStatus {
  pending,
  verified,
  rejected,
}

extension PaymentStatusExtension on PaymentStatus {
  String get value {
    switch (this) {
      case PaymentStatus.pending:
        return 'pending';
      case PaymentStatus.verified:
        return 'verified';
      case PaymentStatus.rejected:
        return 'rejected';
    }
  }

  static PaymentStatus fromString(String value) {
    switch (value) {
      case 'pending':
        return PaymentStatus.pending;
      case 'verified':
        return PaymentStatus.verified;
      case 'rejected':
        return PaymentStatus.rejected;
      default:
        return PaymentStatus.pending;
    }
  }
}

