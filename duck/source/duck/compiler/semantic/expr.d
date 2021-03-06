module duck.compiler.semantic.expr;
import duck.compiler.semantic;
import duck.compiler.semantic.helpers;
import duck.compiler.semantic.overloads;
import duck.compiler.ast;
import duck.compiler.scopes;
import duck.compiler.lexer;
import duck.compiler.types;
import duck.compiler.visitors;
import duck.compiler.dbg;

struct ExprSemantic {
  SemanticAnalysis *semantic;
  int pipeDepth = 0;

  alias semantic this;

  E accept(E)(ref E target) {
    semantic.accept!E(target);
    return target;
  }

  Expr makeModule(Type type, Expr ctor) {
    auto decl = new VarDecl(type, context.temporary());
    return new InlineDeclExpr(new VarDeclStmt(decl, ctor));
  }

  void implicitCall(ref Expr expr) {
    expr.exprType.visit!(
      delegate(OverloadSetType os) {
        expr = expr.call();
        accept(expr);
      },
      (Type type) { }
    );
  }

  void implicitConstruct(ref Expr expr) {
    expr.visit!(
      delegate(ConstructExpr cexpr) {
        if (expr.exprType.as!ModuleType) {
          expr = makeModule(expr.exprType, expr);
          accept(expr);
        }
      },
      (Expr e) { }
    );
    expr.exprType.visit!(
      delegate(TypeType t) {
        // Rewrite: ModuleType
        // to:      ModuleType tmpVar = Module();
        if (auto refExpr = cast(RefExpr)expr) {
          if (refExpr.decl.declType.as!ModuleType) {
            auto ctor = refExpr.call();
            expr = makeModule(refExpr.decl.declType, ctor);
            accept(expr);
            return;
          }
        }
      },
      delegate(Type type) {}
    );
  }

  void implicitConstructCall(ref Expr expr) {
    implicitConstruct(expr);
    implicitCall(expr);
  }

  string describe(Type type) {
    if (auto typeType = cast(TypeType)type) {
      return "type " ~ typeType.type.describe;
    }
    return "a value of type " ~ type.describe;
  }

  Expr coerce(Expr sourceExpr, Type targetType) {
    debug(Semantic) log("=> coerce", sourceExpr.exprType.describe.green, "to", targetType.describe.green);
    auto sourceType = sourceExpr.exprType;

    if (sourceType.isSameType(targetType)) return sourceExpr;

    // Coerce an overload set by automatically calling it
    if (sourceType.as!OverloadSetType) {
      implicitCall(sourceExpr);
      return coerce(sourceExpr, targetType);
    }
    // Coerce type by constructing instance of that type
    if (auto typeType = sourceType.as!TypeType) {
      if (auto moduleType = typeType.type.as!ModuleType) {
        implicitConstruct(sourceExpr);
        return coerce(sourceExpr, targetType);
      }
    }
    // Coerce module by automatically reference field output
    if (auto moduleType = sourceType.as!ModuleType) {
      auto output = moduleType.decl.decls.lookup("output");
      if (output) {
        sourceExpr = sourceExpr.member("output");
        accept(sourceExpr);
        return coerce(sourceExpr, targetType);
      }
    }
    return sourceExpr.error("Cannot coerce " ~ describe(sourceType) ~ " to " ~ describe(targetType));
  }

  bool coerce(Expr[] sourceExpr, CallableDecl targetDecl, ref Expr[] output) {
    auto target = targetDecl.parameterTypes;

    bool error = false;
    for (int i = 0; i < sourceExpr.length; ++i) {
      auto targetType = target[i].getTypeDecl.declType;
      output[i] = coerce(sourceExpr[i], targetType);
      error = error || output[i].hasError;
    }
    return !error;
  }

  bool coerce(Expr[] sourceExpr, CallableDecl targetDecl) {
    return coerce(sourceExpr, targetDecl, sourceExpr);
  }

  TupleExpr coerce(TupleExpr sourceExpr, CallableDecl targetDecl) {
    Expr[] output;
    output.length = sourceExpr.length;
    if (coerce(sourceExpr.elements, targetDecl, output)) {
      auto result = new TupleExpr(output);
      accept(result);
      return result;
    } else {
      sourceExpr.taint;
      return sourceExpr;
    }
  }

