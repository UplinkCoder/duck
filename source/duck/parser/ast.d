module duck.compiler.ast;

import duck.compiler.lexer, duck.compiler.types, duck.compiler.semantic;
import duck.compiler.scopes;
import duck.compiler;
import core.exception;

private import std.meta : AliasSeq;
private import std.typetuple: staticIndexOf;
private import std.typecons: Rebindable;
alias NodeTypes = AliasSeq!(
  Program,
  Decl,
  VarDecl,
  TypeDecl,
  ConstDecl,
  FieldDecl,
  MethodDecl,
  StructDecl,
  AliasDecl,
  ExprStmt,
  VarDeclStmt,
  TypeDeclStmt,
  ScopeStmt,
  ImportStmt,
  Stmts,
  ErrorExpr,
  RefExpr,
  TypeExpr,
  InlineDeclExpr,
  ArrayLiteralExpr,
  LiteralExpr,
  IdentifierExpr,
  UnaryExpr,
  AssignExpr,
  BinaryExpr,
  PipeExpr,
  MemberExpr,
  CallExpr,
  MacroDecl);

mixin template NodeMixin() {
  static enum _nodeTypeId = staticIndexOf!(typeof(this), NodeTypes);
  static if (_nodeTypeId < 0) {
    //#TODO:0 Do it right
    static assert(false, "Expected type " ~ typeof(this).stringof ~ " to be in NodeTypes list.");
  }
  override NodeType nodeType() { return _nodeTypeId; };
};

abstract class Node {
  alias NodeType = ubyte;
  this() {
    //writefln("%s %s", this, &this);
  }
  NodeType nodeType();
};

abstract class Stmt : Node {
};

class Program : Node {
  mixin NodeMixin;

  Node[] nodes;
  Decl[] decls;
  DeclTable imported;

  this(Node[] nodes, Decl[] decls = []) {
    this.imported = new DeclTable();
    this.nodes = nodes;
    this.decls = decls;
  }
}

abstract class Decl : Node {
  mixin NodeMixin;

  Token name;
  //Expr expr;
  //Rebindable!(immutable Type) varType;
  //Token identifier;
  Type declType;

  this(Type type, Token name) {
    this.name = name;
    this.declType = type;
  }

/*  this(Token identifier, Expr expr, immutable .Type type = null) {
    this.varType = type;
    this.expr = expr;
    this.identifier = identifier;
  }*/
}

class AliasDecl : Decl {
  mixin NodeMixin;

  Expr targetExpr;

  this(Token identifier, Expr targetExpr) {
    super(null, identifier);
    this.targetExpr = targetExpr;
  }
}

class MacroDecl : Decl {
  mixin NodeMixin;

  Expr[] argTypes;
  Token[] argNames;
  Expr expansion;
  Expr typeExpr;

  this(Expr typeExpr, Token identifier, Expr[] argTypes, Token[] argNames, Expr expansion) {
    super(null, identifier);
    this.typeExpr = typeExpr;
    this.argTypes = argTypes;
    this.argNames = argNames;
    this.expansion = expansion;
  }
}

class FieldDecl : Decl{
  mixin NodeMixin;

  TypeExpr typeExpr;
  alias identifier = name;
  Expr valueExpr;
  StructDecl parentDecl;

  this(TypeExpr typeExpr, Token identifier, Expr valueExpr, StructDecl parent) {
    super(null, identifier);
    this.typeExpr = typeExpr;
    this.valueExpr = valueExpr;
    this.parentDecl = parent;
  }
}

class MethodDecl : Decl {
  mixin NodeMixin;
  Stmt methodBody;
  Decl parentDecl;

  this(Type type, Token identifier, Stmt methodBody, Decl parent) {
    super(type, identifier);
    this.methodBody = methodBody;
    this.parentDecl = parent;
  }
}

class StructDecl : TypeDecl {
  mixin NodeMixin;

  DeclTable decls;
  alias decls this;

  bool external;

  this(Type type, Token name) {
    super(type, name);
    decls = new DeclTable();
  }
}

/*class FuncDecl : Decl {
  mixin NodeMixin;
  bool external;
  Stmt funcBody;

  this(Type type, Token identifier, Stmt methodBody, Decl parent) {
    super(type, identifier);
    this.methodBody = methodBody;
    this.parentDecl = parent;
  }
}*/
/*class FuncDecl : Decl {
  Token identifier;
  Type returnType;
  FieldDecl[] arguments;
  this(Type type, Token identifier, Type returnType, FieldDecl[] args, Stmt funcBody) {
    super(type);
    this.identifier = identifier;
    this.returnType = type;
    this.arguments = args;
    this.fields = fields;
  }
}*/


// hz(number) => frequency
// frequency / frequency => number
// frequency + frequency => frequency
// frequency - frequency => frequency
// number * frequency => frequency

class VarDecl : Decl {
  mixin NodeMixin;

  Expr typeExpr;

  this(Type type, Token name) {
    super(type, name);
  }
  this(Expr typeExpr, Token identifier) {
    super(null, identifier);
    this.typeExpr = typeExpr;
  }
}

class TypeDecl : Decl {
  mixin NodeMixin;

  this(Type type, Token name) {
    super(type, name);
  }
}

class ConstDecl : Decl {
  mixin NodeMixin;
  Expr value;

  this(Type type, Token name, Expr value) {
    super(type, name);
    this.value = value;
  }
}

class Stmts : Stmt {
  mixin NodeMixin;
  Stmt[] stmts;

