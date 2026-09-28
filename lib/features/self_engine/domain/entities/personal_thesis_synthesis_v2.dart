// ignore_for_file: prefer_initializing_formals

import 'memory_thread_link_v2.dart';
import 'memory_thread_v2.dart';
import 'personal_thesis_v2.dart';

class PersonalThesisSynthesisRequestV2 {
  const PersonalThesisSynthesisRequestV2({
    required this.thread,
    required this.supportCandidates,
    required this.counterCandidates,
    required this.threadDerivationAtomIds,
  });

  final MemoryThreadV2 thread;
  final List<ThreadAtomEvidenceV2> supportCandidates;
  final List<ThreadAtomEvidenceV2> counterCandidates;
  final List<String> threadDerivationAtomIds;
}

enum PersonalThesisSynthesisActionV2 { none, create }

class PersonalThesisSynthesisDecisionV2 {
  const PersonalThesisSynthesisDecisionV2.none()
    : action = PersonalThesisSynthesisActionV2.none,
      statement = null,
      rationale = null,
      maturity = null,
      supportAtomIds = const [],
      counterAtomIds = const [];

  const PersonalThesisSynthesisDecisionV2.create({
    required String statement,
    required String rationale,
    required PersonalThesisMaturityV2 maturity,
    required List<String> supportAtomIds,
    required List<String> counterAtomIds,
  }) : action = PersonalThesisSynthesisActionV2.create,
       statement = statement,
       rationale = rationale,
       maturity = maturity,
       supportAtomIds = supportAtomIds,
       counterAtomIds = counterAtomIds;

  final PersonalThesisSynthesisActionV2 action;
  final String? statement;
  final String? rationale;
  final PersonalThesisMaturityV2? maturity;
  final List<String> supportAtomIds;
  final List<String> counterAtomIds;
}

class PersonalThesisPublishV2 {
  const PersonalThesisPublishV2.none()
    : decision = const PersonalThesisSynthesisDecisionV2.none(),
      derivationAtomIds = const [];

  const PersonalThesisPublishV2.create({
    required PersonalThesisSynthesisDecisionV2 decision,
    required List<String> derivationAtomIds,
  }) : decision = decision,
       derivationAtomIds = derivationAtomIds;

  final PersonalThesisSynthesisDecisionV2 decision;
  final List<String> derivationAtomIds;
}
