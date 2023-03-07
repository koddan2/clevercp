import std/os
import std/parseopt
# import sequtils
import strutils
import tables
import glob
import xxhash

const privDirName = ".clevercp"
const hashPathDelim = " | "
const manifestFileName = "manifest.txt"
let relativeManifestPath = joinPath(privDirName, manifestFileName)

let allArgs = commandLineParams()

# let code = if paramCount() > 0:
#   readFile paramStr(1)
#   else: readAll stdin

proc err[Ty](x: varargs[Ty]): void =
  stderr.write("ERR: ")
  stderr.writeLine(x)

proc getHashOfFile(path: string): uint64 =
  let content = readFile(path)
  if content.len > 0:
    result = XXH3_64bits(content)
  else: result = 0

proc echoHeader(): void =
  echo "clevercp version 1.0.0"
  echo ""

proc help(): void =
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


proc parseArgs(): Table[string, string] =
  result = initTable[string, string]()
  result["sub-command"] = allArgs[0]
  let allButFirstArgs = allArgs[1..^1]
  let cliArgs = join(allButFirstArgs, " ")
  var optParser = initOptParser(cliArgs)
  var counter = 0
  while true:
    counter += 1
    optParser.next()
    case optParser.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      result[optParser.key] = optParser.val
    of cmdArgument:
      result["arg:" & $counter] = optParser.key


proc ensurePrivateDir(base: string): void =
  let dirPath = joinPath(base, privDirName)
  if not dirExists(dirPath):
    createDir(dirPath)


proc copyCommand(): void =
  echo "copy"


proc validateManifestCommand(): void =
  echo "VRB: SubCommand = validate-manifest"
  let settings = parseArgs()
  for key, val in settings:
    echo key, " = ", val
  assert settings["sub-command"] == "validate-manifest", "sanity check"
  let dir = normalizedPath(settings["arg:1"])
  assert dirExists(dir), "directory must exist"
  let manifestFilePath = joinPath(dir, relativeManifestPath)
  assert fileExists(manifestFilePath), "manifest file must exist: " & manifestFilePath
  # hash => relative-path
  var hashes = initTable[string, string]()
  let manifestFile = open(manifestFilePath)
  defer: close(manifestFile)

  var line = ""
  while readLine(manifestFile, line):
    var idx = 0
    var ch = line[0]
    while ch != ' ' and idx < line.len:
      idx+=1
      ch = line[idx]
    var idx2 = idx
    while ch != '|' and idx2 < line.len:
      idx2 += 1
      ch = line[idx2]
    let hash = substr(line, 0, idx - 1)
    let path = substr(line, idx2 + 2)
    hashes[path] = hash

  var allOK = true
  for path, hashStr in hashes:
    let pathToFile = joinPath(dir, path)
    if not fileExists(pathToFile):
      allOK = false
      err "Missing file: ", path
      continue
    let computedHash = $getHashOfFile(pathToFile)
    let storedHash = hashStr
    if computedHash == storedHash:
      # echo "OK: ", path
      discard
    else:
      allOK = false
      err "Incorrect checksum: ", path
  if not allOK:
    err "Tree is corrupt!"
    quit(2)
  else:
    echo "OK: Tree is valid according to manifest"


proc generateManifestCommand(): void =
  echo "VRB: SubCommand = generate-manifest"
  let settings = parseArgs()

  var dirFrom: string = normalizedPath(settings["arg:1"])
  assert dirExists(dirFrom), "directory must exist"
  var includeGlob: string = "**"
  if settings.hasKey("includes"):
    includeGlob = settings["includes"]
  var excludeGlob: string = ""
  if settings.hasKey("excludes"):
    excludeGlob = settings["excludes"]

  ensurePrivateDir(dirFrom)
  let manifestFileFullPath = joinPath(dirFrom, relativeManifestPath)
  var localManifestFile = open(manifestFileFullPath, fmWrite)
  defer: close(localManifestFile)
  var counter = 0
  for path in walkGlob(includeGlob, dirFrom):
    if path.startsWith(privDirName):
      # skip private directory
      continue
    elif excludeGlob != "" and path.matches(excludeGlob):
      # skip excluded file
      continue
    # let hashValStr = $secureHashFile(joinPath(dirFrom, path))
    let hashVal = getHashOfFile(joinPath(dirFrom, path))
    let manifestRecord = alignLeft($hashVal, len("18446744073709551615")) &
        hashPathDelim & path
    counter += 1
    stdout.write("\r" & $counter)
    writeLine(localManifestFile, manifestRecord)
    flushFile(localManifestFile)
  echo ""
  echo "Manifest successfully generated: ", manifestFileFullPath


proc main(): void =
  if paramCount() < 1:
    help()
    quit(QuitFailure)

  let firstArg = paramStr(1)
  if firstArg == "copy":
    echoHeader()
    copyCommand()
  elif firstArg == "generate-manifest":
    echoHeader()
    generateManifestCommand()
  elif firstArg == "validate-manifest":
    echoHeader()
    validateManifestCommand()
  else:
    help()
    quit(QuitFailure)

when isMainModule:
  main()
