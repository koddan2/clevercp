import std/os
import std/parseopt
import std/options
import strutils
import tables
import glob
import xxhash

const privDirName = ".clevercp"
const hashPathDelim = " | "
const manifestFileName = "manifest.txt"
let relativeManifestPath = joinPath(privDirName, manifestFileName)

const maxUint64Str = "18446744073709551615"
let maxUint64StrLen = len(maxUint64Str)

let allArgs = commandLineParams()


proc err[Ty](x: varargs[Ty]): void =
  stderr.write("ERR: ")
  stderr.writeLine(x)


proc strOpt(s: string): Option[string] =
  if s.len != 0: some(s)
  else: none(string)


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
  echo "3.  clevercp validate-manifest DIRECTORY"
  echo ""
  echo "Where:"
  echo "  DIRECTORY_FROM is the base directory from which to copy files"
  echo "  DIRECTORY_TO is the target directory to which files should be copied, if their checksum"
  echo "    does not exist or is not equal to the computed one."
  echo "  DIRECTORY is the base directory in which to process files"
  echo "  INC_GLOB and EXC_GLOB are globbing patterns as defined here: https://glob.bolingen.me/latest/glob.html"
  echo "    INC_GLOB defines which files to include, and EXC_GLOB defines which files to exclude"
  echo "    INC_GLOB is ** by default (matches all files), whereas EXC_GLOB is unset."


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


proc computeHashes(includeGlob, dir: string,
                   excludeGlob: Option[string]): Table[string, uint64] =
  var counter = 0
  result = initTable[string, uint64]()

  var exc: string
  proc filterYieldWithExc(path: string, kind: PathComponent): bool =
    result = true
    if path.startsWith(privDirName):
      result = false
    elif path.matches(exc):
      result = false

  proc filterYieldNoExc(path: string, kind: PathComponent): bool =
    not path.startsWith(privDirName)

  var filterYield: FilterYield
  if excludeGlob.isSome:
    exc = excludeGlob.get()
    filterYield = filterYieldWithExc
  else:
    filterYield = filterYieldNoExc

  for path in walkGlob(includeGlob, dir, filterYield = filterYield):
    # if path.startsWith(privDirName):
    #   # skip private directory
    #   continue
    # elif excludeGlob.isSome and path.matches(excludeGlob.get()):
    #   # skip excluded file
    #   continue
    # lets hash
    let hashVal = getHashOfFile(joinPath(dir, path))
    result[path] = hashVal
    stdout.write("\r" & $counter)
    counter += 1


proc readManifest(manifestFilePath: string): Table[string, string] =
  # hash => relative-path
  result = initTable[string, string]()
  if not fileExists(manifestFilePath):
    return
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
    result[path] = hash


proc validateManifestCommand(): void =
  echo "VRB: SubCommand = validate-manifest"
  let settings = parseArgs()
  echo settings
  assert settings["sub-command"] == "validate-manifest", "sanity check"
  let dir = normalizedPath(settings["arg:1"])
  assert dirExists(dir), "directory must exist"
  let manifestFilePath = joinPath(dir, relativeManifestPath)
  assert fileExists(manifestFilePath), "manifest file must exist: " & manifestFilePath

  let hashes = readManifest(manifestFilePath)

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


proc generateManifestCommand(): Table[string, uint64] =
  echo "VRB: SubCommand = generate-manifest"
  let settings = parseArgs()

  echo settings
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
  let hashes = computeHashes(includeGlob, dirFrom, excludeGlob.strOpt)
  result = hashes
  for path, hashVal in hashes:
    let manifestRecord = alignLeft($hashVal, maxUint64StrLen) &
        hashPathDelim & path
    counter += 1
    writeLine(localManifestFile, manifestRecord)
    flushFile(localManifestFile)
  echo ""
  echo "Manifest successfully generated: ", manifestFileFullPath


proc copyCommand(): void =
  echo "VRB: SubCommand = copy"
  let hashes = generateManifestCommand()
  let settings = parseArgs()

  var dirFrom: string = normalizedPath(settings["arg:1"])
  var dirTo: string = normalizedPath(settings["arg:2"])
  assert dirExists(dirFrom), "directory must exist"
  if not dirExists(dirTo):
    createDir(dirTo)
  var includeGlob: string = "**"
  if settings.hasKey("includes"):
    includeGlob = settings["includes"]
  var excludeGlob: string = ""
  if settings.hasKey("excludes"):
    excludeGlob = settings["excludes"]

  let hashesOnTarget = readManifest(joinPath(dirTo, relativeManifestPath))

  var updated = false
  for path in walkGlob(includeGlob, dirFrom):
    if path.startsWith(privDirName):
      # skip private directory
      continue
    let fromFile = joinPath(dirFrom, path)
    let toFile = joinPath(dirTo, path)
    if not dirExists(parentDir(toFile)):
      updated = true
      createDir(parentDir(toFile))

    if not fileExists(toFile):
      updated = true
      copyFile(fromFile, toFile, {cfSymlinkIgnore}) # TODO: option
      echo "VRB: COPY: ", path
    else:
      var toFileHash: string = "0"
      if hashesOnTarget.hasKey(path):
        toFileHash = hashesOnTarget[path]
      if $hashes[path] != toFileHash:
        updated = true
        copyFile(fromFile, toFile, {cfSymlinkIgnore}) # TODO: option
        echo "VRB: COPY: ", path
      else: echo "VRB: SAME: ", path

  if updated:
    let fromManifestFilePath = joinPath(dirFrom, relativeManifestPath)
    let toManifestFilePath = joinPath(dirTo, relativeManifestPath)
    if not dirExists(parentDir(toManifestFilePath)):
      createDir(parentDir(toManifestFilePath))
    copyFile(fromManifestFilePath, toManifestFilePath, {cfSymlinkIgnore}) # TODO: option
    echo "VRB: COPY: ", relativeManifestPath
  else:
    echo "INF: No files were copied - trees were equivalent according to manifest."


proc copySelfCommand(): void =
  let self = getAppFilename()
  let settings = parseArgs()
  let dirTo = joinPath(settings["arg:1"], privDirName)
  let target = joinPath(dirTo, extractFilename(self))
  echo "VRB: SubCommand = copy-self (", self, " => ", target, ")"
  copyFile(self, target)


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
    discard generateManifestCommand()
  elif firstArg == "validate-manifest":
    echoHeader()
    validateManifestCommand()
  elif firstArg == "copy-self":
    copySelfCommand()
  else:
    help()
    quit(QuitFailure)


when isMainModule:
  main()
