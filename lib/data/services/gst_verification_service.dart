class GSTVerificationResult {
  const GSTVerificationResult({
    required this.success,
    required this.gstin,
    required this.message,
    this.legalName,
    this.tradeName,
    this.status,
    this.state,
    this.verifiedAt,
  });

  final bool success;
  final String gstin;
  final String message;
  final String? legalName;
  final String? tradeName;
  final String? status;
  final String? state;
  final DateTime? verifiedAt;
}

abstract interface class GSTVerificationService {
  Future<GSTVerificationResult> verifyGSTIN(String gstin);
}

/// Safe default until a trusted GST verification provider is configured.
class UnconfiguredGSTVerificationService implements GSTVerificationService {
  @override
  Future<GSTVerificationResult> verifyGSTIN(String gstin) async =>
      GSTVerificationResult(
        success: false,
        gstin: gstin,
        message: 'GST verification is not configured. Please try again later.',
      );
}
