import 'memory_atom_v2.dart';
import 'memory_thread_v2.dart';
import 'thread_membership_v2.dart';

class SelfEngineDerivedResultV2 {
  const SelfEngineDerivedResultV2({
    this.atoms = const [],
    this.threads = const [],
    this.memberships = const [],
  });

  final List<MemoryAtomV2> atoms;
  final List<MemoryThreadV2> threads;
  final List<ThreadMembershipV2> memberships;
}
