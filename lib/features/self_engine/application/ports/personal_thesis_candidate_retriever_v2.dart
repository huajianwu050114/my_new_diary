import '../../domain/entities/personal_thesis_synthesis_v2.dart';

abstract interface class PersonalThesisCandidateRetrieverV2 {
  Future<PersonalThesisSynthesisRequestV2?> retrieve(String threadId);
}
