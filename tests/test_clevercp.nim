import unittest
import os
import std/sequtils
import std/strutils
import std/files
import clevercp

suite "clevercp tests":
  setup:
    let testDir = "test_dir"
    let testDirFrom = joinPath(testDir, "from")
    let testDirTo = joinPath(testDir, "to")
    let testFile1 = joinPath(testDirFrom, "file1.txt")
    let testFile2 = joinPath(testDirFrom, "file2.txt")
    let testFile3 = joinPath(testDirFrom, "file3.txt")
    let testFile4 = joinPath(testDirFrom, "file4.txt")
    let manifestFile = joinPath(testDirFrom, ".clevercp", "manifest.txt")

    createDir(testDir)
    createDir(testDirFrom)
    createDir(testDirTo)
    writeFile(testFile1, "This is file 1")
    writeFile(testFile2, "This is file 2")
    writeFile(testFile3, "This is file 3")
    writeFile(testFile4, "This is file 4")

  teardown:
    removeDir(testDir)

  test "generate-manifest":
    discard generateManifestCommand()
    check fileExists(manifestFile)

  test "validate-manifest":
    discard generateManifestCommand()
    check fileExists(manifestFile)
    validateManifestCommand()

  test "copy":
    discard generateManifestCommand()
    copyCommand()
    check fileExists(joinPath(testDirTo, "file1.txt"))
    check fileExists(joinPath(testDirTo, "file2.txt"))
    check fileExists(joinPath(testDirTo, "file3.txt"))
    check fileExists(joinPath(testDirTo, "file4.txt"))

  test "copy-self":
    copySelfCommand()
    let self = getAppFilename()
    let target = joinPath(testDirFrom, ".clevercp", extractFilename(self))
    check fileExists(target)
