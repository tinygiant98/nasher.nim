import json, os, parsecfg, sequtils, strformat, strutils, tables, uri
import cli, git, manifest, shared

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
## package targets
## 
## Install ======================================
## 
## The library install command is an extenstion of nasher's install command and is fully-backward compatible.
## The command will attempt to install a defined target, however, if the target is not found, available
## libraries will be checked to see if the user is attempting to install a library instead of a target.
## 
##  `nasher install [<library|target>,...] [options]`
## 
## 
## 
## 
## 
## Uninstall ====================================
##  uninstall a library or the entire library system?
## Publish ======================================
##  public/private
## Unpublish ====================================
##  public (private just uses uninstall)
## Update =======================================
##  updates all the cloned library repos (git pull)

## Referencing a library in nasher.cfg:
## Since I'll be adding SM's aliasing capability, we want to use that functionality to also reference libraries.
## Libraries do not require an alias to be defined, but will use the same notation.  Libraries will use nasher's
## normal include/exclude statements to determine which library files to include.
## 
## To reference a library, use the alias functionality:
##    include = "${library-name}/**/*.{nss,json}"
## 
## A more complicated call would be
##    include = "${library-name:release[branch]}/**/*.{nss,json}"
## 
## Other than these flags, all other file inclusion and exclusion rules (glob) apply, so the user should have some
## knowledge of the structure of the library they are including.  If the tag and/or branch referenced in the
## statement does not exist, the user will be prompted with a list of available tags and branches to chooose from.
## If the user selects one of these options, the nasher.cfg will be updated with the choice.  :latest and :#head are
## valid options for the :release entry.  :latest will pick up the latest release; :#head will pick up the latest
## commit.
## 
## Installing a library
## If you reference a library in your nasher.cfg file and that library is not installed, but is available on the
## master library listing, you will be prompted to install the library.  You can also install a public or private
## library manually.  To install a public library:
##    nasher install --[l|library|libraries]:<name>[;<name>...]
## 
## To install a private library, go into the folder which contains the library you want to install.  It must be a
## nasher project and contain a nasher.cfg with the [Package] information filled in:
##    nasher install
## 
## Uninstalling a library
## If you want to remove a library from the list of installed libraries:
##    nasher uninstall --[l|library|libraries]:<name>[;<name>...]
## 
## Updating public libraries.  If not arguments, all libraries and the master listing will be updated.
##    nasher update --[l|library|libraries]:<name>[;<name>...]
##    nasher update --master
##    nasher update
## 
## Handling override files:
## Many public script systems have files that are meant to be edited by the user, such as configuration and creature
## spawn files.  When a library gets updated, these files may be overwritten by the library and wreak havoc on a module.
## To prevent this, ensure library files are the first to be referenced in the list of included files, followed by
## local override versions of these scripts.  Files will be installed in order of inclusion and files lower in the list
## will overwrite files higher on the list.
##    include = "@core-framework/**/*.{nss,json}"
##    include = "src/framework/core_c_config.nss}"
## 
## OR ... library references also work with exclude statements:
##    include = "@core-framework/**/*.{nss,json}"
##    include = "src/framewrok/core_c_config.nss"
##    exclude = "@core-framework/src/core/core_c_config.nss"
## 
## Remove the entire library system.  The user will be prompoted for confirmation since this will delete all public
## libraries.  Private libraries will not be deleted, but can no longer be referenced in nasher.cfg.
##    nasher delete --[l|libraries]
## 
## Publishing a repo as a public library.  From the root folder of the library to be made public, which must containe a
## nasher.cfg file:
##    nasher publish
## 
##    Private repos can't be published, only public repos, however the user will be prompted to ensure they want to conduct
##    this action.  Much like nimble, this action updates the master listing, edits the packages.json file, commits it, then
##    sends a pull request against it.

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

