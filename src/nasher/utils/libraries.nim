import json, os, parsecfg, strformat, strutils, uri
import cli, git, manifest

## Nasher Libraries Implementation
## 
## This system allows for publication of two types of libraries: private and public.  Private libraries
## are those that only exist on the local system.  Public libraries exist as code repositories.  The types
## of files in these repositories is not limited to nwn gff files.
## 
## Referencing a library in nasher.cfg:
## This library implementation uses nasher's normal include/exclude statements to determine which library
## files to include.  To reference a library, use the libraryFlag "@" as the first character.  You can also
## reference a releast with a ":" and a specific branch in square brackets.  So the simplest library call
## would be
##    include = "@library-name/**/*.{nss,json}"
## 
## A more complicated call would be
##    include = "@library-name:release[branch]/**/*.{nss,json}"
## 
## Other than these flags, all other file inclusion and exclusion rules (glob) apply, so the user should have some
## knowledge of the structure of the library they are including.  If the tag and/or branch referenced in the
## statement does not exist, the user will be prompted with a list of available tags and branches to chooose from.
## If the user selects one of these options, the nasher.cfg will be updated with the choice.  :latest and :#head are
## valid options for the :release entry.  :latest will pick up the latest release; :#head will pick up the latest
## commit.
## 
## Initializing
## If initializing nasher in a new folder, library initialization will be included as a optional prompt during
## the initialization process.  Initializing the library system clones the master library repo and creates an
## empty ``installed.json`` file in the libraries folder.  This file should not be edited by hand.
## 
## If a nasher project is already initialized you can initialize just the library system with the command
##    nasher init [--l|--libraries]
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
## Listing installed libraries:
##    nasher list --[l|libraries]
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
  Publish* = enum
    private
    public

  Reference* = object
    library*: string
    release*: string
    branch*: string

const
  libraryFlag = '@'
  masterFolder = "__library-master"
  installedLibraries = "installed.json"
  publicLibraries = masterFolder / "packages.json"
  masterRepo = "https://github.com/tinygiant98/packages"

proc parseLibraryManifest(file: string): Manifest =
  ## Parses the passed file into a Manifest type
  result = newManifest(file)
  result.read(file)

proc newLibraryManifest(dir, file: string) =
  ## Creates a new library-specific manifest for "installed.json" and inserts and example entry
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
               "Do whatever the fuck you want license (wtfpl.net)")
  manifest.write(target)

proc getOptionalField(cfg: Config, section, key: string, default = ""): string =
  ## Attempts to obtain the value associated with key in the passed section of configuration
  ## file cfg.  If not found, default is returned.
  result = cfg.getSectionValue(section, key)
  
  if result == "":
    result = default

proc getRequiredField(cfg: Config, section, key: string): string =
  ## Attempts to obtain the value associated with key in the passed section of configuration
  ## file cfg.  If not found, throws a fatal error.
  result = cfg.getSectionValue(section, key)

  if result == "":
    fatal(fmt"You must include a value for the library's {key}.  Please insert a value " &
          fmt"for {key} in the {section} section of nasher.cfg")

proc getLibrariesDir(): string =
  ## Returns the base libraries directory (parent folder for all libraries)
  getConfigDir() / "nasher" / "libraries"

proc getLibraryDir(library: string): string =
  ## Returns directory for a specified library
  getLibrariesDir() / library

proc isOnLibraryList(library, file: string): bool =
  ## Determines if library is referenced in file
  parseLibraryManifest(file).data.hasKey(library)

proc isAvailable(library: string): bool =
  ## Returns wehther library is on public libraries list
  library.isOnLibraryList(getLibrariesDir() / publicLibraries)

proc isInstalled(library: string): bool =
  ## Returns whether library is on installed libraries list
  library.isOnLibraryList(getLibrariesDir() / installedLibraries)

proc isLibrary(pattern: string): bool =
  ## Return whether pattern references a library
  pattern[0] == libraryFlag

proc isUrl(path: string): bool =
  ## Returns whether parh is a URL
  # TODO - this is super-hacky.  Find a better way
  # Might fail on something like file://...
  parseUri(path).hostname.len > 0

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

  if reference.branch.len == 0:
    reference.branch = "master"
    # TODO check for existence of specified branch

  if reference.release.len == 0:
    reference.release = "latest"
    # TODO check for existence of specified release/tag

  result = reference

proc parseLibrary(): Library =
  ## Populates a Library (type) with data from the nasher.cfg in the current directory.
  ## TODO support hg
  var
    library: Library
    cfg: Config
  
  let file = getCurrentDir() / "nasher.cfg"
   
  if fileExists(file): 
    cfg = loadConfig(getCurrentDir() / "nasher.cfg")
  else:
    fatal(fmt"{file} could not be found.  A valid nasher.cfg is required to publish a library.")

  library.name = cfg.getRequiredField("Package", "name")
  library.path = cfg.getOptionalField("Package", "url")
  library.vcs = 
    if gitRepo(): "git"
    else: "none"
  library.description = cfg.getRequiredField("Package", "description")
  library.license = cfg.getOptionalField("Package", "license")

  result = library

