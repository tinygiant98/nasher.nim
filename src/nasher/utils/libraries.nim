import json, os, parsecfg, sequtils, strformat, strutils, tables, uri
import cli, git, manifest

## Libraries Implementation
## 
## Init =========================================
## 
## The library init command is an extension of nasher's init command and maintain full backward compatibility.
## Init runs along with nasher init, or can be run separately if a nasher project has already been initialized in
## the target folder
##  
##  `nasher init -l|lib|library|libraries`
## 
## Init clones the main packages repo that contains the updated packages.json and creates an empty installed.json
## in the user's config folder (same folder the global user.cfg is maintained)
## 
## List =========================================
## 
## The library list command is an extension of nasher's list command for package targets.  To list libraries, run
## 
##  `nasher list -l|lib|library|libraries[:<library>] [--public|private] [--quite|verbose|debug]`
##    -l|lib|library|libraries without a library value will list all available libraries in the passed sector
##    [:<library>] will limit the list to just the desired library, if it exists
##    --public will list all libraries in the public listing (packages.json)
##    --private will list all libraries in the installed listing (installed.json)
##    
##    no verbosity argument will list the library name, path and description
##    --quiet will list only the library name
##    --verbose will list the library name, path, description, vcs method, and license
## 
## Running `nasher list` without a -l|... argument will run the original list command for
## package targets.  Running `nasher list <target>` with an invalid target will invoke a convenience function
## to search for a library with the same name as <target>, making -l:<target> and <target> interchangeable unless
## there is a target with the same name as a library, in which case the target will take priority.  The library
## list command does not support repeating names.
## 
## Install ======================================
## 
## The library install command is an extension of nasher's install command and is fully-backward compatible.
## The command will attempt to install a defined target, however, if the target is not found, available
## libraries will be checked to see if the user is attempting to install a library instead of a target.
## 
##  `nasher install [-l:][<target>[,...]|<library>] [options]`
## 
## Dependencies listed for the installed library will be installed before the library.  Parent and Child fields
## will be updated upon installation.
## 
## Uninstall ====================================
## 
## Uninstalls the specified library.  No action taken if a library is not specified.  Convenience function added
## to allow library to be specified just like a <target>, without the -l.  If a library has other libraries that
## depend on it, user will be prompted to uninstall those libraries.  Any parent libraries that have no other
## dependencies will also be uninstalled.
## 
##  `nasher uninstall [-l:]<library> [options]`
##  
## Publish ======================================
##  public/private
## Unpublish ====================================
##  public (private just uses uninstall)
## Update =======================================
##  updates all the cloned library repos (git pull)

type
  Sector* = enum
    private
    public

  Reference* = object
    library*: string
    release*: string
    branch*: string

const
  # TODO change library flag to use alias-like system
  libraryFlag = '@'  # change to ${}? see SM's example  incorporate into aliases
  masterFolder* = "__library-master"
  installedLibraries* = "installed.json"
  publicLibraries* = masterFolder / "packages.json"
  masterRepo* = "https://github.com/tinygiant98/packages"  # eventually change this to a repo in SM's github

#Works
proc parseLibraryManifest*(file: string): Manifest =
  ## Parses the passed file into a Manifest type
  result = newManifest(file)
  result.read(file)

#Works
proc newLibraryManifest*(dir, file: string) =
  ## Creates a new library-specific manifest for "installed.json" and inserts an example entry
  let target = dir / file

  if fileExists(target):
    if not askIf(fmt"The installed library manifest file {file} already exists, Do you want to overwrite it?",
                 default = No):
      return  

  var manifest = parseLibraryManifest(file)
  manifest.add(masterFolder, 
               "https://example.com/<username>/<repo>",
               "git",
               "This is an example of an installed library manifest entry.  Removing this entry will " &
                "have no effect on how the library system works, but this file should never be " &
                "edited by hand.",
               "Do whatever the fuck you want license (wtfpl.net)",
               % @[],
               % @[])
  manifest.write(target)

proc getOptionalField*(cfg: Config, section, key: string, default = ""): string =
  ## Attempts to obtain the value associated with key in the passed section of configuration
  ## file cfg.  If not found, default is returned.  Handling multiple identical keys is not
  ## supported.
  result = cfg.getSectionValue(section, key)
  
  if result == "":
    result = default

