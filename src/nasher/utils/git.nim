import os, osproc, strformat, strutils, uri
import cli

from shared import withDir

<<<<<<< HEAD
<<<<<<< HEAD
=======
proc gitExecCmd(cmd: string, default = ""): string {.discardable.} =
=======
var lastError: string

proc gitExecCmd(cmd: string, default = ""): string =
>>>>>>> bd8122c... stuff
  ## Runs ``cmd``, returning its output on success or ``default`` on error.
  let (output, errCode) = execCmdEx(cmd)
  if errCode != 0:
    lastError = output.strip
    default
  else:
    # Remove trailing newline
    lastError = ""
    output.strip

>>>>>>> 89d5c54... more work!
proc gitUser*: string =
  ## Returns the configured git username or "" on failure.
  let gitResult = execCmdEx("git config --get user.name")

  if gitResult.exitCode == 0:
    gitResult.output.strip
  else: ""

proc gitEmail*: string =
  ## Returns the configured git email or "" on failure.
  let gitResult = execCmdEx("git config --get user.email")

<<<<<<< HEAD
  if gitResult.exitCode == 0:
    gitResult.output.strip
  else: ""
=======
proc gitPull*(repo = getCurrentDir()) =
  ## pull the repo
  withDir(repo):
    discard gitExecCmd("git pull")

proc gitClone*(dir = getCurrentDir(), repo, target: string) =
  ## clone repo into target under dir
  withDir(dir):
<<<<<<< HEAD
    gitExecCmd("git rev-parse --is-inside-work-tree") != "true"
>>>>>>> 89d5c54... more work!

proc gitRemote*(repo = getCurrentDir()): string =
  withDir(repo):
    let url = execCmdEx("git ls-remote --get-url")
    result = url.output
=======
    discard gitExecCmd("git clone " & repo & " " & target)

proc gitRemote*(repo = getCurrentDir()): string =
  ## Returns the remote for the git project in ``dir``. Supports ssh formatted
  ## remotes.
  withDir(repo):
    result = gitExecCmd("git ls-remote --get-url")
>>>>>>> bd8122c... stuff

    if url.exitCode == 0:
      if result.endsWith(".git"):
        result.setLen(result.len - 4)

      if result.parseUri.scheme == "":
        let ssh = parseUri("ssh://" & result)
        result = ("https://$1/$2$3") % [ssh.hostname, ssh.port, ssh.path]
    else: result = ""

proc gitInit*(repo = getCurrentDir()): bool =
  ## Initializes dir as a git repository and returns whether the operation was
  ## successful. Will throw an OSError if dir does not exist.
  withDir(repo):
    execCmdEx("git init").exitCode == 0

proc empty(repo: string): bool =
<<<<<<< HEAD
  ## Check if repo has any commits
  withDir(repo):
    execCmdEx("git branch --list").output.strip == ""

proc exists(repo: string): bool =
  ## Check for repo existence
  withDir(repo):
    execCmdEx("git rev-parse --is-inside-work-tree").output.strip == "true"

proc exists(branch: string, repo: string): bool =
  ## Check for branch existence
  withDir(repo):
    execCmdEx(fmt"git show-ref --verify refs/heads/{branch}").exitCode == 0
  
proc branch(repo: string, default = ""): string =
  ## Gets the current repo branch
  withDir(repo):
    execCmdEx("git rev-parse --abbrev-ref HEAD").output.strip

proc checkout(branch: string, repo: string, create = false, throw = false): bool = 
  ## Checkout desired branch, if it exists. If not, prompts for creation or
  ## uses of current branch. If can't checkout because of an error, do something else?
  var
    flag = ""
    suffix = ""
  
  if create:
    flag = "-b "
    if repo.branch != "master" and not repo.empty and "master".exists(repo):
      const
        choiceMaster = "Create branch from master"
        choiceCurrent = "Create branch from current branch"
        choiceQuit = "Abort the operation"
        
      let 
        question = fmt"This operation will create a branch from {repo.branch} instead of master. What would you like to do?"
        choices = [choiceMaster, choiceCurrent, choiceQuit]

      case choose(question, choices)
      of choiceMaster:
        suffix = " master"
      of choiceQuit:
        quit(QuitSuccess)

  withDir(repo):
    let gitResult = execCmdEx(fmt"git checkout {flag}{branch}{suffix}")

    result = gitResult.exitCode == 0
    if not result and throw:
      error(gitResult.output)

