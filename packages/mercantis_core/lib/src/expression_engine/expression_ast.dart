enum TokenType {
  string_, number_, bool_, null_, identifier,
  lparen, rparen, comma, dot,
  plus, minus, star, slash, percent_,
  eq, neq, lt, lte, gt, gte,
  and_, or_, not_,
  eof,
}

class Token {
  final TokenType type;
  final dynamic value;
  final int offset;
  const Token(this.type, this.value, this.offset);
  @override
  String toString() => 'Token($type, $value)';
}

sealed class ExpressionNode {}

final class LiteralNode extends ExpressionNode {
  final dynamic value;
  LiteralNode(this.value);
}

final class IdentifierNode extends ExpressionNode {
  final String name;
  IdentifierNode(this.name);
}

final class UnaryNode extends ExpressionNode {
  final TokenType operator_;
  final ExpressionNode operand;
  UnaryNode(this.operator_, this.operand);
}

final class BinaryNode extends ExpressionNode {
  final TokenType operator_;
  final ExpressionNode left;
  final ExpressionNode right;
  BinaryNode(this.operator_, this.left, this.right);
}

final class CallNode extends ExpressionNode {
  final String name;
  final List<ExpressionNode> arguments;
  CallNode(this.name, this.arguments);
}

final class MemberNode extends ExpressionNode {
  final ExpressionNode object;
  final String member;
  MemberNode(this.object, this.member);
}