proc getOptionalField(cfg: Config, section, key: string, default = ""): string =
  ## Attempts to obtain the value associated with key in the passed section of configuration
  ## file cfg.  If not found, default is returned.  Handling multiple identical keys is not
  ## supported.
  result = cfg.getSectionValue(section, key)
  
  if result == "":
    result = default

proc getRequiredField(cfg: var Config, section, key: string, prompt = true): string =
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
proc getLibraryDir(library: string): string =
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
proc isUrl(path: string): bool =
  ## Returns whether path is a URL
  # TODO - this is super-hacky.  Find a better way
  # Might fail on something like file://...
  parseUri(path).hostname.len > 0

#Works, but is this the right way? -- change to add?
proc addElements(json: JsonNode, key: string, values: seq[string], absolute = false) =
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
proc removeElements(json: JsonNode, key: string, values: seq[string], absolute = false) =
  ## Removes elements from an array at json[key] if they are in values
  ## absolute = true --> remove all values (set to %[])
  var elements = json[key].getElems()

  if absolute:
    json[key] = %[]
  else:
    elements.keepIf(proc (x: JsonNode): bool = x.getStr() notin values)
    json[key]= %elements

#Works
proc parseReference(pattern: string): Reference =
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

proc filter(j: JsonNode, pred: proc(x: JsonNode): bool {.closure.}): JsonNode {.inline.} =
  ## keeps nodes in j that satisfy pred
  assert j.kind == JObject
  result = newJObject()

  for k, v in j:
    if pred(j[k]):
      result.add(k, v)

proc parseLibrary(): Library =
  ## Populates a Library (type) with data from the nasher.cfg in the current directory.
  ## TODO support hg
  var
    library: Library
    cfg: Config
  
  # TODO modify this to use getPackageRoot without all the errors of including options.nim (circular)
  let file = getCurrentDir() / "nasher.cfg"
   
  if fileExists(file): 
    cfg = loadConfig(getCurrentDir() / "nasher.cfg")
  else:
    fatal(fmt"{file} could not be found.  A valid nasher.cfg is required to publish a library.")

  library.name = cfg.getRequiredField("Package", "name")
  library.path = cfg.getOptionalField("Package", "url")
  library.vcs = 
    # TODO add a gitRepoType function (really, add hg functionality)
    if library.name.getLibraryDir().exists: "git"
    else: "none"
  library.description = cfg.getRequiredField("Package", "description")
  library.license = cfg.getOptionalField("Package", "license")

  # if we changed anything in the config, write it?  This writes anyway, send file to field proc?
  cfg.writeConfig(file)
  result = library

proc delete(installedManifest: var Manifest, library: string) = 
  let path = installedManifest.data[library].fields["path"].getStr()
  if path.isUrl:
    display("Library", fmt"uninstalling public library {library}; associated repo deleted")
    installedManifest.data.delete(library)
    #removeDir(getLibraryDir(library))
  else:
    display("Library", fmt"uninstalling private library {library}; files remain available at {path}, " &
      "but will no longer be accessible as a nasher library.")
    installedManifest.data.delete(library)

proc uninstall(library: string, installedManifest: var Manifest) =
  var parentLibraries = installedManifest.data.filter(proc(x: JsonNode): bool = %library in x.fields["children"])

  ## experiment for uninstalling from the top - this isn't working, need to update a variable in the loop
  var childLibraries = installedManifest.data.filter(proc(x: JsonNode): bool = %library in x.fields["parents"])
  if childLibraries.len > 0:
    warning(fmt"library {library} has dependent libraries and cannot be uninstalled; the following " &
      "libraries must be uninstalled first: " & childLibraries.getElems().join(", "))
    let question = "Do you want to uninstall these libraries?"
    if askIf(question):
      for library in childLibraries:
        uninstall(library.getStr(), installedManifest)

      return #?
  ## end experiment

  if parentLibraries.len > 0:
    for k, v in parentLibraries:
      var elements = v["children"].getElems()
      elements.keepIf(proc (x: JsonNode): bool = x != %library)
      if elements.len > 0:
        installedManifest.data[k].removeElements("children", @[library])
        debug(fmt"reference to {library} removed as child element of {k}")
      else:
        uninstall(k, installedManifest)
        
    if installedManifest.data.hasKey(library):
      installedManifest.delete(library)
  else:
    installedManifest.delete(library)

