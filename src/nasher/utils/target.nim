import std/[os, parsecfg, sequtils, streams, strtabs, strutils, tables]

type
  PackageError* = object of CatchableError
    ## Raised when the package parser encounters an error

  Target* = ref object
    opts*: OptionTable
    lists*: ListTable
    variables*: seq[KeyValuePair]
    rules*: seq[Rule]

  OptionTable* = Table[string, string]
  ListTable* = Table[string, seq[string]]
  KeyValuePair* = tuple[key, value: string]
  Rule* = tuple[pattern, dest: string]

const validTargetChars = {'\32'..'\64', '\91'..'\126'} - invalidFileNameChars

const validTargetOpts = @["name", "description", "file", "branch", "parent", "gffFormat", "tlkFormat", "format",
                          "modName", "modMinGameVersion", "modDescription", "nssChunks", "chunks"]

const validTargetLists = @["include", "exclude", "filter", "flags", "group", "skipCompile"]

const defaultTargetKeys = @[
  (keys: @["gffFormat", "tlkFormat"], default: "format"),
  (keys: @["nssChunks"], default: "chunks"),
]

proc raisePackageError(msg: string) =
  ## Raises a `PackageError` with the given message.
  raise newException(PackageError, msg)

proc raisePackageError(p: CfgParser, msg: string) =
  ## Raises a `PackageError` with the given message. Includes file, column, and
  ## line information for the user.
  raise newException(PackageError, "Error parsing $1($2:$3): $4" %
    [p.getFilename, $p.getLine, $p.getColumn, msg])

proc `==`*(a, b: Target): bool =
  result = true
  for _, valA, valB in fieldPairs(a[], b[]):
    if valA != valB:
      return false

proc get*[T](opts: OptionTable, key: string, default: T = ""): T =
  var key = key
  result = default
  
  if not opts.hasKey(key):
    for defaults in defaultTargetKeys:
      if key in defaults.keys:
        key = defaults.default
  
  if opts.hasKey(key):
    try:
      when T is string:
        result = opts[key]
      elif T is bool:
        result = opts[key].toBool
      elif T is int:
        result = opts[key].parseInt
      else:
        raise newException(Defect, "opts.get() is not implemented for type " & $(type(T)) )
    except ValueError:
      discard

proc get*(lists: ListTable, key: string): seq[string] =
  if lists.hasKey(key):
    result = lists[key]

proc filter*(targets: seq[Target], wanted: string): seq[Target] =
  for find in wanted.split(';'):
    if find == "":
      result.add(targets[0])
    elif find == "all":
      return targets
    else:
      let found = targets.filterIt(find == it.opts.get("name") or find in it.lists.get("groups"))
      if found.len == 0:
        raise newException(KeyError, "Unknown target " & find)
      result.add(found)
  result.deduplicate

proc contains(kv: seq[KeyValuePair], key: string): bool =
  for k in kv:
    if k.key == key:
      return true

proc inherit(child: var seq[string], parent: seq[string]) =
  for value in parent:
    if value notin child:
      child.add(value)

proc inherit(child, parent: Target, idx: int) =
  if not child.opts.hasKey("name"):
    raisePackageError("Error: target $1 does not have a name" % $(idx + 1))

  for k, _ in parent.opts.pairs:
    if k notin ["description", "parent"] and not child.opts.hasKey(k):
      child.opts[k] = parent.opts[k]

  for k, _ in parent.lists.pairs:
    if not child.lists.hasKey(k):
      child.lists[k] = parent.lists[k]
    else:
      inherit(child.lists[k], parent.lists[k])

  for rule in parent.rules:
    if rule notin child.rules:
      child.rules.add(rule)

  for (key, value) in parent.variables:
    if key notin child.variables:
      child.variables.add((key, value))

proc resolve(s: var string, variables: StringTableRef) =
  s = `%`(s, variables, {useEnvironment})

