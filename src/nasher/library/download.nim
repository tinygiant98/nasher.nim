import os, osproc, parseutils, strformat, httpclient
import ../utils/cli
from strutils import splitLines
from ../utils/shared import withDir

type
  VersionControlSource* {.pure.} = enum
    git = "git", hg = "hg"

proc getSpecificDir(source: VersionControlSource): string {.used.} =
  case source
  of VersionControlSource.git:
    ".git"
  of VersionControlSource.hg:
    ".hg"

proc checkout(repo, branch: string, source: VersionControlSource) =
  case source
  of VersionControlSource.git:
    withDir(repo):
      discard execCmd("git checkout --force " & branch)
      discard execCmd("git submodule update --recursive")
  of VersionControlSource.hg:
    withDir(repo):
      discard execCmd("hg checkout " & branch)

proc pull(repo: string, source: VersionControlSource) {.used.} =
  case source
  of VersionControlSource.git:
    repo.checkout("", source)
    withDir(repo):
      discard execCmd("git pull")
      if fileExists(".gitmodules"):
        discard execCmd("git submodule update")
  of VersionControlSource.hg:
    repo.checkout("default", source)
    withDir(repo):
      discard execCmd("hg pull")

proc clone(name, url, dir: string, source: VersionControlSource, branch = "", onlyTip = true) =
  case source
  of VersionControlSource.git:
    let
      depthArg = if onlyTip: "--depth 1 " else: ""
      branchArg = if branch == "": "" else: "-b " & branch & " "

    withDir(dir):
      discard execCmd("git clone --recursive " & depthArg & branchArg & url & " " & name)
  of VersionControlSource.hg:
    let
      depthArg = if onlyTip: "-r tip " else: ""
      branchArg = if branch == "": "" else: "-b " & branch & " "
    
    withDir(dir):
      discard execCmd("hg clone " & depthArg & branchArg & url & " " & name)

proc getTags(repo: string, source: VersionControlSource): seq[string] =
  withDir(repo):
    var output = execProcess("git tag")
    result = @[]
    case source
    of VersionControlSource.git:
      output = execProcess("git tag")
      if output.len > 0:
        for line in output.splitLines():
          if line == "": continue
          result.add(line)
    of VersionControlSource.hg:
      output = execProcess("hg tags")
      if output.len > 0:
        for line in output.splitLines():
          if line == "": continue
          var tag = ""
          discard parseUntil(line, tag, ' ')
          if tag != "tip":
            result.add(tag)

proc getVersionControlSource*(source: string): VersionControlSource =
  case source
  of "git": return VersionControlSource.git
  of "hg": return VersionControlSource.hg
  else:
    fatal(fmt"invalid download method requested: {source}")

proc getVersionControlSourceByUrl*(url: string): VersionControlSource =
  if execCmdEx("git ls-remote " & url).exitCode == QuitSuccess:
    return VersionControlSource.git
  elif execCmdEx("hg identify " & url).exitCode == QuitSuccess:
    return VersionControlSource.hg
  else:
    fatal(fmt"unable to identify version control source by url {url}")

proc getProxy*(options: Options): Proxy =
  ## Returns ``nil`` if no proxy is specified.
  var url = ""
  if ($options.config.httpProxy).len > 0:
    url = $options.config.httpProxy
  else:
    try:
      if existsEnv("http_proxy"):
        url = getEnv("http_proxy")
      elif existsEnv("https_proxy"):
        url = getEnv("https_proxy")
      elif existsEnv("HTTP_PROXY"):
        url = getEnv("HTTP_PROXY")
      elif existsEnv("HTTPS_PROXY"):
        url = getEnv("HTTPS_PROXY")
    except ValueError:
      display("Warning:", "Unable to parse proxy from environment: " &
          getCurrentExceptionMsg(), Warning, HighPriority)

  if url.len > 0:
    var parsed = parseUri(url)
    if parsed.scheme.len == 0 or parsed.hostname.len == 0:
      parsed = parseUri("http://" & url)
    let auth =
      if parsed.username.len > 0: parsed.username & ":" & parsed.password
      else: ""
    return newProxy($parsed, auth)
  else:
    return nil