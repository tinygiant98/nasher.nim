import json, os, strformat, strutils, tables
import utils/[cli, git, libraries, manifest, nwn, options, shared]

const
  helpInstall* = """
  Usage:
    nasher install [options] [<target>...]

  Description:
    Converts, compiles, and packs all sources for <target>, then installs the
    packed file into the NWN installation directory. If <target> is not supplied,
    the first target found in the package will be packed and installed.

    If the file to be installed would overwrite an existing file, you will be
    prompted to overwrite it. The default answer is to keep the newer file.

    The default install location is '~/Documents/Neverwinter Nights' for Windows
    and Mac or `~/.local/share/Neverwinter Nights` on Linux.

  Options:
    --l|lib:<library>  Installs the specified public library
    --clean            Clears the cache directory before packing
    --yes, --no        Automatically answer yes/no to prompts
    --default          Automatically accept the default answer to prompts
    --branch:<branch>  Selects git branch before operation.

  Global Options:
    -h, --help     Display help for nasher or one of its commands
    -v, --version  Display version information

  Logging:
    --debug        Enable debug logging
    --verbose      Enable additional messages about normal operation
    --quiet        Disable all logging except errors
    --no-color     Disable color output (automatic if not a tty)
  """

# TODO add helpPublish

proc installLibrary*(library: Library, manifest: var Manifest, sector: Sector = private) =
  ## Adds library to manifest
  manifest.add(library)

  if manifest.data.hasKey(library.name):
    success(fmt"{library.name} successfully installed as a {sector} library")
  else:
    fatal(fmt"{library.name} could not be installed.")

proc installLibrary*(library: string, installedManifest: var Manifest) =
  ## Installs a pre-defined public library, if available.
  try:
    let
      target = getLibrariesDir() / library
      publicManifest = parseLibraryManifest(getLibrariesDir() / publicLibraries)
      publicLibrary = publicManifest.data[library].to(Library)

    var parents: seq[string]

    if isUrl(publicLibrary.path):
      for parent in publicLibrary.parents:
        parent.getStr().installLibrary(installedManifest)
        parents.add(parent.getStr())
        installedManifest.data[parent.getStr()].addElements(key = "children", values = @[publicLibrary.name])

      if publicLibrary.name.isInstalled():
        let question = fmt"{publicLibrary.name} is already installed; keep current version?"
        if askIf(question, default = Yes):
          return
      
      removeDir(target)
      display("Installing", fmt"library {library} from {publicLibrary.path}")
      publicLibrary.path.clone(getLibrariesDir(), publicLibrary.name, throw = true)
      publicLibrary.installLibrary(installedManifest, sector = public)

      installedManifest.data[publicLibrary.name].addElements(key = "parents", values = parents)
    else:
      warning(fmt"{library} cannot be installed as a public library; its path is not a valid url")
  except KeyError:
    fatal(fmt"cannot find target or library named {library}")
  finally:
    installedManifest.write(target = getLibrariesDir() / installedLibraries)

proc installParents(library: Library, installedManifest: var Manifest): bool =
  result = true

  for parent in library.parents:
    if not parent.getStr().isInstalled():
      if parent.getStr().isAvailable():
        parent.getStr().installLibrary(installedManifest)
        installedManifest.data[parent.getStr()].addElements(key = "children", values = @[library.name])
      else:
        result = false
        break
    else:
      result = true

proc installTarget(opts: Options, pkg: PackageRef): bool =
  ## Installs a target into installDir
  let
    cmd = opts["command"]
    file = opts["file"]
    dir = opts.getOrPut("installDir", getNwnInstallDir()).expandPath

  if opts.get("noInstall", false):
    return cmd != "install"

  display("Installing", file & " into " & dir)
  if not fileExists(file):
    fatal(fmt"Cannot install {file}: file does not exist")

  if not dirExists(dir):
    fatal(fmt"Cannot install to {dir}: directory does not exist")

  let
    (_, name, ext) = file.splitFile
    fileTime = file.getLastModificationTime
    fileName = name & ext
    installDir =
      case ext
      of ".erf": dir / "erf"
      of ".hak": dir / "hak"
      of ".mod": dir / "modules"
      of ".tlk": dir / "tlk"
      else: dir

  if not dirExists(installDir):
    createDir(installDir)

  let installed = installDir / fileName
  if fileExists(installed):
    let
      installedTime = installed.getLastModificationTime
      timeDiff = getTimeDiff(fileTime, installedTime)
      defaultAnswer = if timeDiff >= 0: Yes else: No

    hint(getTimeDiffHint("The file to be installed", timeDiff))
    if not askIf(fmt"{installed} already exists. Overwrite?", defaultAnswer):
      return ext == ".mod" and cmd != "install" and
             askIf(fmt"Do you still wish to {cmd} {filename}?")

  copyFile(file, installed)
  setLastModificationTime(installed, fileTime)

  if (ext == ".mod" and opts.get("useModuleFolder", true)):
    let
      modFolder = installDir / name
      erfUtil = opts.get("erfUtil")
      erfFlags = opts.get("erfFlags")

    if not dirExists(modFolder):
      createDir(modFolder)

    withDir(modFolder):
      for file in walkFiles("*"):
        file.removeFile

      display("Extracting", fmt"module to {modFolder}")
      extractErf(installed, erfUtil, erfFlags)

  success("installed " & fileName)

  # Prevent falling through to the next function if we were called directly
  return cmd != "install"

proc publish*(opts: Options) =
  ## Publishes a nasher library
  var
    file = getLibrariesDir() / installedLibraries
    installedManifest = parseLibraryManifest(file)
    sector: Sector = parseEnum(opts.get("level", "private"), private)
    library = parseLibrary(sector)
  
  if sector == public:
    #do the PR thing
    discard

  if installParents(library, installedManifest):
    library.installLibrary(installedManifest, sector)
  
  installedManifest.write(target = file)

proc install*(opts: Options, pkg: PackageRef): bool {.discardable.} =
  ## Routing function for installing targets and libraries
  var manifest = parseLibraryManifest(getLibrariesDir() / installedLibraries)

  if opts.get("list") == "libraries":
    installLibrary(opts.get("library"), manifest)
    result = false
  elif opts.get("targets").len > 0 and opts.get("targets") notin getTargetNames(pkg):
    installLibrary(opts.get("targets"), manifest)
    result = false
  else:
    result = installTarget(opts, pkg)
    