  Node visit(ErrorExpr expr) {
    return expr;
  }

  Node visit(InlineDeclExpr expr) {
    accept(expr.declStmt);

    splitStatement(expr.declStmt);
    debug(Semantic) log("=> Split", expr.declStmt);

    Expr ident = new IdentifierExpr(expr).withSource(expr);
    accept(ident);
    return ident;
  }

  Node visit(ArrayLiteralExpr expr) {
    Type elementType;
    foreach(ref e; expr.exprs) {
      accept(e);
      if (!elementType) {
        elementType = e.exprType;
      } else if (elementType != e.exprType) {
        e.error("Expected array element to have type " ~ elementType.mangled);
      }
    }
    expr.exprType = ArrayType.create(expr.exprs[0].exprType);
    return expr;
  }

  Node visit(PipeExpr expr) {
    debug(Semantic) log("PipeExpr", "depth =", pipeDepth);
    debug(Semantic) log("=>", expr);
    pipeDepth++;
    accept(expr.left);
    accept(expr.right);
    pipeDepth--;
    debug(Semantic) log("=>", expr);

    implicitConstructCall(expr.right);

    debug(Semantic) log("=>", expr);

    Expr originalRHS = expr.right;
    expr.exprType = expr.right.exprType;

    while (expr.right.exprType.as!ModuleType && expr.right.isLValue) {
      expr.right = expr.right.member("input");
      accept(expr.right);
      implicitCall(expr.right);
      debug(Semantic) log("=>", expr);
    }

    expr.left = coerce(expr.left, expr.right.exprType);
    if(!expr.left.hasError)
      expect(isPipeTarget(expr.right), expr.right, "Right hand side of connection must be a module field");

    if (expr.left.hasError || expr.right.hasError) expr.taint;

    if (pipeDepth > 0) {
      Stmt stmt = new ExprStmt(expr);
      debug(Semantic) log("=> Split", expr);
      splitStatement(stmt);
      return originalRHS;
    }

    return expr;
  }

  CallableDecl resolveCall(Expr expr, SymbolTable searchScope, string identifier, Expr[] arguments, Expr context = null) {
    return resolveCall(expr, cast(OverloadSet)searchScope.lookup(identifier).decl, arguments);
  }

  CallableDecl resolveCall(Expr expr, OverloadSet overloadSet, Expr[] arguments, Expr context = null) {
    if (!overloadSet) return null;

    TupleExpr args = new TupleExpr(arguments.dup);
    accept(args);
    CallableDecl[] viable;
    auto best = findBestOverload(overloadSet, context, args, &viable);
    if (expect(viable.length == 0, expr, "Ambigious call.") && best) {
      return best;
    }
    return null;
  }

  Node visit(UnaryExpr expr) {
    accept(expr.operand);

    if (expr.operand.hasError) return expr.taint;

    auto callable = resolveCall(expr, symbolTable, expr.operator, expr.arguments);
    if (callable && coerce(expr.arguments, callable)) {
      Expr e = callable.call(expr.arguments).withSource(expr);
      return accept(e);
    }

    return expr.operand.error("Operation " ~ expr.operator.value.idup ~ " " ~ mangled(expr.operand.exprType) ~ " is not defined.");
  }

  Node visit(BinaryExpr expr) {
    accept(expr.left);
    accept(expr.right);

    if (expr.left.hasError || expr.right.hasError) {
      expr.taint;
    }
    else {
      auto callable = resolveCall(expr, symbolTable, expr.operator, expr.arguments);
      if (callable && coerce(expr.arguments, callable)) {
        Expr e = callable.call(expr.arguments).withSource(expr);
        return accept(e);
      }
    }

    auto call = new ErrorExpr(expr.operator).taint.call(expr.arguments);
    if (!expr.hasError)
      call.error("Operation " ~ mangled(expr.left.exprType) ~ " " ~ expr.operator.value.idup ~ " " ~ mangled(expr.right.exprType) ~ " is not defined.");

    return call.taint;
  }

  Node visit(TupleExpr expr) {
    bool tupleError = false;
    Type[] elementTypes = [];
    assumeSafeAppend(elementTypes);
    foreach (ref Expr e; expr) {
      accept(e);
      if (e.hasError)
        tupleError = true;
      elementTypes ~= e.exprType;
    }
    if (tupleError) return expr.taint;

    expr.exprType = TupleType.create(elementTypes);
    return expr;
  }

