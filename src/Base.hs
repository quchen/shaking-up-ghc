module Base (
    -- * General utilities
    module Control.Applicative,
    module Control.Monad.Extra,
    module Data.Function,
    module Data.List,
    module Data.Maybe,
    module Data.Monoid,
    MonadTrans(lift),

    -- * Shake
    module Development.Shake,
    module Development.Shake.Classes,
    module Development.Shake.FilePath,

    -- * Paths
    shakeFilesPath, configPath, sourcePath, programInplacePath,
    bootPackageConstraints, packageDependencies,
    packageConfiguration, packageConfigurationInitialised,

    -- * Output
    putColoured, putOracle, putBuild, putSuccess, putError, renderBox,

    -- * Miscellaneous utilities
    bimap, minusOrd, intersectOrd, replaceEq, replace, quote, chunksOfSize,
    replaceSeparators, decodeModule, encodeModule, unifyPath, (-/-),
    versionToInt, removeFileIfExists, removeDirectoryIfExists, wordsWhen
    ) where

import Control.Applicative
import Control.Monad.Extra
import Control.Monad.Reader
import Data.Function
import Data.List
import Data.Maybe
import Data.Monoid
import Development.Shake hiding (unit, (*>), parallel)
import Development.Shake.Classes
import Development.Shake.FilePath
import System.Console.ANSI
import qualified System.Directory as IO
import System.IO

-- TODO: reexport Stage, etc.?
import Stage

-- Build system files and paths
shakePath :: FilePath
shakePath = "shake-build"

shakeFilesPath :: FilePath
shakeFilesPath = shakePath -/- ".db"

configPath :: FilePath
configPath = shakePath -/- "cfg"

-- | Path to source files of the build system, e.g. this file is located at
-- sourcePath -/- "Base.hs". We use this to `need` some of the source files.
sourcePath :: FilePath
sourcePath = shakePath -/- "src"

programInplacePath :: FilePath
programInplacePath = "inplace/bin"

bootPackageConstraints :: FilePath
bootPackageConstraints = shakeFilesPath -/- "boot-package-constraints"

packageDependencies :: FilePath
packageDependencies = shakeFilesPath -/- "package-dependencies"

packageConfiguration :: Stage -> FilePath
packageConfiguration Stage0 = "libraries/bootstrapping.conf"
packageConfiguration _      = "inplace/lib/package.conf.d"

-- StageN, N > 0, share the same packageConfiguration (see above)
packageConfigurationInitialised :: Stage -> FilePath
packageConfigurationInitialised stage =
    shakeFilesPath -/- "package-configuration-initialised-"
    ++ stageString (min stage Stage1)

-- Utility functions
-- | Find and replace all occurrences of a value in a list
replaceEq :: Eq a => a -> a -> [a] -> [a]
replaceEq from = replaceWhen (== from)

-- | Find and replace all occurrences of path separators in a String with a Char
replaceSeparators :: Char -> String -> String
replaceSeparators = replaceWhen isPathSeparator

replaceWhen :: (a -> Bool) -> a -> [a] -> [a]
replaceWhen p to = map (\from -> if p from then to else from)

-- | Find all occurrences of substring 'from' and replace them to 'to' in a
-- given string. Not very efficient, but simple and fast enough for our purposes
replace :: Eq a => [a] -> [a] -> [a] -> [a]
replace from to = go
  where
    skipFrom = drop $ length from
    go [] = []
    go s @ (x : xs)
        | from `isPrefixOf` s = to ++ go (skipFrom s)
        | otherwise           = x  :  go xs

-- | Split a list into chunks in places where the predicate @p@ holds.
-- See: http://stackoverflow.com/a/4981265
wordsWhen :: Eq a => (a -> Bool) -> [a] -> [[a]]
wordsWhen p list =
    case dropWhile p list of
        [] -> []
        l  -> w : wordsWhen p rest where (w, rest) = break p l

-- | @chunksOfSize size strings@ splits a given list of strings into chunks not
-- exceeding the given @size@.
chunksOfSize :: Int -> [String] -> [[String]]
chunksOfSize _    [] = []
chunksOfSize size strings = reverse chunk : chunksOfSize size rest
  where
    (chunk, rest) = go [] 0 strings
    go res _         []     = (res, [])
    go res chunkSize (s:ss) =
        if newSize > size then (res, s:ss) else go (s:res) newSize ss
      where
        newSize = chunkSize + length s

-- | Add quotes to a String
quote :: String -> String
quote s = "\"" ++ s ++ "\""

-- | Given a version string such as "2.16.2" produce an integer equivalent
versionToInt :: String -> Int
versionToInt s = major * 1000 + minor * 10 + patch
  where
    [major, minor, patch] = map read . words $ replaceEq '.' ' ' s

