module Settings (
    args
    ) where

import Base
import Settings.GhcPkg
import Settings.GhcCabal
import Settings.User
import Expression

args :: Args
args = defaultArgs <> userArgs

-- TODO: add all other settings
defaultArgs :: Args
defaultArgs = mconcat
    [ cabalArgs
    , ghcPkgArgs
    , customPackageArgs ]
