import json, os
import ../utils/cli

type
  Manifest* = object
    file*: string
    data*: JsonNode

proc newManifest(file: string): Manifest =
  Manifest(file: file, data: %* {})

proc read(manifest: var Manifest, file: string) =
  try:
    manifest.data = file.parseFile()
  except IOError:
    manifest.data = %* {}

proc write*(manifest: Manifest, file: string) =
  try:
    createDir(splitPath(file).head)
    file.writeFile(manifest.data.pretty)
  except:
    fatal("Could not write to library management file " & splitPath(file).tail)

proc parseManifest*(file: string): Manifest =
  result = newManifest(file)
  result.read(file)

proc add*(manifest: var Manifest, library, url, `method`, license, version: string) =
  manifest.data[library] = %* {"url": url, 
  "method":`method`, "license":license, "version":version}

proc delete*(manifest: var Manifest, file: string) =
  if manifest.data.hasKey(file):
    manifest.data.delete(file)

iterator keys*(manifest: Manifest): string =
  for key in manifest.data.keys:
    yield key