  this (Stmt[] stmts) {
    this.stmts = stmts;
  }
};

class ImportStmt : Stmt {
  mixin NodeMixin;
  Token identifier;

  this(Token identifier) {
    this.identifier = identifier;
  }
}

class VarDeclStmt : Stmt {
  mixin NodeMixin;

  Token identifier;
  Decl decl;
  Expr expr;

  this(Token token, Decl decl, Expr expr) {
    this.identifier = token;
    this.decl = decl;
    this.expr = expr;
  }
}

class TypeDeclStmt : Stmt {
  mixin NodeMixin;

  Decl decl;

  this(Decl decl) {
    this.decl = decl;
  }
}


class ScopeStmt : Stmt {
  mixin NodeMixin;

  Stmts stmts;
  this(Stmts stmts) {
    this.stmts = stmts;
  }
}

abstract class Expr : Node {
  Type _exprType;

  @property bool exprTypeSet() {
    return _exprType !is null;
  }

  @property Type exprType() {
    if (!_exprType) {
      throw __ICE("Trying to use expression type before it is calculated");
    }
    return _exprType;
  }

  @property void exprType(Type type) {
    _exprType = type;
  }

  override string toString() {
    import duck.compiler.dbg;
    return cast(string)this.accept(ExprToString());
  }
}

class ErrorExpr : Expr {
    mixin NodeMixin;
    Span span;
    this(Span span) {
      this.span = span;
      this.exprType = errorType;
    }
}

class ExprStmt : Stmt {
  mixin NodeMixin;

  Expr expr;
  this(Expr expr) {
    this.expr = expr;
  }
}

class InlineDeclExpr : IdentifierExpr {
  mixin NodeMixin;

  VarDeclStmt declStmt;

  this(Token token, VarDeclStmt declStmt) {
    super(token);
    this.declStmt = declStmt;
  }
}

class RefExpr : Expr {
  mixin NodeMixin;

  Decl decl;
  Token identifier;

  this(Token identifier, Decl decl) {
    this.identifier = identifier;
    this.decl = decl;
  }
}

class TypeExpr : Expr {
  mixin NodeMixin;

  Expr expr;
  TypeDecl decl;

  this(Expr expr) {
    this.expr = expr;
  }
}

class LiteralExpr : Expr {
  mixin NodeMixin;

  Token token;
  this(Token token) {
    this.token = token;
    if (token.type == Number)
      this.exprType = numberType;
    else if (token.type == StringLiteral)
      this.exprType = stringType;
  }
}

class ArrayLiteralExpr : Expr {
  mixin NodeMixin;

  Expr[] exprs;
  this(Expr[] exprs) {
    this.exprs = exprs;
  }
}

class IdentifierExpr : Expr {
  mixin NodeMixin;

  Token token;

  this(Token token) {
    this.token = token;
  }
}

class UnaryExpr : Expr {
  mixin NodeMixin;

  Token operator;
  Expr operand;

  this(Token op, Expr operand) {
    operator = op;
    this.operand = operand;
  }
}

class BinaryExpr : Expr {
  mixin NodeMixin;

  Token operator;
  Expr left, right;

  this(Token op, Expr left, Expr right) {
    this.operator = op;
    this.left = left;
    this.right = right;
  }
}

class PipeExpr : Expr {
  mixin NodeMixin;

  Token operator;
  Expr left, right;

  this(Token op, Expr left, Expr right) {
    this.operator = op;
    this.left = left;
    this.right = right;
  }
}

class AssignExpr : Expr {
  mixin NodeMixin;

  Token operator;
  Expr left, right;

  this(Token op, Expr left, Expr right) {
    this.operator = op;
    this.left = left;
    this.right = right;
  }
}

class MemberExpr : Expr {
  mixin NodeMixin;

  Expr expr;
  Token identifier;

  this(Expr expr, Token identifier) {
    this.expr = expr;
    this.identifier = identifier;
  }
}

class CallExpr : Expr {
  mixin NodeMixin;

  Expr expr;
  Expr[] arguments;

  this(Expr expr, Expr[] arguments) {
    this.expr = expr;
    this.arguments = arguments;
  }
}

auto accept(Visitor)(Node node, auto ref Visitor visitor) {
///writefln("Visit %s %s", node.nodeType, node);

  switch(node.nodeType) {
    foreach(NodeType; NodeTypes) {
      static if (is(typeof(visitor.visit(cast(NodeType)node))))
        case NodeType._nodeTypeId: return visitor.visit(cast(NodeType)node);
    }
    default:
      throw __ICE("Visitor " ~ Visitor.stringof ~ " can not visit node of type " ~ node.classinfo.name);
  }
}
/*
import std.stdio: writefln;
import std.typetuple, std.traits;


auto accept(Visitor...)(Node node, auto ref Visitor visitors) if (Visitor.length > 1) {
  template getVisitorResultType(T) {
    alias getVisitorResultType = ReturnType!(&accept!T);//T.VisitResultType;
  }
  //alias ReturnTypes = staticMap!(ReturnType, staticMap!(getVisitor, Visitor));
  alias ReturnTypes = staticMap!(getVisitorResultType, Visitor);

  ReturnTypes R;
  foreach(i, visitor; visitors) {
    {  ReturnTypes[i] result;
      //writefln("Visit using %s", typeof(visitor).stringof);
      static if (i == 0) {
        R[i] = node.accept(visitor);
      } else {
        R[i] = R[i-1].accept(visitor);
      }
    }
  }
  return R[R.length-1];
}*/