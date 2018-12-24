module Common
    ( module Common
    , module Lenses
    , module T
    ) where

import Control.Monad as T (unless, when)
import Control.Monad.Catch as T (catch)
import Control.Monad.IO.Class as T (MonadIO, liftIO)
import Lens.Micro.Platform as Lenses

import Data.Default as T (Default (def))
import Data.Foldable ()
import Data.Function (on)
import Data.Hashable (Hashable, hash)
import Data.HashMap.Strict (HashMap, fromList)
import Data.List (nubBy, sortBy)
import Data.Ord (comparing)
import Data.String (IsString (fromString))

import GHC.Generics (Generic)

import Test.Hspec as T
import Test.QuickCheck as T (Arbitrary (..), Gen, Property, Testable, elements, forAll, ioProperty,
                             property, (===), (==>))
import Test.QuickCheck.Instances as T ()

import qualified Data.Tree.AVL as AVL
import qualified Data.Tree.AVL.Store.Pure as Pure
import qualified Data.Tree.AVL.Store.Void as Void

-- | Extensional equality combinator.
(.=.) :: (Eq b, Show b, Arbitrary a) => (a -> b) -> (a -> b) -> a -> Property
f .=. g = \a ->
  let fa = f a
      ga = g a

  in  fa === ga

infixr 5 .=.

--data InitialHash
--    = InitialHash { getInitialHash :: Layer }
--    | Default
--    deriving (Ord, Generic)

type Layer = AVL.MapLayer IntHash StringName Int IntHash

instance Hashable StringName

instance Hashable a => AVL.ProvidesHash a IntHash where
    getHash = IntHash . hash

newtype IntHash = IntHash { getIntHash :: Int }
    deriving (Eq, Ord,  Arbitrary, Generic)

instance Hashable IntHash

instance Show IntHash where
    show = take 8 . map convert . map (`mod` 16) . iterate (`div` 16) . abs . getIntHash
      where
        convert = ("0123456789ABCDEF" !!)

newtype StringName = StringName { getStringName :: String }
    deriving (Eq, Ord, Generic)

instance IsString StringName where
    fromString = StringName

instance Show StringName where
    show = getStringName

instance Arbitrary StringName where
    arbitrary = do
        a <- elements ['B'.. 'Y']
        return (StringName [a])

instance (Eq k, Hashable k) => Default (HashMap k v) where
    def = fromList []

-- Requirement of QuickCheck
instance Show (a -> b) where
    show _ = "<function>"

type StorageMonad = Void.Store

type M = AVL.Map IntHash StringName Int

scanM :: Monad m => (a -> b -> m b) -> b -> [a] -> m [b]
scanM _      _     []       = return []
scanM action accum (x : xs) = do
    (accum :) <$> do
        accum' <- action x accum
        scanM action accum' xs

unique :: Eq a => [(a, b)] -> [(a, b)]
unique = nubBy  ((==) `on` fst)

uniqued :: Ord a => [(a, b)] -> [(a, b)]
uniqued = sortBy (comparing fst) . unique . reverse

it'
    ::  ( Testable (f Property)
        , Testable  prop
        , Functor   f
        )
    =>  String
    ->  f (StorageMonad prop)
    ->  SpecWith ()
it' msg func =
    it msg $ property $ fmap (ioProperty . Void.runStoreT) func

it''
    ::  ( Testable   prop
        , Arbitrary  src
        , AVL.Params h k v
        , Show       src
        )
    =>  String
    ->  (src -> Pure.StoreT h k v StorageMonad prop)
    ->  SpecWith ()
it'' msg func =
    it msg $ property $ \src ->
        ioProperty $ Void.runStoreT $ do
            st <- Pure.newState
            Pure.runStoreT st (func src)

put :: (MonadIO m) => String -> m ()
put = liftIO . putStrLn
