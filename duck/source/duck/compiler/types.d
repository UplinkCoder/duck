module duck.compiler.types;

import duck.compiler.ast, duck.compiler.lexer, duck.compiler.types;

private import std.meta : AliasSeq;
private import std.typetuple: staticIndexOf;

alias BasicTypes = AliasSeq!("number", "string", "type", "nothing", "error");
alias ExtendedTypes = AliasSeq!(StructType, ModuleType, FunctionType, ArrayType, TupleType, OverloadSetType);

alias Types = AliasSeq!(NumberType, StringType, TypeType, VoidType, ErrorType, StructType, ModuleType, FunctionType, ArrayType, OverloadSetType);

template TypeId(T) {
  static if (staticIndexOf!(T, ExtendedTypes) >= 0) {
    enum TypeId = staticIndexOf!(T, ExtendedTypes) + BasicTypes.length;
  } else {
    static assert(0, T.stringof ~ " is not in extended types list.");
  }
}

template BasicType(string desc) {
  final class BasicType : Type {
    static enum _Kind Kind = staticIndexOf!(desc, BasicTypes);
    override _Kind kind() { return Kind; };
    static assert(Kind >= 0, T.stringof ~ " is not in basic types list.");

    static BasicType create() {
      return instance;
    }

    override string describe() const {
      return desc;
    }
    override bool opEquals(Object o) {
      return this is o;
    }
    private: static __gshared instance = new BasicType();
  }
  //static __gshared BasicType = new BasicTypeT();
}

alias NumberType = BasicType!("number");
alias StringType = BasicType!("string");
alias TypeType = BasicType!("type");
alias VoidType = BasicType!("nothing");
alias ErrorType = BasicType!("error");


mixin template TypeMixin() {
  static enum Kind = TypeId!(typeof(this));//;staticIndexOf!(typeof(this), Types);
  static if (Kind < 0) {
    static assert(false, "Expected type " ~ typeof(this).stringof ~ " to be in Types list.");
  }
  override _Kind kind() { return Kind; };
};


abstract class Type {
  alias _Kind = ubyte;

  _Kind kind();
  string describe() const ;

  final bool isKindOf(T)() {
    return this.kind == T.Kind;
  }

};

final class TupleType : Type {
  mixin TypeMixin;

  Type[] elementTypes;

  override string describe() const {
    import std.conv : to;
    string s = "tuple(";
    foreach (i, e ; elementTypes) {
      if (i != 0) s ~= ", ";
      s ~= e.describe();
    }
    return s ~ ")";
  }

  static auto create(Type[] elementTypes) {
    return new TupleType().init(elementTypes);
  }

  auto init(Type[] elementTypes) {
    this.elementTypes = elementTypes;
    return this;
  }

  size_t length() { return elementTypes.length; }
  ref Type opIndex(size_t index) { return elementTypes[index]; }
}

class StructType : Type {
  mixin TypeMixin;

  string name;
  StructDecl decl;

  override string describe() const {
    return cast(immutable)name;
  }

  static auto create(string name) {
    return new StructType().init(name);
  }

  auto init(string name) {
    this.name = name;
    return this;
  }
}

final class ArrayType : Type {
  mixin TypeMixin;

  Type elementType;

  override string describe() const {
    return "array with elements of type " ~ elementType.describe;// ~ "[]";
  }

  static auto create(Type elementType) {
    return new ArrayType().init(elementType);
  }

  auto init(Type elementType) {
    this.elementType = elementType;
    return this;
  }
}


final class ModuleType : StructType {
  mixin TypeMixin;

  override string describe() const {
    return "module";
  }

  static ModuleType create(string name) {
    return new ModuleType().init(name);
  }

  ModuleType init(string name) {
    this.name = name;
    return this;
  }

}

class OverloadSetType : Type {
  mixin TypeMixin;

  static auto create(OverloadSet set) {
    auto o = new OverloadSetType();
    o.overloadSet = set;
    return o;
  }

  override string describe() const {
    return "overloads";
  }
  OverloadSet overloadSet;
}

class FunctionType : Type {
  mixin TypeMixin;

  static auto create(Type returnType, TupleType parameters) {
    auto f = new FunctionType();
    f.returnType = returnType;
    f.parameters = parameters;
    return f;
  }

  Type returnType;
  //Type[] parameterTypes;
  TupleType parameters;
  CallableDecl decl;

  override string describe() const {
    auto s = "ƒ(";
    foreach (i, param ; parameters.elementTypes) {
      if (i != 0) s ~= ", ";
      s ~= param.describe();
    }
    return s ~ ") -> "~returnType.describe;
  }
};

string mangled(const Type type) {
  return type ? type.describe() : "?";
}
