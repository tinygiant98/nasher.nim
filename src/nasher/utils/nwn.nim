import json, os, osproc, streams, strformat, strutils
import cli

const
  Options = {poUsePath, poStdErrToStdOut}

  GffExtensions* = @[
    "utc", "utd", "ute", "uti", "utm", "utp", "uts", "utt", "utw",
    "git", "are", "gic", "mod", "ifo", "fac", "dlg", "itp", "bic",
    "jrl", "gff", "gui"
  ]

proc gffToJson(file, bin, args: string): JsonNode =
  ## Converts ``file`` to json, stripping the module ID if ``file`` is
  ## module.ifo.
  let
    cmd = join([bin, args, "-i", file, "-k json -p"], " ")
    (output, errCode) = execCmdEx(cmd, Options)

  if errCode != 0:
    fatal(fmt"Could not parse {file}: {output}")

  result = output.parseJson

  ## TODO: truncate floats
  if file.extractFilename == "module.ifo" and result.hasKey("Mod_ID"):
    result.delete("Mod_ID")


proc jsonToGff(inFile, outFile, bin, args: string) =
  ## Converts a json ``inFile`` to an erf ``outFile``.
  let
    cmd = join([bin, args, "-i", inFile, "-o", outFile], " ")
    (output, errCode) = execCmdEx(cmd, Options)

  if errCode != 0:
    fatal(fmt"Could not convert {inFile}: {output}")

proc gffConvert*(inFile, outFile, bin, args: string) =
  ## Converts ``inFile`` to ``outFile``
  let
    (dir, name, ext) = outFile.splitFile
    fileType = ext.strip(chars = {'.'})
    outFormat = if fileType in GffExtensions: "gff" else: fileType

  try:
    createDir(dir)
  except OSError:
    let msg = osErrorMsg(osLastError())
    fatal(fmt"Could not create {dir}: {msg}")

  let category = if outFormat in ["json", "gff"]: "Converting" else: "Copying"
  info(category, "$1 -> $2" % [inFile.extractFilename, name & ext])

  ## TODO: Add gron and yaml support
  case outFormat
  of "json":
    let text = gffToJson(inFile, bin, args).pretty
    writeFile(outFile, text)
  of "gff":
    jsonToGff(inFile, outFile, bin, args)
  else:
    copyFile(inFile, outFile)

proc extractErf*(file, bin, args: string) =
  ## Extracts the erf ``file`` into the current directory.
  let
    cmd = join([bin, args, "-x -f", file], " ")
    (output, errCode) = execCmdEx(cmd, Options)

  if errCode != 0:
    fatal(fmt"Could not extract {file}: {output}")

proc createErf*(files: seq[string], outFile, bin, args: string) =
  ## Creates an file at ``outFile`` from ``files``.
  let
    cmd = join([bin, args, "-c -f", outFile, files.join(" ")], " ")
    (output, errCode) = execCmdEx(cmd, Options)

  if errCode != 0:
    fatal(fmt"Could not pack {outFile}: {output}")
