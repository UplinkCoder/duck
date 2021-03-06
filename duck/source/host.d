module host;

immutable VERSION = import("VERSION");

import duck.compiler;
import duck.host;
import std.file : getcwd;
import std.path : buildPath, dirName;
import std.stdio;
import std.format: format;
import std.algorithm.searching;
import duck.compiler.context;
import std.getopt, std.array;
import core.stdc.stdlib : exit;

import duck.compiler.backend.d;

import duck;

immutable TARGET_CHECK        = "check";
immutable TARGET_EXECUTABLE   = "exe";
immutable TARGET_AST          = "ast";
immutable TARGET_RUN          = "run";
immutable TARGETS = [TARGET_RUN, TARGET_EXECUTABLE, TARGET_AST, TARGET_CHECK];
immutable TARGETS_DEFAULT = TARGET_RUN;

immutable ENGINE_NULL         = "null";
immutable ENGINE_PORT_AUDIO   = "port-audio";
immutable ENGINES = [ENGINE_PORT_AUDIO, ENGINE_NULL];
immutable ENGINES_DEFAULT = ENGINE_PORT_AUDIO;

version (D_Coverage) {
  extern (C) void dmd_coverDestPath(string);
  extern (C) void dmd_coverSourcePath(string);
  extern (C) void dmd_coverSetMerge(bool);
}

void printHelp(GetoptResult result, string error = null) {
  defaultGetoptPrinter(
    "Duck " ~ VERSION ~ "\n"
    "Usage:\n"
    "  duck { options } input.duck\n"
    "  duck { options } -- \"duck code\"\n",
    result.options);
  if (error) {
    stderr.writeln("\nError: ",error);
  }
  exit(1);
}

GetoptResult getopt(T...)(ref string[] args, T opts) {
  try {
    return std.getopt.getopt(args, opts);
  }
  catch(GetOptException e) {
    string[] tmp = [args[0]];
    auto result = std.getopt.getopt(tmp, opts);
    printHelp(result, e.msg);
    return result;
  }
}

int main(string[] args) {
  version(D_Coverage) {
    dmd_coverSourcePath(".");
    dmd_coverDestPath("coverage");
    dmd_coverSetMerge(true);
  }
  version(unittest) {
    return 0;
  }
  else {

    bool verbose = false;
    //bool forever = false;
    bool noStdLib = false;
    bool instrument = false;
    string outputName = "output";
    string[] engines = [];
    string[] targets = [];

    auto result = getopt(
      args,
      std.getopt.config.bundling,
      std.getopt.config.keepEndOfOptions,
      "target|t", format("Targets: %-(%s, %)  (defaults to %s)", TARGETS, TARGETS_DEFAULT), &targets,
      "output|o", "Output filename (excluding extension)", &outputName,
      "engine|e", format("Audio engines: %-(%s, %)  (defaults to %s)", ENGINES, ENGINES_DEFAULT), &engines,
      "nostdlib|n", "Do not automatically import the standard library", &noStdLib,
      "instrument|i", "Add instrumentation code to built binary", &instrument,
      //"forever|f", "Run forever", &forever,
      "verbose|v", "Verbose output", &verbose
    );

    // Set default audio engines, and target
    if (engines.length == 0) engines = [ENGINES_DEFAULT];
    if (targets.length == 0) targets = [TARGETS_DEFAULT];

    if (result.helpWanted || args.length == 1) {
      printHelp(result);
    }

    Context context;
    if (args[1] == "--") {
      context = Duck.contextForString(args[2..$].join(" "));
    } else {
      context = Duck.contextForFile(args[1]);
    }
    if (context.hasErrors) return cast(int)context.errors.length;

    context.instrument = instrument;
    context.verbose = verbose;
    context.includePrelude = !noStdLib;

    context.library;

    if (targets.canFind(TARGET_AST)) {
      import duck.compiler.visitors.json;
      auto json = context.generateJson();
      if (outputName == "-") {
        stdout.writeln(json);
      } else {
        import std.file;
        write(outputName ~ ".json", json);
      }
    }

    if (!context.hasErrors
    && (targets.canFind(TARGET_RUN) || targets.canFind(TARGET_EXECUTABLE))) {
      Backend backend = new DBackend(context);

      if (auto compiler = backend.compiler) {
        auto compiled = compiler.compile(engines);
        if (context.hasErrors) return cast(int)context.errors.length;

        if (targets.canFind(TARGET_EXECUTABLE) && outputName != "-") {
          import std.file;
          copy(compiled.filename, outputName);
        }

        if (targets.canFind(TARGET_RUN)) {
          auto proc = compiled.execute();
          proc.wait();
        }
      }
    }

    return cast(int)context.errors.length;
  }
}
