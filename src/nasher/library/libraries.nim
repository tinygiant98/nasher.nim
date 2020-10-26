import json, os, strformat, strutils, uri
import manifest, ../utils/cli

const
  libraryFlag = '@'
  installedLibraries = "installed.json"
  availableLibraries = "available.json"

proc getLibrariesDir(): string =
  getConfigDir() / "nasher" / "libraries"

proc getLibraryDir(library: string): string =
  getLibrariesDir() / library

proc isOnLibraryList(library, file: string): bool =
  parseManifest(file).data.hasKey(library)

proc isAvailable(library: string): bool =
  library.isOnLibraryList(getLibrariesDir() / availableLibraries)

proc isInstalled(library: string): bool =
  library.isOnLibraryList(getLibrariesDir() / installedLibraries)

proc isLibrary(element: string): bool =
  element[0] == libraryFlag

proc parseLibraryName(library: string): string =
  var
    folder = '/'
    version = ':'
    tokens = library.split({folder, version})

  result = tokens[0].replace($libraryFlag, "")
    
proc handleLibraries*(patterns: var seq[string]): seq[string] =
  for pattern in patterns.mitems:
    if isLibrary(pattern):
      let
        library = pattern.parseLibraryName
        file = getLibrariesDir() / installedLibraries
        libraries = parseManifest(file)
        
      echo libraries.data.kind
      if library.isInstalled:
        var
          path = libraries.data[library]["path"].getStr
          split = pattern.split('/')
          url: Uri
        
        # if the path is a url, we need to convert it to local pathing
        url = parseUri(path)
        if url.hostname.len == 0:
          # Local library
          split[0] = path
        else:
          # Installed library
          split[0] = getLibraryDir(library)
          split[0] = join(split(split[0], "\\"), "\\\\")
          echo "joined up?: " & split[0]

        pattern = split.join("/")
        echo pattern
      else:
        # Maybe we can install it
        if library.isAvailable:
          if askIf(fmt"The requested library {library} is not installed, but is available. " &
                    "Do you want to install it?", default = Yes):
            echo "stuff"
          else:
            # Do nothing - is a nasher error thrown if the file isn't found?
            continue

        else:
          warning(fmt"The requested library {library} is not installed and is " &
                    "not listed on the master library listing.  To use this library, " &
                    "you must publish it either locally or publicly.")
          continue

var includes = @["@daz-stuff:latest/**/*.{json}","@core-framework/**/*.{nss,json}"]
discard handleLibraries(includes)
  






