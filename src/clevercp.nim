import std/os
import std/parseopt
import std/sha1
# import sequtils, tables
import strutils
import glob

const privDirName = ".clevercp"
const hashPathDelim = " | "
const manifestFileName = "manifest.txt"
let relativeManifestPath = joinPath(privDirName, manifestFileName)

let allArgs = commandLineParams()

# let code = if paramCount() > 0:
#   readFile paramStr(1)
#   else: readAll stdin

proc help(): void =
  echo "clevercp version 1.0.0"
  echo ""
  echo "This is a tool whose purpose is to minimize file transfers over networks. It tries to do so"
  echo "  by computing checksums of files and storing them in a manifest file."
  echo ""
  echo "USAGE"
  echo "1.  clevercp copy DIRECTORY_FROM DIRECTORY_TO [--include=INC_GLOB] [--exclude=EXC_GLOB]"
  echo "2.  clevercp generate-manifest DIRECTORY [--include=INC_GLOB] [--exclude=EXC_GLOB]"
  echo "3.  clevercp validate-manifest DIRECTORY [--include=INC_GLOB] [--exclude=EXC_GLOB]"
  echo ""
  echo "Where:"
  echo "  DIRECTORY_FROM is the base directory from which to copy files"
  echo "  DIRECTORY_TO is the target directory to which files should be copied, if their checksum"
  echo "    does not exist or is not equal to the computed one."
  echo "  INC_GLOB and EXC_GLOB are globbing patterns as defined here: https://glob.bolingen.me/latest/glob.html"
  echo "    INC_GLOB defines which files to include, and EXC_GLOB defines which files to exclude"


proc ensurePrivateDir(base: string) : void =
  let dirPath = joinPath(base, privDirName)
  if not dirExists(dirPath):
    createDir(dirPath)


proc copyCommand(): void =
  echo "copy"


proc generateManifestCommand(): void =
  echo "VRB: SubCommand => generate-manifest"
  let allButFirstArgs = allArgs[1..^1]
  let cliArgs = join(allButFirstArgs, " ")
  var optParser = initOptParser(cliArgs)

  var dirFrom: string = ""
  var includeGlob: string = ""
  var excludeGlob: string = ""
  var counter = 0
  while true:
    counter += 1
    optParser.next()
    case optParser.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      if optParser.val == "":
        echo "ERR: unrecognized option: ", optParser.key
        quit(QuitFailure)
      else:
        echo "VRB:   option(", optParser.key, ") = ", optParser.val
        if optParser.key == "includes":
          includeGlob = optParser.val
        elif optParser.key == "excludes":
          excludeGlob = optParser.val
        else:
          echo "ERR: unrecognized option: ", optParser.key
          quit(QuitFailure)
    of cmdArgument:
      if counter == 1:
        # assume this is the DIRECTORY_FROM
        echo "VRB: argument(DIRECTORY) = ", optParser.key
        dirFrom = normalizedPath(optParser.key)
        if not dirExists(dirFrom):
          echo "ERR: directory ", dirFrom, " does not exist"
          quit(QuitFailure)
      # elif counter == 2:
      #   echo "argument(DIRECTORY_TO): ", optParser.key
      #   dirTo = optParser.key
      else:
        echo "ERR: unrecognized argument: ", optParser.key
        quit(QuitFailure)

  ensurePrivateDir(dirFrom)
  var localManifestFile = open(joinPath(dirFrom, relativeManifestPath), fmWrite)
  defer: close(localManifestFile)
  for path in walkGlob(includeGlob, dirFrom):
    if path.startsWith(privDirName):
      # skip private directory
      continue
    elif excludeGlob != "" and path.matches(excludeGlob):
      # skip excluded file
      continue
    let hashValStr = $secureHashFile(joinPath(dirFrom, path))
    let manifestRecord = hashValStr & hashPathDelim & path
    echo manifestRecord
    writeLine(localManifestFile, manifestRecord)
    flushFile(localManifestFile)


proc validateManifestCommand(): void =
  echo "copy"


proc main(): void =
  if paramCount() < 1:
    help()
    quit(QuitFailure)

  let firstArg = paramStr(1)
  if firstArg == "copy":
    copyCommand()
  elif firstArg == "generate-manifest":
    generateManifestCommand()
  elif firstArg == "validate-manifest":
    validateManifestCommand()
  else:
    help()
    quit(QuitFailure)

when isMainModule:
  main()
