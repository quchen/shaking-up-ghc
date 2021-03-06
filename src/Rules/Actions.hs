{-# LANGUAGE RecordWildCards #-}
module Rules.Actions (
    build, buildWithResources, copyFile, createDirectory, moveDirectory,
    fixFile, runConfigure, runMake, runBuilder
    ) where

import qualified System.Directory as IO

import Base
import Expression
import Oracles
import Oracles.ArgsHash
import Settings
import Settings.Args
import Settings.Builders.Ar
import qualified Target

-- Build a given target using an appropriate builder and acquiring necessary
-- resources. Force a rebuilt if the argument list has changed since the last
-- built (that is, track changes in the build system).
buildWithResources :: [(Resource, Int)] -> Target -> Action ()
buildWithResources rs target = do
    let builder = Target.builder target
    needBuilder laxDependencies builder
    path    <- builderPath builder
    argList <- interpret target getArgs
    verbose <- interpret target verboseCommands
    let quietlyUnlessVerbose = if verbose then withVerbosity Loud else quietly
    -- The line below forces the rule to be rerun if the args hash has changed
    checkArgsHash target
    withResources rs $ do
        unless verbose $ putInfo target
        quietlyUnlessVerbose $ case builder of
            Ar -> do
                output <- interpret target getOutput
                if "//*.a" ?== output
                then arCmd path argList
                else do
                    input <- interpret target getInput
                    top   <- topDirectory
                    cmd [path] [Cwd output] "x" (top -/- input)

            HsCpp    -> captureStdout target path argList
            GenApply -> captureStdout target path argList

            GenPrimopCode -> do
                src  <- interpret target getInput
                file <- interpret target getOutput
                input <- readFile' src
                Stdout output <- cmd (Stdin input) [path] argList
                writeFileChanged file output

            _  -> cmd [path] argList

-- Most targets are built without explicitly acquiring resources
build :: Target -> Action ()
build = buildWithResources []

captureStdout :: Target -> FilePath -> [String] -> Action ()
captureStdout target path argList = do
    file <- interpret target getOutput
    Stdout output <- cmd [path] argList
    writeFileChanged file output

copyFile :: FilePath -> FilePath -> Action ()
copyFile source target = do
    putBuild $ renderBox [ "Copy file"
                         , "    input: " ++ source
                         , "=> output: " ++ target ]
    copyFileChanged source target

createDirectory :: FilePath -> Action ()
createDirectory dir = do
    putBuild $ "| Create directory " ++ dir
    liftIO $ IO.createDirectoryIfMissing True dir

-- Note, the source directory is untracked
moveDirectory :: FilePath -> FilePath -> Action ()
moveDirectory source target = do
    putBuild $ renderBox [ "Move directory"
                         , "    input: " ++ source
                         , "=> output: " ++ target ]
    liftIO $ IO.renameDirectory source target

-- Transform a given file by applying a function to its contents
fixFile :: FilePath -> (String -> String) -> Action ()
fixFile file f = do
    putBuild $ "| Fix " ++ file
    old <- liftIO $ readFile file
    let new = f old
    length new `seq` liftIO $ writeFile file new

runConfigure :: FilePath -> [CmdOption] -> [String] -> Action ()
runConfigure dir opts args = do
    need [dir -/- "configure"]
    putBuild $ "| Run configure in " ++ dir ++ "..."
    quietly $ cmd Shell (EchoStdout False) [Cwd dir] "bash configure" opts' args
    where
        -- Always configure with bash.
        -- This also injects /bin/bash into `libtool`, instead of /bin/sh
        opts' = opts ++ [AddEnv "CONFIG_SHELL" "/bin/bash"]

runMake :: FilePath -> [String] -> Action ()
runMake dir args = do
    need [dir -/- "Makefile"]
    let note = if null args then "" else " (" ++ intercalate ", " args ++ ")"
    putBuild $ "| Run make" ++ note ++ " in " ++ dir ++ "..."
    quietly $ cmd Shell (EchoStdout False) "make" ["-C", dir] args

runBuilder :: Builder -> [String] -> Action ()
runBuilder builder args = do
    needBuilder laxDependencies builder
    path <- builderPath builder
    let note = if null args then "" else " (" ++ intercalate ", " args ++ ")"
    putBuild $ "| Run " ++ show builder ++ note
    quietly $ cmd [path] args

-- Print out key information about the command being executed
putInfo :: Target.Target -> Action ()
putInfo (Target.Target {..}) = putBuild $ renderBox
    [ "Run " ++ show builder
      ++ " (" ++ stageInfo
      ++ "package = " ++ pkgNameString package
      ++ wayInfo ++ ")"
    , "    input: " ++ digest inputs
    , "=> output: " ++ digest outputs ]
  where
    stageInfo = if isStaged builder then "" else "stage = " ++ show stage ++ ", "
    wayInfo   = if way == vanilla   then "" else ", way = " ++ show way
    digest list = case list of
        []  -> "none"
        [x] -> x
        xs  -> head xs ++ " (and " ++ show (length xs - 1) ++ " more)"
