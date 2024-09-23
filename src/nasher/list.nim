from strutils import join, capitalizeAscii
import utils/shared

const helpList* = """
Usage:
  nasher list [options] [<target>...]

Description:
  For each <target>, lists the name, description, source file patterns, and
  final filename once built.

  If passed with --quiet, will only show target names. If passed with --verbose,
  will also show all files matching the source patterns.

"""

proc displayField(field, val: string) =
  display(capitalizeAscii(field) & ":", val)

proc list*(target: Target) =
  display("Target:", target.opts.get("name"), priority = HighPriority)
  for field, val in fieldPairs(target[]):
    case field
    of "opts":
      for k, _ in target.opts.pairs:
        displayField(k, target.opts[k])
    of "lists":
      for k, _ in target.lists.pairs:
        displayField(k, target.lists[k].join("\n"))
    else:
      discard

  if isLogging(LowPriority):
    info("Source Files:", target.getSourceFiles.join("\n"))

  for pattern, dir in target.rules.items:
    display("Rule:", pattern & " -> " & dir)
