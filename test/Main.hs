
import qualified Algorithm
import qualified Deletion
import qualified Insertion
import qualified Lookup
import qualified Persistence
import qualified Adapter

import Common

main :: IO ()
main = hspec $ do
    describe "AVL+ tree" $ do
        Algorithm.tests
        Insertion.tests
        Deletion.tests
        Lookup.tests
        Persistence.tests
        Adapter.tests