  Expr expandMacro(CallableDecl macroDecl, Expr[] arguments, Expr contextExpr = null) {
    debug(Semantic) log("=> ExpandMacro", macroDecl, contextExpr);

    Expr[Decl] replacements;
    foreach (i, parameter; macroDecl.parameters) {
      replacements[parameter] = arguments[i];
    }
    if (macroDecl.parentDecl)
      replacements[macroDecl.parentDecl.context] = contextExpr;

    Expr expansion = macroDecl.returnExpr;
    debug(Semantic) log("=> expansion", expansion);
    expansion = expansion.dupWithReplacements(replacements);
    debug(Semantic) log("=> expansion", expansion);
    accept(expansion);

    return expansion;
  }

  Node visit(ConstructExpr expr) {
    accept(expr.target);
    accept(expr.arguments);
    debug(Semantic) log("=>", expr);

    Decl decl = expr.target.getTypeDecl();

    debug(Semantic) log("=> decl", decl);
    if (expr.target.hasError || expr.arguments.hasError)
      return expr.taint;

    //TODO: Generate default constructor if no constructors are defined.
    if (expr.arguments.length == 0) {
      expr.exprType = expr.callable.getTypeDecl().declType;
      return expr;
    }

    return expr.target.exprType.visit!(
      delegate(TypeType type) {
        if (expr.arguments.length == 1 && expr.arguments[0].exprType == decl.declType) {
          return expr.arguments[0];
        }

        return decl.visit!(
          (StructDecl structDecl) {
            // TODO: Rewrite as call expression instead
            OverloadSet os = structDecl.ctors;
            expr.context = structDecl.reference().withSource(expr);
            accept(expr.context);

            auto best = resolveCall(expr, os, expr.arguments.elements, expr.context);
            if (best) {
              expr.arguments = coerce(expr.arguments, best);
              expr.exprType = decl.declType;
              // Expand macros immediately
              if (best.isMacro) {
                return expandMacro(best, expr.arguments.elements, expr.context);
              }
              return expr;
            }
            else {
              return expr.error("No constructor matches argument types " ~ expr.arguments.exprType.describe());
            }
          },
          (TypeDecl typeDecl) {
            return expr;
          }
        );
      }
    );
  }

  Node visit(IndexExpr expr) {
    accept(expr.expr);
    accept(expr.arguments);
    debug(Semantic) log("=>", expr);

    if (expr.expr.hasError || expr.arguments.hasError)
      return expr.taint;

    return expr.expr.exprType.visit!(
      (StaticArrayType t) {
        if (expr.arguments.length != 1) {
          expr.arguments.error("Only one index accepted");
          return expr.taint;
        }
        expr.exprType = t.elementType;
        return expr;
      },
      (ArrayType t) {
        if (expr.arguments.length != 1) {
          expr.arguments.error("Only one index accepted");
          return expr.taint;
        }
        expr.exprType = t.elementType;
        return expr;
      },
      (TypeType t) {
        TypeDecl decl = expr.expr.getTypeDecl;
        debug(Semantic) log ("=>", decl);
        ArrayDecl arrayDecl;

        if (expr.arguments.length == 0)
          arrayDecl = new ArrayDecl(decl);
        else {
          if (expr.arguments.length != 1) {
            expr.arguments.error("Only one length accepted.");

            return expr.taint;
          }
          import std.conv: to;
          auto size = expr.arguments[0].visit!(
              (LiteralExpr literal) => literal.value.toString().to!uint,
              (Expr e) {
                expr.arguments.error("Expected a number for array size.");
                expr.taint;
                return cast(uint)0;
              }
          )();
          if (expr.hasError) return expr;

          arrayDecl = new ArrayDecl(decl, size);
        }

        auto re = arrayDecl.reference();
        re.exprType = t;
        accept(re);
        return re;
      }
    );
  }

