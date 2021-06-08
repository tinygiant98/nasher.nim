import os, git, githubapi, strformat, json, uri, libraries, strutils, shared
import std/[options]

echo masterRepo.split("/").pop()
let parts = masterRepo.split("/")
echo parts
echo masterRepo.parseUri().hostname
echo masterRepo.parseUri().path

echo masterRepo.splitPath().head.parseUri().path
echo masterRepo.splitPath().tail
echo masterRepo.splitPath().head.splitPath().tail

when false:
  var auth: Option[Auth]

  let mode = 1

  auth = some(Auth())
  echo fmt"Some: {isSome(auth)}"
  auth = none(Auth)
  echo fmt"None: {isNone(auth)}"

  case mode
  of 1:
    var newauth = getAuth()
    if newauth.isSome():
      echo $apiGetContent(newauth, "tinygiant98", "nasher.nim", "full_name")
  of 2:
    auth = none(Auth)
    echo $apiGetContent(auth, "tinygiant98", "nasher.nim", "full_name")
  else:
    discard
