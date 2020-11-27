import json, os, sequtils, strformat, strutils, tables
import utils/[cli, libraries, manifest, options]

const
  helpUninstall* = """
  Usage:
    nasher uninstall [options]

  Description:
    Uninstalls the specified library.

  Options:
    --default      Automatically accept the default answers to prompts

  Global Options:
    -h, --help     Display help for nasher or one of its commands
    -v, --version  Display version information

  Logging:
    --debug        Enable debug logging
    --verbose      Enable additional messages about normal operation
    --quiet        Disable all logging except errors
    --no-color     Disable color output (automatic if not a tty)
  """
proc delete(installedManifest: var Manifest, library: string) = 
  let path = installedManifest.data[library].fields["path"].getStr()
  if path.isUrl:
    display("Library", fmt"uninstalling public library {library}")
    installedManifest.data.delete(library)
    removeDir(getLibraryDir(library))

    if not dirExists(getLibraryDir(library)):
      success(fmt"{library} uninstalled; associated files removed")
    else:
      error(fmt"{library} could not be uninstalled")
  else:
    display("Library", fmt"uninstalling private library {library}; files remain available at {path}, " &
      "but will no longer be accessible as a nasher library.")
    installedManifest.data.delete(library)

proc uninstall(library: string, installedManifest: var Manifest) =
  var
    parentLibraries = installedManifest.data.filter(proc(x: JsonNode): bool = %library in x.fields["children"])
    childLibraries = installedManifest.data.filter(proc(x: JsonNode): bool = %library in x.fields["parents"])
    childKeys: seq[string]

  if childLibraries.len > 0:
    for key in childLibraries.keys:
      childKeys.add(key)

    warning(fmt"library {library} has dependent libraries and cannot be uninstalled; the following " &
      "libraries must be uninstalled first: " & childKeys.join(", "))
    
    let question = "Do you want to uninstall these libraries?"
    if askIf(question, default = No):
      for key in childKeys:
        if installedManifest.data.hasKey(key):
          key.uninstall(installedManifest)
    else:
      return
      
  if parentLibraries.len > 0:
    for k, v in parentLibraries:
      var elements = v["children"].getElems()
      elements.keepIf(proc (x: JsonNode): bool = x != %library)
      
      if elements.len > 0:
        installedManifest.data[k].removeElements("children", @[library])
      else:
        installedManifest.delete(k)
        
    if installedManifest.data.hasKey(library):
      installedManifest.delete(library)
  else:
    if installedManifest.data.hasKey(library):
      installedManifest.delete(library)

proc uninstall*(opts: Options) =
  let library = opts.get("target")

  var 
    file = getLibrariesDir() / installedLibraries
    installedManifest = parseLibraryManifest(file)

  uninstall(library, installedManifest)
  installedManifest.write(target = file)
