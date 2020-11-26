import os, strformat
import utils/[cli, git, libraries, options]

const
  helpInit* = """
  Usage:
    nasher init [options] [<dir> [<file>]]

  Description:
    Initializes a directory as a nasher project. If supplied, <dir> will be
    created if needed and set as the project root; otherwise, the current
    directory will be the project root.

    If supplied, <file> will be unpacked into the project root's source tree.

  Options:
    --default      Automatically accept the default answers to prompts
    --l|library    Initializes the library system

  Global Options:
    -h, --help     Display help for nasher or one of its commands
    -v, --version  Display version information

  Logging:
    --debug        Enable debug logging
    --verbose      Enable additional messages about normal operation
    --quiet        Disable all logging except errors
    --no-color     Disable color output (automatic if not a tty)
  """

proc init*() =
  ## Initializes the library system by creating the folder all public libraries will be stored
  ## in and creating an example installed.json.  Called during the nasher init process, but can
  ## be called separately.
  display("Initializing", "library system")

  if not existsOrCreateDir(getLibrariesDir()):
    debug("Cloning", fmt"master package repo into {getLibrariesDir() / masterFolder}")
    gitClone(getLibrariesDir(), masterRepo, masterFolder)
    newLibraryManifest(getLibrariesDir(), installedLibraries)
  else:
    error("library system was previously installed, no action taken")
    return

  if dirExists(getLibrariesDir() / masterFolder):
    success("initialized library system")
  else:
    error("The library system could not be initialized")

proc init*(opts: Options, pkg: PackageRef): bool =
  ## Initializes a nasher project
  case opts.get("list")
  of "libraries":
    init()
  else:
    let
      dir = opts.getOrPut("directory", getCurrentDir())
      file = dir / "nasher.cfg"

    if fileExists(file):
      fatal(dir & " is already a nasher project")

    display("Initializing", "into " & dir)

    try:
      display("Creating", "package file at " & file)
      createDir(dir)
      writeFile(file, genPackageText(opts))
      success("created package file")
    except:
      fatal("Could not create package file at " & file)

    # TODO: support hg
    if opts.getOrPut("vcs", "git") == "git":
      try:
        display("Initializing", "git repository")
        if gitInit(dir):
          gitIgnore(dir)
        success("initialized git repository")
      except:
        error("Could not initialize git repository: " & getCurrentExceptionMsg())

    if askif("Initializing the library system will clone the nasher repo " & 
            "containing the list of public libraries.  Do you want to continue?", default = Yes):
      init()
    else:
      display("Skipping", "library system")

    success("project initialized")

    # Check if we should unpack a file
    if opts.hasKey("file"):
      opts.verifyBinaries
      result = true
