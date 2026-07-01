class PermissionRule {
  final String role;
  final bool read;
  final bool write;
  final bool create;
  final bool delete;
  final bool submit;

  /// Cancel a submitted document. Distinct from [delete] (C5): cancelling a
  /// posted voucher reverses its effects, which is a different authority from
  /// deleting a draft. In fail-closed mode this must be granted explicitly; in
  /// open mode a [delete] grant still covers cancel for back-compat.
  final bool cancel;
  final bool amend;
  final bool matchAll;
  final String? conditionExpression;

  const PermissionRule({
    required this.role,
    this.read = false,
    this.write = false,
    this.create = false,
    this.delete = false,
    this.submit = false,
    this.cancel = false,
    this.amend = false,
    this.matchAll = false,
    this.conditionExpression,
  });

  factory PermissionRule.fromJson(Map<String, dynamic> json) => PermissionRule(
        role: json['role'] as String,
        read: (json['read'] as bool?) ?? false,
        write: (json['write'] as bool?) ?? false,
        create: (json['create'] as bool?) ?? false,
        delete: (json['delete'] as bool?) ?? false,
        submit: (json['submit'] as bool?) ?? false,
        cancel: (json['cancel'] as bool?) ?? false,
        amend: (json['amend'] as bool?) ?? false,
        matchAll: (json['matchAll'] as bool?) ?? false,
        conditionExpression: json['conditionExpression'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'role': role,
        'read': read,
        'write': write,
        'create': create,
        'delete': delete,
        'submit': submit,
        'cancel': cancel,
        'amend': amend,
        'matchAll': matchAll,
        if (conditionExpression != null) 'conditionExpression': conditionExpression,
      };
}
