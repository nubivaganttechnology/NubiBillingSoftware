import '../../core/errors/app_exception.dart';

/// Structured error item produced by repository product validation.
class ProductValidationError {
  const ProductValidationError({
    required this.code,
    required this.message,
    this.field,
    this.attributeId,
    this.variantIdOrIndex,
  });

  final String code;
  final String message;
  final String? field;
  final String? attributeId;
  final dynamic variantIdOrIndex;

  @override
  String toString() =>
      '[$code] ${field != null ? 'Field: $field - ' : ''}${attributeId != null ? 'Attr: $attributeId - ' : ''}$message';

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        if (field != null) 'field': field,
        if (attributeId != null) 'attributeId': attributeId,
        if (variantIdOrIndex != null) 'variantIdOrIndex': variantIdOrIndex,
      };
}

/// Structured validation result returned by repository safety layer.
class ProductValidationResult {
  const ProductValidationResult({
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
  });

  final bool isValid;
  final List<ProductValidationError> errors;
  final List<String> warnings;

  factory ProductValidationResult.success([List<String> warnings = const []]) =>
      ProductValidationResult(isValid: true, warnings: warnings);

  factory ProductValidationResult.failure(
    List<ProductValidationError> errors, [
    List<String> warnings = const [],
  ]) =>
      ProductValidationResult(isValid: false, errors: errors, warnings: warnings);
}

/// Structured exception thrown when repository validation fails.
class ProductValidationException extends AppException {
  ProductValidationException(this.result)
      : super(
          result.errors.isNotEmpty
              ? result.errors.map((e) => e.message).join('; ')
              : 'Product validation failed.',
          code: result.errors.isNotEmpty ? result.errors.first.code : 'validation-failed',
        );

  final ProductValidationResult result;

  @override
  String toString() =>
      'ProductValidationException(${result.errors.map((e) => e.toString()).join('; ')})';
}
