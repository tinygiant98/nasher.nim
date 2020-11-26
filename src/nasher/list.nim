import json, os, sequtils, strformat, strutils
import utils/[cli, libraries, manifest, options]

const
  helpList* = """
  Usage:
    nasher list [options]

  Description:
    For each target, lists the name, description, source files, and final
    filename of all build targets. These names can be passed to the compile or
    pack commands.  For a library, list information for each installed or
    publicly available library.

  Options:
    --l|lib[:<library>]   List details for all libraries or a specified library
    --public|private      List public/private libraries [default: private]

  Global Options:
    -h, --help     Display help for nasher or one of its commands
    -v, --version  Display version information

  Logging:
    --debug        Enable debug logging
    --verbose      Enable additional messages about normal operation
    --quiet        Disable all logging except errors
    --no-color     Disable color output (automatic if not a tty)
  """

proc list*(opts: Options, sector: Sector = private) =
  ## lists the installed or available libraries
  let
    file =
      case sector
      of private: installedLibraries
      of public: publicLibraries
    manifest = parseLibraryManifest(getLibrariesDir() / file)  # type Manifest
    library = opts.get("library")
  
  var hasRun = false
  
  if library.len == 0:
    display("Listing", fmt"{sector} libraries")

  for k, v in manifest.data:
    if v["name"].getStr().startsWith("__"):
      continue

    if library.len > 0 and v["name"].getStr() != library:
      continue

    if hasRun: stdout.write("\n")
    display("Name:", v["name"].getStr(), priority = HighPriority)
    display("Path:", v["path"].getStr())
    display("VCS:", v["method"].getStr(), priority = LowPriority)
    display("Description:", v["description"].getStr())
    display("License:", v["license"].getStr(), priority = LowPriority)
    display("Parents:", v["parents"].getElems().mapIt(it.getStr()).join(", "), priority = LowPriority)
    display("Children:", v["children"].getElems().mapIt(it.getStr()).join(", "), priority = LowPriority)
    if getLogLevel() < HighPriority:
      hasRun = true
    
proc list*(opts: Options, pkg: PackageRef) =
  # check to see if we're listing libraries or a specific library
  case opts.get("list")
  of "libraries":
    list(opts, parseEnum(opts.get("level"), private))
  else:
    let listTarget = opts.get("target")

    if pkg.targets.len > 0:
      var hasRun = false
      for target in pkg.targets:
        if listTarget.len > 0 and target.name != listTarget:
          continue
        
        if hasRun:
          stdout.write("\n")
        display("Target:", target.name, priority = HighPriority)
        display("Description:", target.description)
        display("File:", target.file)
        display("Includes:", target.includes.join("\n"))
        display("Excludes:", target.excludes.join("\n"))
        display("Filters:", target.filters.join("\n"))

        for pattern, dir in target.rules.items:
          display("Rule:", pattern & " -> " & dir)
        hasRun = true
    else:
      fatal("No targets found. Please check your nasher.cfg.")
