import 'expression_ast.dart';

class ExpressionParseError implements Exception {
  final String message;
  final int offset;
  const ExpressionParseError(this.message, this.offset);
  @override
  String toString() => 'ExpressionParseError at $offset: $message';
}

class Lexer {
  final String _source;
  int _pos = 0;
  final List<Token> _tokens = [];

  Lexer(this._source);

  List<Token> tokenize() {
    while (_pos < _source.length) {
      _skipWhitespace();
      if (_pos >= _source.length) break;
      final ch = _source[_pos];

      if (ch == '"' || ch == "'") {
        _readString(ch);
      } else if (_isDigit(ch) || (ch == '-' && _pos + 1 < _source.length && _isDigit(_source[_pos + 1]) && _tokens.isNotEmpty && _isUnaryContext())) {
        _readNumber();
      } else if (_isAlpha(ch) || ch == '_') {
        _readIdentifierOrKeyword();
      } else {
        _readSymbol();
      }
    }
    _tokens.add(Token(TokenType.eof, null, _pos));
    return _tokens;
  }

  bool _isUnaryContext() {
    if (_tokens.isEmpty) return true;
    final last = _tokens.last.type;
    return last == TokenType.lparen || last == TokenType.comma ||
        last == TokenType.eq || last == TokenType.neq ||
        last == TokenType.lt || last == TokenType.lte ||
        last == TokenType.gt || last == TokenType.gte ||
        last == TokenType.and_ || last == TokenType.or_ ||
        last == TokenType.not_;
  }

  void _skipWhitespace() {
    while (_pos < _source.length && _source[_pos].trim().isEmpty) {
      _pos++;
    }
  }

  bool _isDigit(String ch) => ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;
  bool _isAlpha(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
  }

  void _readString(String quote) {
    final start = _pos;
    _pos++; // skip opening quote
    final buf = StringBuffer();
    while (_pos < _source.length && _source[_pos] != quote) {
      if (_source[_pos] == '\\' && _pos + 1 < _source.length) {
        _pos++;
        switch (_source[_pos]) {
          case 'n': buf.write('\n');
          case 't': buf.write('\t');
          case 'r': buf.write('\r');
          default: buf.write(_source[_pos]);
        }
      } else {
        buf.write(_source[_pos]);
      }
      _pos++;
    }
    _pos++; // skip closing quote
    _tokens.add(Token(TokenType.string_, buf.toString(), start));
  }

  void _readNumber() {
    final start = _pos;
    if (_source[_pos] == '-') _pos++;
    while (_pos < _source.length && _isDigit(_source[_pos])) {
      _pos++;
    }
    if (_pos < _source.length && _source[_pos] == '.') {
      _pos++;
      while (_pos < _source.length && _isDigit(_source[_pos])) {
        _pos++;
      }
    }
    final numStr = _source.substring(start, _pos);
    _tokens.add(Token(TokenType.number_, num.parse(numStr), start));
  }

  void _readIdentifierOrKeyword() {
    final start = _pos;
    while (_pos < _source.length &&
        (_isAlpha(_source[_pos]) || _isDigit(_source[_pos]) || _source[_pos] == '_' || _source[_pos] == '.')) {
      _pos++;
    }
    final word = _source.substring(start, _pos);
    switch (word) {
      case 'true': _tokens.add(Token(TokenType.bool_, true, start));
      case 'false': _tokens.add(Token(TokenType.bool_, false, start));
      case 'null': _tokens.add(Token(TokenType.null_, null, start));
      case 'and': case '&&': _tokens.add(Token(TokenType.and_, null, start));
      case 'or': case '||': _tokens.add(Token(TokenType.or_, null, start));
      case 'not': case '!': _tokens.add(Token(TokenType.not_, null, start));
      default: _tokens.add(Token(TokenType.identifier, word, start));
    }
  }

  void _readSymbol() {
    final start = _pos;
    final ch = _source[_pos];
    switch (ch) {
      case '(':
        _tokens.add(Token(TokenType.lparen, null, start)); _pos++;
      case ')':
        _tokens.add(Token(TokenType.rparen, null, start)); _pos++;
      case ',':
        _tokens.add(Token(TokenType.comma, null, start)); _pos++;
      case '+':
        _tokens.add(Token(TokenType.plus, null, start)); _pos++;
      case '-':
        _tokens.add(Token(TokenType.minus, null, start)); _pos++;
      case '*':
        _tokens.add(Token(TokenType.star, null, start)); _pos++;
      case '/':
        _tokens.add(Token(TokenType.slash, null, start)); _pos++;
      case '%':
        _tokens.add(Token(TokenType.percent_, null, start)); _pos++;
      case '!':
        if (_pos + 1 < _source.length && _source[_pos + 1] == '=') {
          _tokens.add(Token(TokenType.neq, null, start)); _pos += 2;
        } else {
          _tokens.add(Token(TokenType.not_, null, start)); _pos++;
        }
      case '=':
        if (_pos + 1 < _source.length && _source[_pos + 1] == '=') {
          _tokens.add(Token(TokenType.eq, null, start)); _pos += 2;
        } else {
          _tokens.add(Token(TokenType.eq, null, start)); _pos++;
        }
      case '<':
        if (_pos + 1 < _source.length && _source[_pos + 1] == '=') {
          _tokens.add(Token(TokenType.lte, null, start)); _pos += 2;
        } else {
          _tokens.add(Token(TokenType.lt, null, start)); _pos++;
        }
      case '>':
        if (_pos + 1 < _source.length && _source[_pos + 1] == '=') {
          _tokens.add(Token(TokenType.gte, null, start)); _pos += 2;
        } else {
          _tokens.add(Token(TokenType.gt, null, start)); _pos++;
        }
      case '&':
        if (_pos + 1 < _source.length && _source[_pos + 1] == '&') {
          _tokens.add(Token(TokenType.and_, null, start)); _pos += 2;
        } else {
          _pos++;
        }
      case '|':
        if (_pos + 1 < _source.length && _source[_pos + 1] == '|') {
          _tokens.add(Token(TokenType.or_, null, start)); _pos += 2;
        } else {
          _pos++;
        }
      default:
        _pos++; // skip unknown
    }
  }
}