proc resolve(items: var seq[string], variables: StringTableRef) =
  for item in items.mitems:
    resolve(item, variables)

proc resolve(rules: var seq[Rule], variables: StringTableRef) =
  for rule in rules.mitems:
    rule.pattern.resolve(variables)
    rule.dest.resolve(variables)

proc resolve(target: Target) =
  ## Resolves all variables in `target`'s fields using the values in
  ## `target.variables`. Missing variables will be filled in by env vars if
  ## available. Otherwise, throws an error.
  let vars = newStringTable()
  for (key, value) in target.variables:
    vars[key] = value

  # These variables should remain constant
  vars["target"] = target.opts.get("name")
  vars["ext"] = "$ext" # This supports $ext in unpack rule destinations

  # Resolve variables (including env vars)
  try:
    for key, val in fieldPairs(target[]):
      case key
      of "opts":
        for k, _ in target.opts.pairs:
          resolve(target.opts[k], vars)
      of "lists":
        for k, _ in target.lists.pairs:
          for i in 0..<target.lists[k].len:
            resolve(target.lists[k][i], vars)
      of "rules":
        resolve(target.rules, vars)
      of "variables":
        discard
  except ValueError as e:
    e.msg.removePrefix("format string: key not found: ")
    raisePackageError("Unknown variable $$$# in target $#" % [e.msg, target.opts.get("name")])

proc add(targets: var seq[Target], target, package: Target, isDefault: bool) =
  ## Resolves variables in `target` using the parent target from `targets` (if
  ## given, `package` if not) to supply default values. Then inserts `target` at
  ## the beginning or end of `targets` depending on `isDefault`.
  let parent =
    if target.opts.get("parent").len > 0:
      targets.filterIt(it.opts.get("name") == target.opts.get("parent"))[0]
    else: package
  target.inherit(parent, targets.len)
  if isDefault:
    targets.insert(target, 0)
  else:
    targets.add(target)

proc add(opts: var OptionTable, key, value: string): bool =
  ## Attempts to add key:value to target.opts if key is contained in validTargetOpts.
  ## Returns true if value was added.
  if key in validTargetOpts:
    opts[key] = value
    result = true

proc add(opts: var OptionTable, kv: tuple[key: string, value: string]) =
  ## Attempts to add key:value to target.opts if key is contained in validTargetOpts.
  if not opts.add(kv.key, kv.value):
    raisePackageError("Invalid opts.key $1" % kv.key)

proc add(lists: var ListTable, key, value: string): bool =
  ## Attempts to add key:value to lists.opts if key is contained in validTargetLists.
  ## Returns true if value was added.
  if key in validTargetLists:
    if not lists.hasKey(key):
      lists[key] = @[]
    lists[key].add(value)
    result = true

proc add(lists: var ListTable, kv: tuple[key: string, value: string]) =
  ## Attempts to add key:value to lists.opts if key is contained in validTargetLists.
  if not lists.add(kv.key, kv.value):
    raisePackageError("Invalid lists.key $1" % kv.key)