-- | Given a module name extract the directory and file name, e.g.:
--
-- > decodeModule "Data.Functor.Identity" = ("Data/Functor/", "Identity")
decodeModule :: String -> (FilePath, String)
decodeModule = splitFileName . replaceEq '.' '/'

-- | Given the directory and file name find the corresponding module name, e.g.:
--
-- > encodeModule "Data/Functor/" "Identity.hs" = "Data.Functor.Identity"
encodeModule :: FilePath -> String -> String
encodeModule dir file = replaceEq '/' '.' $ dir -/- takeBaseName file

-- | Normalise a path and convert all path separators to @/@, even on Windows.
unifyPath :: FilePath -> FilePath
unifyPath = toStandard . normaliseEx

-- | Combine paths using '</>' and apply 'unifyPath' to the result
(-/-) :: FilePath -> FilePath -> FilePath
a -/- b = unifyPath $ a </> b

infixr 6 -/-

-- | A more colourful version of Shake's putNormal
putColoured :: Color -> String -> Action ()
putColoured colour msg = do
    liftIO $ setSGR [SetColor Foreground Vivid colour]
    putNormal msg
    liftIO $ setSGR []
    liftIO $ hFlush stdout

-- | Make oracle output more distinguishable
putOracle :: String -> Action ()
putOracle = putColoured Blue

-- | Make build output more distinguishable
putBuild :: String -> Action ()
putBuild = putColoured White

-- | A more colourful version of success message
putSuccess :: String -> Action ()
putSuccess = putColoured Green

-- | A more colourful version of error message
putError :: String -> Action a
putError msg = do
    putColoured Red msg
    error $ "GHC build system error: " ++ msg

-- | Render the given set of lines in a nice box of ASCII.
--
-- The minimum width and whether to use Unicode symbols are hardcoded in the
-- function's body.
--
-- >>> renderBox (words "lorem ipsum")
-- /----------\
-- | lorem    |
-- | ipsum    |
-- \----------/
renderBox :: [String] -> String
renderBox ls = tail $ concatMap ('\n' :) (boxTop : map renderLine ls ++ [boxBot])
  where
    -- Minimum total width of the box in characters
    minimumBoxWidth = 32

    -- FIXME: See Shake #364.
    useUnicode = False

    -- Characters to draw the box
    (dash, pipe, topLeft, topRight, botLeft, botRight, padding)
        | useUnicode = ('─', '│', '╭',  '╮', '╰', '╯', ' ')
        | otherwise  = ('-', '|', '/', '\\', '\\', '/', ' ')

    -- Box width, taking minimum desired length and content into account.
    -- The -4 is for the beginning and end pipe/padding symbols, as
    -- in "| xxx |".
    boxContentWidth = (minimumBoxWidth - 4) `max` maxContentLength
      where
        maxContentLength = maximum (map length ls)

    renderLine l = concat
        [ [pipe, padding]
        , padToLengthWith boxContentWidth padding l
        , [padding, pipe] ]
      where
        padToLengthWith n filler x = x ++ replicate (n - length x) filler

    (boxTop, boxBot) = ( topLeft : dashes ++ [topRight]
                       , botLeft : dashes ++ [botRight] )
      where
        -- +1 for each non-dash (= corner) char
        dashes = replicate (boxContentWidth + 2) dash

-- Explicit definition to avoid dependency on Data.Bifunctor
-- | Bifunctor bimap.
bimap :: (a -> b) -> (c -> d) -> (a, c) -> (b, d)
bimap f g (x, y) = (f x, g y)

-- Explicit definition to avoid dependency on Data.List.Ordered
-- | Difference of two ordered lists.
minusOrd :: Ord a => [a] -> [a] -> [a]
minusOrd [] _  = []
minusOrd xs [] = xs
minusOrd (x:xs) (y:ys) = case compare x y of
    LT -> x : minusOrd xs (y:ys)
    EQ ->     minusOrd xs ys
    GT ->     minusOrd (x:xs) ys

-- Explicit definition to avoid dependency on Data.List.Ordered
-- | Intersection of two ordered lists by a predicate.
intersectOrd :: (a -> b -> Ordering) -> [a] -> [b] -> [a]
intersectOrd cmp = loop
  where
    loop [] _ = []
    loop _ [] = []
    loop (x:xs) (y:ys) = case cmp x y of
         LT ->     loop xs (y:ys)
         EQ -> x : loop xs ys
         GT ->     loop (x:xs) ys

-- | Remove a file that doesn't necessarily exist
removeFileIfExists :: FilePath -> Action ()
removeFileIfExists f = liftIO . whenM (IO.doesFileExist f) $ IO.removeFile f

-- | Remove a directory that doesn't necessarily exist
removeDirectoryIfExists :: FilePath -> Action ()
removeDirectoryIfExists d =
    liftIO . whenM (IO.doesDirectoryExist d) $ IO.removeDirectoryRecursive d
