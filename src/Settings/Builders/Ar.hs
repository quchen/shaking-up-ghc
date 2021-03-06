module Settings.Builders.Ar (arBuilderArgs, arCmd) where

import Base
import Expression
import Oracles
import Predicates (builder)

arBuilderArgs :: Args
arBuilderArgs = builder Ar ? mconcat [ arg "q"
                                     , arg =<< getOutput
                                     , append =<< getInputs ]

-- This count includes arg "q" and arg file parameters in arBuilderArgs.
-- Update this value appropriately when changing arBuilderArgs.
arFlagsCount :: Int
arFlagsCount = 2

-- Ar needs to be invoked in a special way: we pass the list of files to be
-- archived via a temporary file as otherwise Ar (or rather Windows command
-- line) chokes up. Alternatively, we split argument list into chunks and call
-- ar multiple times (when passing files via a separate file is not supported).
arCmd :: FilePath -> [String] -> Action ()
arCmd path argList = do
    arSupportsAtFile <- flag ArSupportsAtFile
    let flagArgs = take arFlagsCount argList
        fileArgs = drop arFlagsCount argList
    if arSupportsAtFile
    then useAtFile path flagArgs fileArgs
    else useSuccessiveInvocations path flagArgs fileArgs

useAtFile :: FilePath -> [String] -> [String] -> Action ()
useAtFile path flagArgs fileArgs = withTempFile $ \tmp -> do
    writeFile' tmp $ unwords fileArgs
    cmd [path] flagArgs ('@' : tmp)

useSuccessiveInvocations :: FilePath -> [String] -> [String] -> Action ()
useSuccessiveInvocations path flagArgs fileArgs = do
    maxChunk <- cmdLineLengthLimit
    forM_ (chunksOfSize maxChunk fileArgs) $ \argsChunk ->
        unit . cmd [path] $ flagArgs ++ argsChunk