proc uninstall*(library: string) =
  var 
    file = getLibrariesDir() / installedLibraries
    installedManifest = parseLibraryManifest(file)

  uninstall(library, installedManifest)
  #installedManifest.write(target = file)

proc install(library: Library, manifest: var Manifest, sector: Sector = private) =
  ## Installs library into manifest as a sector library.  Called directly for private
  ## library installs, called from overloaded `install` for public library installations.
  let file = getLibrariesDir() / installedLibraries

  manifest.add(library)
  manifest.write(target = file)

  if library.name.isInstalled:
    success(fmt"{library.name} successfully installed as a {sector} library")
  else:
    fatal(fmt"{library.name} could not be installed.  File a bug report at ...")  

#Works
proc install(name: string, parent = "") =
  ## For use when installing public libraries.  Creates the target folder for the repository,
  ## clones the repo into the target folder and inserts an entry into "installed.json".  If repo
  ## cannot be cloned, throws a non-fatal error.  Checks for library dependencies and installs
  ## those libraries if they are available.
  
  let
    target = getLibrariesDir() / name
    publicManifest = parseLibraryManifest(getLibrariesDir() / publicLibraries)
    publicLibrary = publicManifest.data[name].to(Library)

  var
    installedManifest = parseLibraryManifest(getLibrariesDir() / installedLibraries)
  
  # This procedure is only for public libraries, so the path has to be a url
  if isUrl(publicLibrary.path):
    # Installing, so don't want to keep any old files, if there are any
    removeDir(target)
    
    display("Installing", fmt"library {name} from {publicLibrary.path}")
    # Clone it
    gitClone(getLibrariesDir(), publicLibrary.path, publicLibrary.name)
    # Put it on the "installed.json" manifest
    # Maybe I should call this overloaded install method "list" instead, since that's what it does
    publicLibrary.install(installedManifest, sector = public)

    # parent only passed if this is a dependency, add parent listing for an easy reference
    # later when unistalling so we know if this library is a dependency of more than one other
    # library --> then prompt for removal and warning for other libraries not working, or ...
    # leave it there and info/display that it wasn't removed because of dependencies (probably better)
    if parent.len > 0:
      # TODO I've used this sequence at least three times so far, put it into a procedure
      installedManifest.data[publicLibrary.name].addElements(key = "parents", values = @[parent])
      # maybe not write this here and just pass the continuously modify manifest around until it's done?
      installedManifest.write(target = getLibrariesDir() / installedLibraries)

    # See if a nasher.cfg exists in the new repo, if so, parse for dependencies, check if they're on the
    # primary listing and, if so, install, and repeat.
    withDir(getLibrariesDir() / publicLibrary.name):
      var
        cfg: Config
        reference: Reference
        #instLibrary: Library
        children: seq[string]

      if fileExists(getCurrentDir() / "nasher.cfg"):
        cfg = loadConfig(getCurrentDir() / "nasher.cfg")

        ## This section is my first attempt, using a dependencies section in nasher.cfg.  This can work,
        ## but since we're already bought into the `include = "@library:tag[branch]"` construct, let's use
        ## that.  A library that is based on another library should have these includes anyway.
        #if cfg.hasKey("Dependencies") and cfg["Dependencies"].hasKey("requires"):
        #  for key, value in cfg["Dependencies"]:
        #    if key == "requires":
        #      if value.isAvailable and not value.isInstalled:
        #        debug("Library", fmt"attempting to install {value} as a dependency of {library.name}")
        #        value.install
        #      else:
        #        error(fmt"could not install library {value} as a dependency of {library.name}; " &
        #                 "the library is either not published or already installed.")
        #else:
        #  debug("Library", fmt"{library.name} has no dependencies listed in its nasher.cfg")

        ## This is the second attempt, using the [Sources] section, which already exists.  We'll just have to
        ## assume that the main [Sources] is where the libraries would be located. Can't do much if they
        ## have a bunch of crap in the targets.  We have to have a starndard at some point.  Maybe explicit
        ## dependencies is the way to go.  If so, change the `include =` construct to an explicity dependencies
        ## section.  Also, probably move this to a function to also be used by and `update libraries` process
        if cfg.hasKey("Sources"):
          for key, value in cfg["Sources"]:
            if key == "include":
              reference = value.parseReference
              if reference.library.isAvailable and not reference.library.isInstalled:
                debug("Library", fmt"attempting to install {reference.library} as a dependency of {publicLibrary.name}")
                reference.library.install(parent = publicLibrary.name)   #recursion
                children.add(value)
              else:
                error(fmt"could not install library {reference.library} as a dependency of {publicLibrary.name}; " &
                         "the library is either not published publicly or is already installed.")

          # TODO split these out, don't need repeated code
          if children.len > 0:
  
            # installedManifest was changed during the earlier install (since the last read), so read it again
            installedManifest = parseLibraryManifest(getLibrariesDir() / installedLibraries)
            # add the children elements
            installedManifest.data[publicLibrary.name].addElements(key = "children", values = children, absolute = true)
            # rewrite the file
            installedManifest.write(target = getLibrariesDir() / installedLibraries)
          else:
            installedManifest = parseLibraryManifest(getLibrariesDir() / installedLibraries)
            # delete the children elements
            installedManifest.data[publicLibrary.name].removeElements(key = "children", values = @[], absolute = true)
            installedManifest.write(target = getLibrariesDir() / installedLibraries)
        else:
          debug("Library", fmt"{publicLibrary.name} has no dependencies listed in its nasher.cfg")
      else:
        debug("Library", fmt"{publicLibrary.name} has no nasher.cfg file")
  else:
    debug("Library", "public `install` function called without valid URL as its path")
    fatal("An unknown error has occurred ...")

