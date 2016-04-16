module duck.compiler.semantic.helpers;

import duck.compiler.visitors;
import duck.compiler.context;

import duck.compiler.ast;
import duck.compiler.types;
import duck.compiler.lexer.tokens;

bool hasError(Expr expr) {
  return (cast(ErrorType)expr._exprType) !is null;
}

bool hasType(Expr expr) {
  return expr._exprType !is null;
}

auto taint(Expr expr) {
  expr.exprType = ErrorType.create;
  return expr;
}

auto taint(Decl decl) {
  decl.declType = ErrorType.create;
  return decl;
}

bool isLValue(Expr expr) {
  return expr.visit!(
    (RefExpr r) => true,
    (MemberExpr m) => isLValue(m.left),
    (Expr e) => false
  );
}

/*
F1 is determined to be a better function than F2 if implicit conversions for
all arguments of F1 are not worse than the implicit conversions for all arguments of F2, and
1) there is at least one argument of F1 whose implicit conversion is better than the corresponding implicit conversion for that argument of F2
2) or. if not that, (only in context of non-class initialization by conversion), the standard conversion sequence from the return type of F1 to the type being initialized is better than the standard conversion sequence from the return type of F2
3) or, if not that, F1 is a non-template function while F2 is a template specialization
4) or, if not that, F1 and F2 are both template specializations and F1 is more specialized according to the partial ordering rules for template specializations
*/

enum MatchResult {
  Equal,
  Better,
  Worse
}

bool isFunctionViable(Type[] args, FunctionType A) {
  return false;
}

// M - N - parameters to use
MatchResult rankViableFunctionArgs(TupleType T, TupleType F1, TupleType F2, ulong M, ulong N) {
  return rankArgLists(T.elementTypes, F1.elementTypes, F2.elementTypes, 0, T.elementTypes.length);
}

MatchResult rankFunctions(Type[] args, FunctionType A, FunctionType B) {
  // Best viable function
  return MatchResult.Equal;
}

MatchResult rankArgLists(Type[] T, Type[] A, Type[] B, ulong M, ulong N) {
  bool someWorse = false;
  bool someBetter = false;
  for (ulong i = M; i < N; ++i) {
    MatchResult result = T[i].rankArgs(A[i], B[i]);
    if (result == MatchResult.Worse) someWorse = true;
    if (result == MatchResult.Better) someBetter = true;
  }
  if (someBetter == someWorse) return MatchResult.Equal;
  if (someBetter) return MatchResult.Better;
  if (someWorse) return MatchResult.Worse;
  return MatchResult.Equal;
}

MatchResult rankArgs(Type T, Type A, Type B) {
  // Ranking of implicit conversion sequence
  return T.visit!(
    (TupleType T) {
      if (T.elementTypes.length == 1) {
        return rankArgs(
          T.elementTypes[0],
          cast(TupleType)A ? (cast(TupleType)A).elementTypes[0] : A,
          cast(TupleType)B ? (cast(TupleType)B).elementTypes[0] : B);
      }
      return rankArgLists(T.elementTypes, (cast(TupleType)A).elementTypes, (cast(TupleType)B).elementTypes, 0, cast(int)T.elementTypes.length);
    },
    (Type T) {
      bool eqA = T == A;
      bool eqB = T == B;
      if (eqA == eqB) return MatchResult.Equal;
      if (eqA) return MatchResult.Better;
      if (eqB) return MatchResult.Worse;
      return MatchResult.Equal;
    }
  );
}

unittest {
  assert(rankArgs(NumberType.create, NumberType.create, NumberType.create) == MatchResult.Equal);
  assert(rankArgs(NumberType.create, StringType.create, NumberType.create) == MatchResult.Worse);
  assert(rankArgs(NumberType.create, NumberType.create, StringType.create) == MatchResult.Better);
  assert(rankArgLists([NumberType.create, StringType.create], [NumberType.create, StringType.create], [NumberType.create, StringType.create], 0, 2) == MatchResult.Equal);
  assert(rankArgLists([NumberType.create, StringType.create], [NumberType.create, StringType.create], [StringType.create, StringType.create], 0, 2) == MatchResult.Better);
  assert(rankArgLists([NumberType.create, StringType.create], [StringType.create, StringType.create], [NumberType.create, StringType.create], 0, 2) == MatchResult.Worse);
}
/**
http://en.cppreference.com/w/cpp/language/overload_resolution
https://stackoverflow.com/questions/29090692/how-is-ambiguity-determined-in-the-overload-resolution-algorithm
...] let ICSi(F) denote the implicit conversion sequence that converts the i-th argument in
 the list to the type of the i-th parameter of viable function F.
[...] a viable function F1 is defined to be a better function than another viable function F2
if for all arguments i, ICSi(F1) is not a worse conversion sequence than ICSi(F2), and then
— for some argument j, ICSj(F1) is a better conversion sequence than ICSj(F2)
*/
/*
bool isImplictlyConvertible(Type sourceType, Type targetType) {
  if (sourceType == targetType) return true;
  return sourceType.visit!(
    delegate (TupleType source) {
      return targetType.visit!(
        delegate (TupleType target) {
          if (source.elementTypes.length != target.elementTypes.length)
            return false;
          for (int i = 0; i < source.elementTypes.length; ++i) {
            if (!source.elementTypes[i].isImplictlyConvertible(target.elementTypes[i]))
              return false;
          }
          return true;
        },
        (Type type) => false
      );
    },
    (Type type) => false
  );
}*/
/*
for (int i = 0; i < type.parameterTypes.length; ++i) {
  Type paramType = type.parameterTypes[i];
  Type argType = expr.arguments[i].exprType;
  if (paramType != argType)
  {
    if (isModule(expr.arguments[i]))
    {
      expr.arguments[i] = new MemberExpr(expr.arguments[i], context.token(Identifier, "output"));
      accept(expr.arguments[i]);
      continue outer;
    }
    else
      error(expr.arguments[i], "Cannot implicity convert argument of type " ~ mangled(argType) ~ " to " ~ mangled(paramType));
  }
}
*/


bool isModule(Expr expr) {
  return expr.exprType.kind == ModuleType.Kind;
}