  Node visit(CallExpr expr) {
    accept(expr.callable);
    debug(Semantic) log("=>", expr);
    pipeDepth++;
    accept(expr.arguments);
    pipeDepth--;
    debug(Semantic) log("=>", expr);

    if (expr.callable.hasError || expr.arguments.hasError)
      return expr.taint;

    if (!expr.context) {
      expr.context = expr.callable.visit!(
        (RefExpr expr) => expr.context,
        (Expr expr) => null
      );
    }

    Node resolve(CallExpr expr) {
      return expr.callable.exprType.visit!(
        delegate (FunctionType ft) {
          expr.arguments = coerce(expr.arguments, ft.decl);
          expr.exprType = ft.returnType;
          if (ft.decl.isMacro) {
            return expandMacro(ft.decl, expr.arguments.elements, expr.context);
          }
          return expr;
        },
        delegate (OverloadSetType ot) {
          debug(Semantic) log("=>", "context", expr.context);

          auto best = resolveCall(expr, ot.overloadSet, expr.arguments.elements, expr.context);
          if (expect(best, expr, "No functions matches arguments.")) {
            expr.callable = expr.callable.visit!(
              (RefExpr r) => best.reference().withContext(r.context).withSource(r)
            );

            accept(expr.callable);
            return resolve(expr);
          }
          return expr;
        },
        delegate (TypeType tt) {
          Expr e = new ConstructExpr(expr.callable, expr.arguments, expr.source);
          accept(e);
          return e;
        },
        delegate (Type tt) {
          return expr.error("Cannot call something with type " ~ mangled(expr.callable.exprType));
        }
      );
    }
    return resolve(expr);
  }

  Node visit(AssignExpr expr) {
    //TODO: Type check
    accept(expr.left);
    implicitCall(expr.left);
    debug(Semantic) log("=>", expr);
    accept(expr.right);
    implicitCall(expr.right);
    debug(Semantic) log("=>", expr);
    expr.exprType = expr.left.exprType;
    return expr;
  }

  Node visit(IdentifierExpr expr) {
    ContextDecl decl = symbolTable.lookup(expr.identifier);

    if (decl) {
      auto reference = decl.reference()
        .withContext(decl.context)
        .withSource(expr);
      accept(reference);
      return reference;
    }

    return expr.error("Undefined identifier " ~ expr.identifier.idup);
  }

  Node visit(TypeExpr expr) {
      accept(expr.expr);
      debug(Semantic) log("=>", expr.expr);

      if (auto re = cast(RefExpr)expr.expr) {
        if (expr.expr.exprType.as!TypeType && re.decl.as!TypeDecl) {
          expr.exprType = expr.expr.exprType;
          expr.decl = re.decl.as!TypeDecl;
          return expr;
        }
      }

      if (!expr.expr.hasError) {
        expr.decl = new TypeDecl(ErrorType.create());
        expr.error("Expected a type");
      }
      return expr.taint();
  }

  Node visit(RefExpr expr) {
    if (expr.context) {
      accept(expr.context);
      debug(Semantic) log("=>", expr);
      implicitConstructCall(expr.context);
      if (expr.context.hasError) return expr.taint;
    }

    return expr.decl.visit!(
      (TypeDecl decl) => (expr.exprType = TypeType.create(decl.declType), expr),
      (VarDecl decl) => (expr.exprType = decl.declType, expr),
      (FieldDecl decl) => (expr.exprType = decl.declType, expr),
      (ParameterDecl decl) => (expr.exprType = decl.declType, expr),
      (CallableDecl decl) => (expr.exprType = decl.declType, expr),
      (OverloadSet os) => (expr.exprType = OverloadSetType.create(os), expr)
    );
  }

  Node visit(MemberExpr expr) {
    accept(expr.context);
    implicitConstructCall(expr.context);
    debug(Semantic) log("=>", expr);

    if (expr.context.hasError) return expr.taint;

    return expr.context.exprType.visit!(
      (ModuleType type) {
        ASSERT(isLValue(expr.context), "Modules can not be temporaries.");

        auto member = type.decl.decls.lookup(expr.name);
        if (!member) {
          return expr.error("No member " ~ expr.name ~ " in " ~ type.decl.name);
        }

        auto refExpr = member.reference().withContext(expr.context).withSource(expr);
        return accept(refExpr);
    },
    (Type t) {
      expr.context.error("Cannot access members of " ~ expr.context.exprType.mangled());
      return expr.taint;
    });
  }

  // Nothing to do for these
  Node visit(LiteralExpr expr) {
    return expr;
  }
}
