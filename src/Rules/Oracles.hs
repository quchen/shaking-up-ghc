module Rules.Oracles (oracleRules) where

import Base
import Oracles
import Oracles.ArgsHash
import Oracles.ModuleFiles

oracleRules :: Rules ()
oracleRules = do
    argsHashOracle     -- see Oracles.ArgsHash
    configOracle       -- see Oracles.Config
    dependenciesOracle -- see Oracles.Dependencies
    lookupInPathOracle -- see Oracles.LookupInPath
    moduleFilesOracle  -- see Oracles.ModuleFiles
    packageDataOracle  -- see Oracles.PackageData
    packageDepsOracle  -- see Oracles.PackageDeps
    windowsRootOracle  -- see Oracles.WindowsRoot
