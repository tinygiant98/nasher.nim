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

proc listLibraries(opts: Options, sector: Sector = private) =
  ## lists the installed or available libraries
  let
    file =
      case sector
      of private: installedLibraries
      of public: publicLibraries
    manifest = parseLibraryManifest(getLibrariesDir() / file)
    library = opts.get("library")
    plurality = if library.len == 0: "ies" else: "y"
  
  var hasRun = false
  
  display("Listing", fmt"{sector} librar{plurality}")
  if sector == public:
    warning("public libraries must be installed before use")
  else:
    display("Info:", "private libraries are installed and ready to use", displayType = Success)

  for k, v in manifest.data:
    if v["name"].getStr().startsWith("__"):
      continue

    if library.len > 0 and v["name"].getStr() != library:
      continue

    if hasRun: stdout.write("\n")
    display("Library:", v["name"].getStr(), priority = HighPriority)
    display("Path:", v["path"].getStr())
    display("VCS:", v["method"].getStr(), priority = LowPriority)
    display("Description:", v["description"].getStr())
    display("License:", v["license"].getStr(), priority = LowPriority)
    display("Parents:", v["parents"].getElems().mapIt(it.getStr()).join(", "), priority = LowPriority)
    display("Children:", v["children"].getElems().mapIt(it.getStr()).join(", "), priority = LowPriority)
    if getLogLevel() < HighPriority:
      hasRun = true
    
proc listTargets(opts: Options, pkg: PackageRef) =
  let listTarget = opts.get("target")

  # convenience check, in case user is looking for a library
  if listTarget.len > 0 and listTarget notin getTargetNames(pkg):
    var sector: Sector
    echo fmt"{sector=}"
    
    if isInstalled(listTarget):
      sector = private
    elif isAvailable(listTarget):
      sector = public

    opts["library"] = listTarget
    listLibraries(opts, sector)
    return

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

proc list*(opts: Options, pkg: PackageRef) =
  case opts.get("list")
  of "libraries":
    listLibraries(opts, parseEnum(opts.get("level"), private))
  else:
    listTargets(opts, pkg)
