module duck.compiler.backend.d.dmd;
import duck.compiler.backend.backend: Executable;
import std.algorithm: canFind;
import std.exception: assumeUnique;
import std.stdio: stdout, stdin, stderr;
import std.process;
import std.path : buildPath;

private {
  int tmpIndex = 0;
  string tmpFolder = "/tmp/";
}

private string temporaryFileName() {
    import std.conv: to;
    return "duck_temp" ~ tmpIndex.to!string;
}

struct DCompilerOptions {
  string[] flags;
  string[] sourceFiles;
  string[] libraries;
  string[] frameworks;
  string[] versions;

  void merge(const DCompilerOptions options) {
    foreach (s; options.flags)
      if (!flags.canFind(s)) flags ~= s;
    foreach (s; options.sourceFiles)
      if (!sourceFiles.canFind(s)) sourceFiles ~= s;
    foreach (s; options.libraries)
      if (!libraries.canFind(s)) libraries ~= s;
    foreach (s; options.frameworks)
      if (!frameworks.canFind(s)) frameworks ~= s;
    foreach (s; options.versions)
      if (!versions.canFind(s)) versions ~= s;
  }

  version(OSX)
  static immutable DCompilerOptions PortAudio = {
    sourceFiles: [
      "duck/plugin/portaudio/package",
      "deimos/portaudio.di"
    ],
    libraries: ["../runtime/lib/libportaudio.a"],
    frameworks: ["CoreAudio", "CoreFoundation", "CoreServices", "AudioUnit", "AudioToolbox"],
    versions: ["USE_PORT_AUDIO"]
  };

  static immutable DCompilerOptions
    OSC = {
      versions: ["USE_OSC"],
      sourceFiles: [
        "duck/plugin/osc/server",
        "duck/plugin/osc/ugen"
      ]
    },
    Instrumentation = {
      sourceFiles: [
        "duck/runtime/instrument.d"
      ],
      versions: ["USE_INSTRUMENTATION"]
    },
    DuckRuntime = {
      flags: ["-release", "-inline"],
      //libraries: ["../bin/libduck.a"],
      sourceFiles: [
        "duck/runtime/package",
        "duck/runtime/model",
        "duck/runtime/scheduler",
        "duck/runtime/entry",
        "duck/runtime/global",
        "duck/runtime/print",
        "duck/stdlib/package",
        "duck/stdlib/scales",
        "duck/stdlib/units",
        "duck/stdlib/ugens"
      ]
      };
}

struct DFile {
  string filename;
  string name;
  DCompilerOptions options;

  bool opCast() {
    return filename != null;
  }

  this(string filename, string name = null) {
    this.name = name;
    this.filename = filename;
    this.options.merge(DCompilerOptions.DuckRuntime);
  }

  static tempFromHash(size_t hash) {
    import std.digest.digest : toHexString;
    ubyte[8] result = (cast(ubyte*) &hash)[0..8];
    string name = "duck_" ~ toHexString(result[0..8]).assumeUnique;
    string filename = (tmpFolder ~ name ~ ".d").assumeUnique;
    return DFile(filename, name);
  }

  Executable compile() {
      return compile(tmpFolder ~ temporaryFileName());
  }

  Executable compile(string output) {
    stdout.flush();
    auto command = "dmd  -Iruntime/source -of" ~ output ~ buildCommand(options);
    debug(VERBOSE) writeln("EXECUTE: ", command);
    debug(duck_host) stderr.writefln("%s", command);
    Pid compile = spawnShell(command, stdin, stdout, stderr, null, Config.none, null);
    auto result = wait(compile);
    debug(duck_host) stderr.writeln("Done compiling");
    return Executable(output);
  }

  static string hostFolder() {
    import core.runtime;
    import std.path : dirName;
    string path = dirName(Runtime.args[0]);
    if (path.length > 0 && (path[$-1] != '/' && path[$-1] != '\\'))
        path = path ~ "/";
    return path;
  }

  static string buildCommand(DCompilerOptions options) {
    string path = hostFolder;
    string command;
    foreach (string v; options.flags)
      command ~= " " ~ v;
    foreach(string sourceFile; options.sourceFiles)
      command ~= " " ~ buildPath(hostFolder, "../runtime/source/", sourceFile);
    foreach (string v; options.versions)
      command ~= " -version=" ~ v;
    foreach(string library; options.libraries)
        command ~= " -L" ~ path ~ library;
    foreach(string framework; options.frameworks)
        command ~= " -L-framework -L" ~ framework;
    return command;
  }
}