proc create(repo: string, branch: string):bool =
  ## Wrapper function for checkout; creates a new git branch in repo
  branch.checkout(repo, create = true)
=======
  ## Determines whether a specified repo has had any commits
  withDir(repo):
    gitExecCmd("git branch --list", "none").len == 0

proc exist*(tag: string): bool =
  ## Determines whether a specified tag/release exists
  echo tag

proc exists*(repo: string): bool =
  ## Determine whether a specified repo exists
  withDir(repo):
    gitExecCmd("git rev-parse --is-inside-work-tree") == "true"

proc exists*(branch: string, repo: string): bool =
  ## Determines whether a specified branch exits
  withDir(repo):
    gitExecCmd("git show-ref --verify refs/heads/" & branch, "error") != "error"

proc checkout(branch: string, repo: string, create = false): bool = 
  # Checkout desired branch, if it exists.  If not, prompts for creation or
  # uses of current branch.  If can't checkout because of an error, do something else?
  if create:
    withDir(repo):
      gitExecCmd("git checkout -b " & branch, "error") != "error"
  else:
    withDir(repo):
      gitExecCmd("git checkout " & branch, "error") != "error"

proc branch(repo: string, default = ""): string =
  ## Returns the name of the curretly checked-out branch
  withDir(repo):
    gitExecCmd("git rev-parse --abbrev-ref HEAD", default)

proc create(repo: string, branch: string):bool =
  ## Wrapper function for checkout; creates a new git branch in repo
  branch.checkout(repo, true)
>>>>>>> bd8122c... stuff

proc gitSetBranch*(repo = getCurrentDir(), branch: string): string =
  ## Called if the branch option was specified in configuration or command line
  if repo.exists:
    if branch.exists(repo):
      if repo.branch == branch:
        result = branch
      else:
<<<<<<< HEAD
        if branch.checkout(repo, throw = true):
          result = repo.branch
        else:
          fatal(fmt"{branch} could not be checked out. Resolve all git repo errors before continuing.")
=======
        if branch.checkout(repo):
          result = repo.branch
        else:
          error(lastError)
          fatal(fmt"You must resolve the git repo error before you can continue on branch {branch}")
>>>>>>> bd8122c... stuff
    else:
      if repo.empty:
        let question = "Nasher cannot determine the status of this repo because there have not been any commits. " &
                       fmt"Continue the operation on branch {branch}?"

        if askIf(question):
          if repo.create(branch): 
            if branch != "master":
              warning("check repo structure, orphan branch may have been created")

            result = branch
          else: fatal(fmt"branch {branch} could not be created")
        else:
          fatal("operation aborted by user")
      else:
        if repo.create(branch): result = branch
  else:
<<<<<<< HEAD
    result = "this folder is not a vcs repository"
=======
    result = "this folder is not a git repository"
>>>>>>> bd8122c... stuff

proc gitIgnore*(repo = getCurrentDir(), force = false) =
  ## Creates a .gitignore file in ``dir`` if one does not already exist or if
  ## ``force`` is true. Will throw an OSError if ``dir`` does not exist.
  const
    file = ".gitignore"
    text = """
    # Ignore packed files
    *.erf
    *.hak
    *.mod
    *.tlk

    # Ignore the nasher directory
    .nasher/
    """
  if force or not fileExists(repo / file):
<<<<<<< HEAD
    writeFile(repo / file, text.unindent(4))
=======
    writeFile(repo / file, text.unindent(4))
>>>>>>> bd8122c... stuff