proc getRequiredField*(cfg: var Config, section, key: string, prompt = true): string =
  ## Attempts to obtain the value associated with key in the passed section of configuration
  ## file cfg.  If not found, throws a fatal error.  Handling multiple identical keys is not
  ## supported
  result = cfg.getSectionValue(section, key)

  if result == "":
    if prompt:
      let question = fmt"A value must be included for this library's {key}.  Please enter a value " &
        fmt"or add a value for {key} in the {section} section of nasher.cfg."
      
      result = ask(question, allowBlank = false)
      cfg.setSectionKey(section, key, result)
    else:
      fatal(fmt"You must include a value for the library's {key}.  Please insert a value " &
            fmt"for {key} in the {section} section of nasher.cfg")

proc getLibrariesDir*(): string =
  ## Returns the base libraries directory (parent folder for all public libraries)
  ## This is where the default library location should be set
  getConfigDir() / "nasher" / "libraries"

#Works
proc getLibraryDir*(library: string): string =
  ## Returns directory for a specified library
  getLibrariesDir() / library

#Works
proc isOnLibraryList(library, file: string): bool =
  ## Determines if library is referenced in file
  parseLibraryManifest(file).data.hasKey(library)

#Works
proc isAvailable*(library: string): bool =
  ## Returns wehther library is on public libraries list
  library.isOnLibraryList(getLibrariesDir() / publicLibraries)

#Works
proc isInstalled*(library: string): bool =
  ## Returns whether library is on installed libraries list
  library.isOnLibraryList(getLibrariesDir() / installedLibraries)

#Works
proc isLibrary(pattern: string): bool =
  ## Return whether pattern references a library
  pattern[0] == libraryFlag

#TODO
proc isUrl*(path: string): bool =
  ## Returns whether path is a URL
  # TODO - this is super-hacky.  Find a better way
  # Might fail on something like file://...
  parseUri(path).hostname.len > 0

#Works, but is this the right way? -- change to add?
proc addElements*(json: JsonNode, key: string, values: seq[string], absolute = false) =
  ## Adds unique values to json[key] array
  ## 
  ## This was originally meant to help create an array list of dependencies from a library
  ## file, however, it might be better to create a JsonNode with {"parentlibrary":"childlibrary:release[branch]"}
  ## This would allow us to checkout a specific release/branch for one parent and different one
  ## when called by a different parent.
  
  ## absolute = true --> set the values, don't add them to the current values

  if absolute:
    json[key] = %values
  else:
    for value in values:
      if %value notin json[key].getElems:
        json[key].add %value

#Works -- change to keepIf?
proc removeElements*(json: JsonNode, key: string, values: seq[string], absolute = false) =
  ## Removes elements from an array at json[key] if they are in values
  ## absolute = true --> remove all values (set to %[])
  var elements = json[key].getElems()

  if absolute:
    json[key] = %[]
  else:
    elements.keepIf(proc (x: JsonNode): bool = x.getStr() notin values)
    json[key]= %elements

proc parseReference*(pattern: string): Reference =
  ## Parse a pattern into a Reference.
  let tokens = split(split(pattern, "/")[0], {'[', ':'})
  var reference: Reference
  
  reference.library = tokens[0][1 .. ^1]
  for token in tokens[1 .. ^1]:
    if token[^1] == ']':
      reference.branch = token[0 .. ^2]
    else:
      reference.release = token

  # TODO probably need to get rid of these defaults.  If an empty string (or maybe "default")
  # is returned, we can then go on to check other sources for a required branch/releease, such
  # as a library's nasher.cfg, if it exists.
  if reference.branch.len == 0 or not reference.branch.exists(reference.library.getLibraryDir):
    reference.branch = "master"

  if reference.release.len == 0:
    reference.release = "latest"
    # TODO check for existence of specified release/tag, if not, then "" or #head

  result = reference

proc filter*(j: JsonNode, pred: proc(x: JsonNode): bool {.closure.}): JsonNode {.inline.} =
  ## keeps nodes in j that satisfy pred
  assert j.kind == JObject
  result = newJObject()

  for k, v in j:
    if pred(j[k]):
      result.add(k, v)