proc parseCfgPackage(s: Stream, filename = "nasher.cfg"): seq[Target] =
  ## Parses the content of `s` into a sequence of `Target`s. The cfg package
  ## format is assumed. `filename` is used for error messages only. Raises
  ## `PackageError` if an error is encountered during parsing.
  var
    p: CfgParser
    context, section, defaultTarget: string
    defaults = new Target
    target = new Target
    isDefault: bool

  p.open(s, filename)
  while true:
    var e = p.next
    case e.kind
    of cfgEof:
      if context == "target":
        result.add(target, defaults, isDefault)
        echo "added new target"
      break
    of cfgSectionStart:
      case e.section.toLower
      of "package":
        if section == "package":
          p.raisePackageError("duplicate [package] section")
        elif section.len > 0:
          p.raisePackageError("[package] section must be declared before other sections")
        context = "package"
      of "target":
        case context
        of "package", "":
          defaults = target
        of "target":
          result.add(target, defaults, isDefault)
        else: assert(false)
        target = new Target
        context = "target"
        isDefault = false
      of "sources", "rules", "variables":
        discard
      of "package.sources", "package.rules", "package.variables":
        if context in ["target"]:
          p.raisePackageError("[$1] must be declared within [package]" % e.section)
      of "target.sources", "target.rules", "target.variables":
        if context in ["package", ""]:
          p.raisePackageError("[$1] must be declared within [target]" % e.section)
      else:
        p.raisePackageError("invalid section [$1]" % e.section)

      # Trim context from subsection
      section = e.section.toLower.rsplit('.', maxsplit = 1)[^1]
    of cfgKeyValuePair, cfgOption:
      case section
      of "package", "target":
        case e.key
        of "default":
          case section
          of "package":
            defaultTarget = e.value
          of "target":
            try:
              isDefault = e.value.parseBool
            except ValueError:
              p.raisePackageError("value of target.default must be a boolean")
        of "name":
          if section == "target":
            if e.value in ["", "all"]:
              p.raisePackageError("invalid target name \"$1\"" % e.value)
            for c in e.value:
              if c notin validTargetChars:
                p.raisePackageError("invalid character $1 in target name $2" %
                                    [escape($c), e.value.escape])
            if result.anyIt(it.opts.get("name") == e.value):
              p.raisePackageError("duplicate target name $1" % e.value.escape)
            else:
              target.opts.add((e.key, e.value))
              isDefault = isDefault or target.opts.get("name") == defaultTarget
        of "parent":
          if not result.anyIt(it.opts.get("name") == e.value):
            p.raisePackageError("unknown parent target $1" % e.value.escape)
          target.opts.add((e.key, e.value))
        of "nssChunks", "chunks":
          try:
            discard e.value.parseInt()
            target.opts.add((e.key, e.value))
          except ValueError:
            p.raisePackageError("value of target.$1 must be an integer" % e.key.escape)
        of "gffFormat", "tlkFormat", "format":
          if e.value notin GffFormats:
            p.raisePackageError("invalid format \"$2\"" % e.value.escape)
        of "source": target.lists.add(("include", e.value))
        of "version", "url", "author": discard
        else:
          if not target.opts.add(e.key, e.value) and not target.lists.add(e.key, e.value):
          # For backwards compatibility, treat any unknown keys as unpack rules.
          # Unfortunately, this prevents us from detecting incorrect keys, so
          # nasher may work unexpectedly. In the future, we will issue a
          # deprecation warning here.
            target.rules.add((e.key, e.value))
      of "sources":
        case e.key
        of "include", "exclude", "filter", "skipCompile":
          target.lists.add((e.key, e.value))
        else:
          p.raisePackageError("invalid key $1 for section [$2$3]" %
            [e.key.escape, if context.len > 0: context & "." else: "", section])
      of "rules":
        target.rules.add((e.key, e.value))
      of "variables":
        target.variables.add((e.key, e.value))
      else:
        discard
    of cfgError:
      p.raisePackageError(e.msg)
  close(p)
  result.apply(resolve)

proc parsePackageString*(s: string, filename = "nasher.cfg"): seq[Target] =
  ## Parses `s` into a series of targets. The parser chosen is based on
  ## `filename`'s extension'.
  let stream = newStringStream(s)
  case filename.splitFile.ext
  of ".cfg":
    result = parseCfgPackage(stream, filename)
  else:
    raisePackageError("Unable to determine package parser for $1" % filename)

proc parsePackageFile*(filename: string): seq[Target] =
  ## Parses the file `filename` into a sequence of targets. The parser chosen is
  ## based on the file's extension.
  let fileStream = newFileStream(filename)
  if fileStream.isNil:
    raise newException(IOError, "Could not read package file $1" % filename)

  case filename.splitFile.ext
  of ".cfg": result = parseCfgPackage(fileStream, filename)
  else: raisePackageError("Unable to determine package parser for $1" % filename)
