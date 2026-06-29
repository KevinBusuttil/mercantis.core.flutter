/// Who is performing an operation, on behalf of which company, with which roles,
/// from which device and session. Propagated into [DocumentEngine] per call so
/// audit, mutation provenance, and permission checks reflect the real operator
/// rather than a single instance-wide identity. Port of Swift `ExecutionContext`.
///
/// Threading is intentionally **additive**: every `DocumentEngine` lifecycle
/// method takes an optional `context:` defaulting to `null`. When `null`, the
/// engine synthesises a [ExecutionContext.legacy] from its constructor identity
/// (carrying the call's `userRoles`), so existing call sites keep their exact
/// behaviour until they opt in.
class ExecutionContext {
  /// The authenticated operator performing the action. Recorded as the audit
  /// `user_id` and the mutation `userId`.
  final String operatorId;

  /// The company the operation is scoped to. Empty = unscoped (single-company).
  final String companyId;

  /// The operator's roles, used by permission and workflow-guard checks.
  final Set<String> roles;

  /// The physical device. Recorded as the mutation `deviceId` and used for
  /// offline-safe numbering. Stable per install, not per session.
  final String deviceId;

  /// The current session (e.g. an unlock session). Empty when not tracked.
  final String sessionId;

  /// `true` for explicit system / import / migration work allowed to bypass
  /// interactive permission gating. Never set implicitly — it must be a
  /// deliberate, auditable choice at the call site.
  final bool isSystemOperation;

  /// `true` only for the synthesised pre-C1 fallback context. It distinguishes
  /// "no operator supplied" (stays permissive via the call's `userRoles`) from
  /// "an explicit operator context that carries no roles", which must NOT bypass
  /// permission checks — an authenticated operator with no granting role is
  /// denied (fail-closed). Callers cannot set this; only [legacy] produces it.
  final bool isLegacyFallback;

  const ExecutionContext({
    required this.operatorId,
    this.companyId = '',
    this.roles = const {},
    required this.deviceId,
    this.sessionId = '',
    this.isSystemOperation = false,
  }) : isLegacyFallback = false;

  const ExecutionContext._({
    required this.operatorId,
    required this.companyId,
    required this.roles,
    required this.deviceId,
    required this.sessionId,
    required this.isSystemOperation,
    required this.isLegacyFallback,
  });

  /// Backward-compatible context synthesised from a [DocumentEngine]'s
  /// constructor identity when a caller does not supply a per-operation context.
  /// Unlike the Swift original it carries the call's [roles] (Flutter passes
  /// `userRoles` as a separate argument), so legacy permission behaviour is
  /// preserved exactly.
  factory ExecutionContext.legacy({
    required String userId,
    required String deviceId,
    Set<String> roles = const {},
  }) =>
      ExecutionContext._(
        operatorId: userId,
        companyId: '',
        roles: roles,
        deviceId: deviceId,
        sessionId: '',
        isSystemOperation: false,
        isLegacyFallback: true,
      );

  /// Explicit system / import context: audit-attributed to [operatorId] (default
  /// `"system"`) and flagged so permission gating can deliberately exempt it.
  factory ExecutionContext.system({
    String operatorId = 'system',
    required String deviceId,
    String companyId = '',
  }) =>
      ExecutionContext(
        operatorId: operatorId,
        companyId: companyId,
        deviceId: deviceId,
        isSystemOperation: true,
      );
}
