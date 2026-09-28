import '../../domain/entities/personal_thesis_synthesis_v2.dart';

abstract interface class PersonalThesisSynthesizerV2 {
  Future<PersonalThesisSynthesisDecisionV2> synthesize(
    PersonalThesisSynthesisRequestV2 request,
  );
}

class PersonalThesisFormatFailureV2 implements Exception {
  const PersonalThesisFormatFailureV2(this.message);
  final String message;
  @override
  String toString() => 'PersonalThesisFormatFailureV2: $message';
}

class PersonalThesisValidationFailureV2 implements Exception {
  const PersonalThesisValidationFailureV2(this.message);
  final String message;
  @override
  String toString() => 'PersonalThesisValidationFailureV2: $message';
}
