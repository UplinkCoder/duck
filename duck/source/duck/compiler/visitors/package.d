module duck.compiler.visitors;

import duck.compiler.ast, duck.compiler.lexer, duck.compiler.types;
public import duck.compiler.transforms;

public import duck.compiler.visitors.codegen;

import duck.compiler.buffer;
import std.traits;

auto accept(Node, Visitor)(Node node, auto ref Visitor visitor) {
  import duck.compiler.dbg;
  switch(node.nodeType) {
    foreach(NodeType; NodeTypes) {
      static if (is(NodeType : Node) && is(typeof(visitor.visit(cast(NodeType)node))))
        case NodeType._nodeTypeId: return visitor.visit(cast(NodeType)node);
    }
    default:
      throw __ICE("Visitor " ~ Visitor.stringof ~ " can not visit node of type " ~ node.classinfo.name);
  }
}

auto accept(alias T1, Node)(Node node)
{
  struct DelegateVisitor {
    ReturnType!T1 visit(ParameterTypeTuple!T1[0] n) { return T1(n); }
  }
  return node.accept(DelegateVisitor());
}


auto accept(alias T1, alias T2, Node)(Node node)
{
  struct DelegateVisitor {
    ReturnType!T1 visit(ParameterTypeTuple!T1[0] n) { return T1(n); }
    ReturnType!T2 visit(ParameterTypeTuple!T2[0] n) { return T2(n); }
  }
  return node.accept(DelegateVisitor());
}

void traverse(T)(Node node, bool delegate(T) dg) {
  struct TraverseVisitor {
    bool stopped = false;
    void visit(T t) {
      if (!stopped) {
        if (dg(t))
          recurse(t);
        else stopped = true;
      }
    }
    void visit(T)(T node) {
      if (!stopped) recurse(node);
    }
    mixin RecursiveAccept;
  }
  return node.accept(TraverseVisitor());
}


string className(Type type) {
  //return "";
  if (!type) return "τ";
  return "τ-"~mangled(type);
}

auto or(T...)(T t) {
  Span a = t[0];
  for (int i = 1; i < t.length; ++i) {
    a = a + t[i];
  }
}

T dup(T)(T t) {
  auto e = t.accept(Dup());
  return cast(T)e;
}

mixin template RecursiveAccept() {
    void accept(Node node) {
      node.accept(this);
    }

    void recurse(BinaryExpr expr) {
      accept(expr.left);
      accept(expr.right);
    }

    void recurse(PipeExpr expr) {
      accept(expr.left);
      accept(expr.right);
    }

    void recurse(AssignExpr expr) {
      accept(expr.left);
      accept(expr.right);
    }

    void recurse(UnaryExpr expr) {
      accept(expr.operand);
    }

    void recurse(CallExpr expr) {
      foreach (i, ref arg ; expr.arguments) {
        accept(arg);
      }
      accept(expr.expr);
    }

    void recurse(MemberExpr expr) {
      accept(expr.expr);
    }

    void recurse(RefExpr expr) {
      accept(expr.decl);
    }

    void recurse(TypeExpr expr) {
      accept(expr.expr);
    }

    void recurse(ImportStmt stmt) {
    }

    void recurse(ScopeStmt stmt) {
      accept(stmt.stmts);
    }
    void recurse(ExprStmt stmt) {
      accept(stmt.expr);
    }
    void recurse(Library library) {
      foreach (ref node ; library.nodes) {
        accept(node);
      }
    }
    void recurse(Node node) {

    }
}

struct Dup {
  Node visit(MemberExpr expr) {
    return new MemberExpr(dup(expr.expr), expr.identifier);
  }

  Node visit(IdentifierExpr expr) {
    return new IdentifierExpr(expr.token);
  }
}


struct LineNumber {
  Slice visit(ErrorExpr expr) {
      return expr.slice;
  }
  Slice visit(TypeExpr expr) {
    return expr.expr.accept(this);
  }
  Slice visit(ArrayLiteralExpr expr) {
    Slice s;
    foreach (i, arg ; expr.exprs) {
      s = s + arg.accept(this);
    }
    return Slice();
  }
  Slice visit(InlineDeclExpr expr) {
    return expr.declStmt.accept(this);
  }
  Slice visit(RefExpr expr) {
    return expr.identifier;
  }
  Slice visit(MemberExpr expr) {
    return expr.expr.accept(this) + expr.identifier;
  }
  Slice visit(T)(T expr) if (is(T : LiteralExpr) || is(T : IdentifierExpr)) {
    return expr.token.slice;
  }
  Slice visit(PipeExpr expr) {
    return expr.left.accept(this) + expr.operator + expr.right.accept(this);
  }
  Slice visit(BinaryExpr expr) {
    return expr.left.accept(this) + expr.operator + expr.right.accept(this);
  }
  Slice visit(AssignExpr expr) {
    return expr.left.accept(this) + expr.operator + expr.right.accept(this);
  }
  Slice visit(UnaryExpr expr) {
    return expr.operator + expr.operand.accept(this);
  }
  Slice visit(CallExpr expr) {
    Slice s = expr.expr.accept(this);
    foreach (i, arg ; expr.arguments) {
      s = s + arg.accept(this);
    }
    return s;
  }
  Slice visit(ExprStmt stmt) {
    return stmt.expr.accept(this);
  }
  Slice visit(Stmts stmt) {
    Slice s;
    foreach (i, sm; stmt.stmts) {
      s = s + sm.accept(this);
    }
    return s;
  }
  Slice visit(VarDeclStmt s) {
    return s.expr.accept(this);
  }
  Slice visit(ImportStmt s) {
    return Slice();
  }
  Slice visit(TypeDeclStmt s) {
    return Slice();
    //return s.decl.accept(this);
  }
  /*int visit(Node node) {
    return 0;
  }*/
}