proc parseLibrary*(sector: Sector = private): Library =
  ## Populates a Library (type) with data from the nasher.cfg in the current directory.  Or asks for
  ## the information through prompting if nasher.cfg doesn't exist.
  ## TODO support hg
  var
    library: Library
    cfg: Config

  let 
    file = getCurrentDir() / "nasher.cfg"

  if fileExists(file): 
    cfg = loadConfig(getCurrentDir() / "nasher.cfg")

    library.name = cfg.getRequiredField("Package", "name")
    
    if sector == public:
      let url = cfg.getRequiredField("Package", "url")
      if not url.isUrl():
        fatal(fmt"{url} is not a valid URL; correct the url in nasher.cfg")
      else:
        library.path = url
    else:
      library.path = getCurrentDir()

    library.vcs = 
      if getCurrentDir().exists: "git"
      else: "none"
    library.description = cfg.getRequiredField("Package", "description")
    library.license = cfg.getOptionalField("Package", "license")
    library.parents = %[]
    library.children = %[]

    if cfg.hasKey("Dependencies"):
      for k, _ in cfg["Dependencies"]:
        if k.isAvailable() or k.isInstalled():
          library.parents.add(%k)
        else:
          error(fmt"dependency {k} not found in public or private library listings; skipping")
  else:
    let question = "This folder is not a nasher project, do you want to create a library from this folder?"
    if askIf(question, default = No):
      display("Collecting", "library information")
      let name = ask("Enter a name for this library (no spaces or special characters):", allowBlank = false)
      library.name = name.normalize().split({' ', '\'', '\"', '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '=', '{', '}'}).join()
      
      if sector == public:
        while true:
          let url = ask("URL (required):", allowBlank = false)
          if not url.isUrl():
            error(fmt"{url} is not a valid URL")
          else:
            library.path = url
            break
      else:
        library.path = getCurrentDir()

      library.vcs =
        if getCurrentDir().exists(): "git"
        else: "none"
      library.description = ask("Enter a description for this library (required):", allowBlank = false)
      if library.description.isEmptyOrWhiteSpace():
        fatal("library description is a required entry; aborting")

      library.license = ask("License:", allowBlank = true)
      library.parents = %[]
      library.children = %[]
    
      while true:
        let dependency = ask("Dependency (optional):", allowBlank = true)
        if dependency.isEmptyOrWhiteSpace():
          break

        if dependency.isAvailable() or dependency.isInstalled():
          library.parents.add(%dependency)
        else:
          warning(fmt"dependency {dependency} not found in public or private libraries; libraries must be " &
            "installed or published before they can be referenced as a dependency")
    else:
      error("Library publication cancelled at user request")

  result = library

proc handleLibraries*(patterns: var seq[string], display = true) =
  ## Receives a sequence of patterns (includes and excludes from nasher.cfg) and modifies the library
  ## entries to reference local location (paths) of public and private libraries.  Non-library entries are
  ## passed without modification.
  for pattern in patterns.mitems:
    if isLibrary(pattern):
      let
        reference = pattern.parseReference
        installedManifest = parseLibraryManifest(getLibrariesDir() / installedLibraries)

      if reference.library.isInstalled:
        var
          path = installedManifest.data[reference.library]["path"].getStr()
          tokens = pattern.split('/')
        
        # If the path is a URL, then it's a public library, so get the path to that repo and
        # modify the pattern
        if path.isUrl:
          tokens[0] = getLibraryDir(reference.library).replace("\\", "/")
          if display: display("Library", fmt"using public library {reference.library}")
          
         # checkout the library at the branch and release referenced in the pattern,
         # or, if not, if the library is a dependency of another library, see if it is
         # marked with a specific release/branch.
          
          debug("Library", fmt"sourcing public library {reference.library} from {tokens[0]}")

          #TODO checkout the reference tag/branch
        else:
          # Otherwise it's a private library, get the path and modify the pattern
          tokens[0] = path
          if display: display("Library", fmt"using private library {reference.library}")
          debug("Libray", fmt"sourcing private library {reference.library} from {tokens[0]}")

          # private libraries can also be git repositories, so if user is requesting a branch and/or
          # release on a private library, see if it's a repo.  If not report the error and use the
          # base library, if it exists.

        pattern = tokens.join("/")
      else:
        # Maybe we can install it
        if reference.library.isAvailable:
          if askIf(fmt"The requested library {reference.library} is not installed, but is available. " &
                      "Do you want to install it?", 
                   default = Yes):
            #reference.library.install
            handleLibraries(patterns, display)
          else:
            # Do nothing - is a nasher error thrown if the file isn't found?
            continue

        else:
          warning(fmt"The requested library {reference.library} is not installed and is " &
                     "not listed on the public library listing.  To use this library, " &
                     "you must publish it either privately or publicly.")
          continue

when isMainModule:
  discard
