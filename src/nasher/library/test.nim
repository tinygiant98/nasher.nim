
import json, os, times, std/sha1
import ../utils/cli

type
  Manifest = object
    file: string
    data: JsonNode

proc newManifest*(file: string): Manifest =
  Manifest(file: file, data: %* {})

proc read*(manifest: var Manifest) =
  let
    path = getCurrentDir() / "installed.json"

  try:
    manifest.data = path.parseFile()
  except IOError:
    manifest.data = %* {}

proc write*(manifest: Manifest) =
  let
    path = getCurrentDir() / "installed.json"

  try:
    createDir(getCurrentDir())
    path.writeFile(manifest.data.pretty)
  except:
    fatal("Could not write to manifest file " & path)

proc parseManifest*(file: string): Manifest =
  result = newManifest(file)
  result.read

proc update*(manifest: var Manifest, fileName, fileSum: string, fileTime: Time) =
  manifest.data[fileName] = %* {"sha1": fileSum, "modified": $fileTime}

proc add*(manifest: var Manifest, library, url, `method`, license, version: string) =
  manifest.data[library] = %* {"url": url, "method":`method`, "license":license, "version":version}

proc delete*(manifest: var Manifest, file: string) =
  if manifest.data.hasKey(file):
    manifest.data.delete(file)

iterator keys*(manifest: Manifest): string =
  for key in manifest.data.keys:
    yield key

var 
  dir = getCurrentDir()
  file = dir / "installed.json"
  manifest = parseManifest(file)

for name, value in manifest.data.pairs:
  echo name & ":" & $value

for key in manifest.keys:
  echo key

manifest.add("daz-stuff", "file://etc/etc", "git", "BSD", "0.1.0")
manifest.write

echo getConfigDir()