proc install(library: Library, libraries: var Manifest, publish: Publish = private) =
  # adds the library to the installed manifest, does not clone, usually directly called for private
  # library publishing/installation

  # called by overloaded install for public installation after clone
  let libraryManifest = getLibrariesDir() / installedLibraries

  libraries.add(library)
  libraries.write(target = libraryManifest)

  if library.name.isInstalled:
    success(fmt"Huzzah! {library.name} was successfully installed as a {publish} library")
  else:
    fatal(fmt"{library.name} could not be installed.  File a bug report at ...")  

proc install(name: string) =
  ## For use when installing public libraries.  Creates the target folder for the repository,
  ## clones the repo into the target folder and inserts an entry into "installed.json".  If repo
  ## cannot be cloned, throws a non-fatal error.
  
  # TODO check for dependencies after clone - should be in nasher.cfg
  # Add a section to nasher.cfg ([Dependecies] or [Library]?) to identify dependencies.  Dependencies
  # should be cloned and, when required, added to the include, exclude patterns during processing

  let
    target = getLibrariesDir() / name
    publicManifest = parseLibraryManifest(getLibrariesDir() / publicLibraries)
    library = publicManifest.data[name].to(Library)

  var
    installedManifest = parseLibraryManifest(getLibrariesDir() / installedLibraries)
  
  if isUrl(library.path):
    removeDir(target)
    
    display("Installing", fmt"library {name} from {library.path}")
    gitClone(getLibrariesDir(), library.path, library.name)
    library.install(installedManifest)
    
proc initLibraries*() =
  ## Initializes the library system by creating the folder all public libraries will be stored
  ## in and creating an example installed.json.  Called during the nasher init process, but can
  ## be called separately.
  display("Initializing", "library system")

  if not existsOrCreateDir(getLibrariesDir()):
    gitClone(getLibrariesDir(), masterRepo, masterFolder)
    newLibraryManifest(getLibrariesDir(), installedLibraries)
  else:
    warning("library system was previously installed, no action taken")
    return

  if dirExists(getLibrariesDir() / masterFolder):
    success("initialized library system")
  else:
    error("The library system could not be initialized")

proc publishLibrary*(`type`: Publish) =
  ## Publish a private or public library
  let 
    installed = getLibrariesDir() / installedLibraries

  var
    library = parseLibrary()
    libraries = parseLibraryManifest(installed)

  case `type`:
  of private:
    library.path = getCurrentDir().replace("\\", "/")
    
    if library.name.isInstalled:
      if askIf(fmt"A library named {library.name} is already installed.  Do you want to overwrite " &
              "this installed library with this library?"):
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
        fatal(getCurrentDir() & " is not a vcs repository and can't be published publicly.")
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
              fatal(fmt"User elected to end operation; library {library.name} not published.")
          else:
            library.install(libraries)

proc handleLibraries*(patterns: var seq[string], display = true) =
  ## Receives a sequence of patterns (includes and excludes from nasher.cfg) and modifies the library
  ## entries to reference local location (paths) of public and private libraries.  Non-library entries are
  ## passed without modification.
  ## TODO checkout the branch and tag, if passed
  for pattern in patterns.mitems:
    if isLibrary(pattern):
      let
        reference = pattern.parseReference
        installedManifest = parseLibraryManifest(getLibrariesDir() / installedLibraries)

      if reference.library.isInstalled:
        var
          path = installedManifest.data[reference.library]["path"].getStr
          tokens = pattern.split('/')
        
        # If the path is a URL, then it's a public library, so get the path to that repo and
        # modify the pattern
        if path.isUrl:
          tokens[0] = getLibraryDir(reference.library).replace("\\", "/")
          if display: display("Library", fmt"using public library {reference.library}")
          
          reference.checkout(getLibraryDir(reference.library))
          
          debug("Library", fmt"sourcing public library {reference.library} from {tokens[0]}")

          #TODO checkout the reference tag/branch
        else:
          # Otherwise it's a private library, get the path and modify the pattern
          tokens[0] = path
          if display: display("Library", fmt"using private library {reference.library}")
          debug("Libray", fmt"sourcing private library {reference.library} from {tokens[0]}")

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

var something: Reference
something =parseReference("@library-name:release-number[branch-name]/")
something =parseReference("@library-name[branch-name]/")
something =parseReference("@library-name/")
something =parseReference("@library-name[branch-name]:release-number/")
something =parseReference("@library-name:release-number/")