#TODO, works to "publish" a private library (local machine), but need a process similar to nimble to publish
# a public library.  Need to learn more about interfacing with GitHub before I can finish this.
proc publishLibrary*(sector: Sector) =
  ## Publish a private or public library
  let 
    installed = getLibrariesDir() / installedLibraries

  var
    library = parseLibrary()
    libraries = parseLibraryManifest(installed)

  case sector
  of private:
    library.path = getCurrentDir().replace("\\", "/")
    
    if library.name.isInstalled:
      if askIf(fmt"A library named {library.name} is already installed.  Do you want to overwrite " &
              "the installed library with this library?"):
        library.install(libraries)
        success(fmt"installed library {library.name} overwritten")
      else:
        fatal(fmt"User elected to end operation; library {library.name} not published.")
    else:
      library.install(libraries)
  of public:
    if library.vcs == "none":
      if askIf("This project must be a vcs repository to publish publicly. " &
              "Do you want to publish privately?"):
        publishLibrary(private)
        return
      else:
        fatal(getCurrentDir() & " is not a vcs repository and cannot be published publicly.")
    elif library.vcs == "git":
      if library.path.isUrl:
        #see if we're going to use it or the git's
        if gitRemote() == library.path:
          # gitRemote and library.path in nasher.cfg are the same
          # publish with that url
          if library.name.isInstalled:
            if askIf(fmt"A library named {library.name} is already installed.  Do you want to overwrite " &
                    "the installed library with this library?"):
              library.install(libraries)
              success(fmt"installed library {library.name} overwritten")
            else:
              fatal(fmt"user elected to end operation; library {library.name} not published.")
          else:
            library.install(libraries)  # is this right?

#Works
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
            reference.library.install
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