class ExpressionParser {
  final List<Token> _tokens;
  int _pos = 0;

  ExpressionParser(this._tokens);

  factory ExpressionParser.fromSource(String source) {
    final tokens = Lexer(source).tokenize();
    return ExpressionParser(tokens);
  }

  ExpressionNode parse() {
    final node = _parseOr();
    if (_current.type != TokenType.eof) {
      throw ExpressionParseError('Unexpected token: ${_current.value}', _current.offset);
    }
    return node;
  }

  Token get _current => _tokens[_pos];
  Token _consume() => _tokens[_pos++];

  ExpressionNode _parseOr() {
    var left = _parseAnd();
    while (_current.type == TokenType.or_) {
      _consume();
      final right = _parseAnd();
      left = BinaryNode(TokenType.or_, left, right);
    }
    return left;
  }

  ExpressionNode _parseAnd() {
    var left = _parseEquality();
    while (_current.type == TokenType.and_) {
      _consume();
      final right = _parseEquality();
      left = BinaryNode(TokenType.and_, left, right);
    }
    return left;
  }

  ExpressionNode _parseEquality() {
    var left = _parseComparison();
    while (_current.type == TokenType.eq || _current.type == TokenType.neq) {
      final op = _consume().type;
      final right = _parseComparison();
      left = BinaryNode(op, left, right);
    }
    return left;
  }

  ExpressionNode _parseComparison() {
    var left = _parseAdditive();
    while (_current.type == TokenType.lt ||
        _current.type == TokenType.lte ||
        _current.type == TokenType.gt ||
        _current.type == TokenType.gte) {
      final op = _consume().type;
      final right = _parseAdditive();
      left = BinaryNode(op, left, right);
    }
    return left;
  }

  ExpressionNode _parseAdditive() {
    var left = _parseMultiplicative();
    while (_current.type == TokenType.plus || _current.type == TokenType.minus) {
      final op = _consume().type;
      final right = _parseMultiplicative();
      left = BinaryNode(op, left, right);
    }
    return left;
  }

  ExpressionNode _parseMultiplicative() {
    var left = _parseUnary();
    while (_current.type == TokenType.star ||
        _current.type == TokenType.slash ||
        _current.type == TokenType.percent_) {
      final op = _consume().type;
      final right = _parseUnary();
      left = BinaryNode(op, left, right);
    }
    return left;
  }

  ExpressionNode _parseUnary() {
    if (_current.type == TokenType.not_) {
      _consume();
      return UnaryNode(TokenType.not_, _parseUnary());
    }
    if (_current.type == TokenType.minus) {
      _consume();
      return UnaryNode(TokenType.minus, _parseUnary());
    }
    return _parsePrimary();
  }

  ExpressionNode _parsePrimary() {
    final tok = _current;
    switch (tok.type) {
      case TokenType.number_:
        _consume();
        return LiteralNode(tok.value);
      case TokenType.string_:
        _consume();
        return LiteralNode(tok.value);
      case TokenType.bool_:
        _consume();
        return LiteralNode(tok.value);
      case TokenType.null_:
        _consume();
        return LiteralNode(null);
      case TokenType.identifier:
        _consume();
        final name = tok.value as String;
        if (_current.type == TokenType.lparen) {
          _consume(); // (
          final args = <ExpressionNode>[];
          while (_current.type != TokenType.rparen &&
              _current.type != TokenType.eof) {
            args.add(_parseOr());
            if (_current.type == TokenType.comma) _consume();
          }
          if (_current.type != TokenType.rparen) {
            throw ExpressionParseError('Expected )', _current.offset);
          }
          _consume(); // )
          return CallNode(name, args);
        }
        return IdentifierNode(name);
      case TokenType.lparen:
        _consume();
        final inner = _parseOr();
        if (_current.type != TokenType.rparen) {
          throw ExpressionParseError('Expected )', _current.offset);
        }
        _consume();
        return inner;
      default:
        throw ExpressionParseError('Unexpected token: ${tok.value} (${tok.type})', tok.offset);
    }
  }

  static Set<String> referencedFields(ExpressionNode node) {
    return _collectIdentifiers(node)
        .where((id) => !id.startsWith('user.'))
        .toSet();
  }

  static Set<String> _collectIdentifiers(ExpressionNode node) {
    return switch (node) {
      LiteralNode() => {},
      IdentifierNode(name: final name) => {name},
      UnaryNode(operand: final operand) => _collectIdentifiers(operand),
      BinaryNode(left: final l, right: final r) =>
        {..._collectIdentifiers(l), ..._collectIdentifiers(r)},
      CallNode(arguments: final args) =>
        args.expand(_collectIdentifiers).toSet(),
      MemberNode(object: final obj) => _collectIdentifiers(obj),
    };
  }
}
