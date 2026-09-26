/// Version contract for reusable Self Engine computations.
///
/// Any prompt, extractor, or validation semantic change that makes an old
/// computation result invalid must bump [semanticVersion]. Provider/model
/// changes alone do not invalidate an otherwise equivalent computation.
abstract final class SelfEnginePipelineV2 {
  static const semanticVersion = 1;
  static const pipelineVersion = semanticVersion;
  static const extractorVersion = semanticVersion;
  static const promptVersion = semanticVersion;

  // Thread decisions depend on the current graph and are never cached by
  // source hash. Bump this for incompatible linker/prompt semantics.
  static const threadPipelineVersion = 1;
}
