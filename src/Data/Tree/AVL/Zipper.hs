
{-# language NamedFieldPuns #-}
{-# language TemplateHaskell #-}
{-# language StandaloneDeriving #-}

module Data.Tree.AVL.Zipper where

import Data.Monoid
import Data.Set (Set)
import Data.Tree.AVL.Internal
import Data.Tree.AVL.Proof
import Data.Tree.AVL.Prune

import Debug.Trace as Debug

import Control.Applicative
import Control.Lens hiding (locus)
import Control.Monad.State.Strict

import qualified Data.Set as Set

data TreeZipper h k v = TreeZipper
    { _tzContext  :: [TreeZipperCxt h k v]
    , _tzHere     :: Map h k v
    , _tzKeyRange :: (k, k)
    , _tzMode     :: Mode
    , _tzRevision :: Revision
    , _tzTouched  :: RevSet
    }

data TreeZipperCxt h k v
    = WentRightFrom (Map h k v) (k, k) Revision
    | WentLeftFrom  (Map h k v) (k, k) Revision
    | JustStarted                      Revision

deriving instance Hash h k v => Show (TreeZipperCxt h k v)

data Mode
    = UpdateMode
    | DeleteMode
    | ReadonlyMode
    deriving (Show, Eq)

makeLenses ''TreeZipper

context :: Lens' (TreeZipper h k v) [TreeZipperCxt h k v]
context = tzContext

locus :: Lens' (TreeZipper h k v) (Map h k v)
locus = tzHere

keyRange :: Lens' (TreeZipper h k v) (k, k)
keyRange = tzKeyRange

mode :: Getter (TreeZipper h k v) Mode
mode = tzMode

trail :: Lens' (TreeZipper h k v) (Set Revision)
trail = tzTouched

instance HasRevision (TreeZipper h k v) where
    revision = tzRevision

type Zipped h k v = StateT (TreeZipper h k v) Maybe

runZipped' :: Hash h k v => Zipped h k v a -> Mode -> Map h k v -> (a, Map h k v, RevSet)
runZipped' action mode0 tree =
    case
        action' `evalStateT` enter mode0 tree
    of
      Just it -> it
      Nothing -> error "runZipped': failed"
  where
    action' = do
      res    <- action
      tree'  <- exit
      trails <- use trail
      return (res, tree', trails)

runZipped :: Hash h k v => Zipped h k v a -> Mode -> Map h k v -> (a, Map h k v, Proof h k v)
runZipped action mode0 tree = case mResult of
    Just (a, tree1, trails) ->
      (a, tree1, prune trails tree)
    Nothing ->
      error "runZipped: failed"
  where
    mResult = action' `evalStateT` enter mode0 tree

    action' = do
      res    <- action
      tree'  <- exit
      trails <- use trail
      return (res, tree', trails)

newRevision :: Zipped h k v Revision
newRevision = do
    rev <- use revision
    revision += 1
    return rev

dump :: Hash h k v => String -> Zipped h k v ()
dump msg = do
    st <- use context
    track ("==== " <> msg <> " BEGIN ====") ()
    track ("ctx\n") st
    l  <- use locus
    track ("lcs\n") l
    track ("==== " <> msg <> " END ====") ()
    return ()

mark :: Zipped h k v ()
mark = do
    rev0 <- use (locus.revision)
    trail %= Set.insert rev0

markAll :: [Revision] -> Zipped h k v ()
markAll revs = do
    trail %= (<> Set.fromList revs)

up :: Hash h k v => Zipped h k v Side
up = do
    ctx  <- use context
    rev1 <- use (locus.revision)
    side <- case ctx of
      WentLeftFrom tree range rev0 : rest
        | Just fork <- tree^.branching -> do
          became <- do
              if rev0 == rev1
              then do
                  return tree

              else do
                  locus %= rehash
                  now   <- use locus
                  rev'  <- newRevision
                  tilt' <- correctTilt (fork^.left) now (fork^.tilt) L
                  let b = branch rev' tilt' now (fork^.right)
                  return b

          context  .= rest
          keyRange .= range

          replaceWith became

          rebalance
          return L

      WentRightFrom tree range rev0 : rest
        | Just fork <- tree^.branching -> do
          became <- do
              if rev0 == rev1
              then do
                  return tree

              else do
                  locus %= rehash
                  now   <- use locus
                  rev'  <- newRevision
                  tilt' <- correctTilt (fork^.right) now (fork^.tilt) R
                  let b = branch rev' tilt' (fork^.left) now
                  return b

          context  .= rest
          keyRange .= range

          replaceWith became

          rebalance
          return R

      [JustStarted _rev0] -> do
          locus %= rehash
          rebalance
          context .= []
          return L

      [] -> do
          fail "already on top"

      other -> do
        error $ "up: " ++ show other

    return side

exit :: Hash h k v => Zipped h k v (Map h k v)
exit = uplift
  where
    uplift = do
        _ <- up
        uplift
      <|> use locus

enter :: Hash h k v => Mode -> Map h k v -> TreeZipper h k v
enter mode0 tree = TreeZipper
    { _tzContext  = [JustStarted (tree^.revision)]
    , _tzHere     = tree
    , _tzKeyRange = (minBound, maxBound)
    , _tzMode     = mode0
    , _tzRevision = tree^.revision + 1
    , _tzTouched  = Set.empty
    }

descentLeft :: Hash h k v => Zipped h k v ()
descentLeft = do
    tree  <- use locus
    range <- use keyRange
    mark
    case tree of
      _ | Just fork <- tree^.branching -> do
          let rev   = fork^.left.revision
          context  %= (WentLeftFrom tree range rev :)
          locus    .= fork^.left
          keyRange .= refine L range (tree^.centerKey)

        | otherwise -> do
            fail "cant' go down on non-branch"

descentRight :: Hash h k v => Zipped h k v ()
descentRight = do
    tree  <- use locus
    range <- use keyRange
    mark
    case tree of
      _ | Just fork <- tree^.branching -> do
          let rev = fork^.right.revision
          context  %= (WentRightFrom tree range rev :)
          locus    .= fork^.right
          keyRange .= refine R range (tree^.centerKey)

        | otherwise -> do
            fail "cant' go down on non-branch"

refine :: Ord key => Side -> (key, key) -> key -> (key, key)
refine L (l, h) m = (l, min m h)
refine R (l, h) m = (max m l, h)

correctTilt :: Hash h k v => Map h k v -> Map h k v -> Tilt -> Side -> Zipped h k v Tilt
correctTilt was became tilt0 side = do
    modus <- use mode
    let
      res = case modus of
        UpdateMode | deepened  was became -> roll tilt0 side
        DeleteMode | shortened was became -> roll tilt0 (another side)
        _                                 -> tilt0

    return res

deepened :: Map h k v -> Map h k v -> Bool
-- | Find a difference in tilt between 2 versions of the branch.
deepened was became
  | Just wasF    <- was   ^.branching
  , Just becameF <- became^.branching
    =   wasF   ^.tilt   ==    M
    &&  becameF^.tilt `elem` [L1, R1]
deepened Leaf{} Branch{} = True
deepened _      _        = False

shortened :: Map h k v -> Map h k v -> Bool
-- | Find a difference in tilt between 2 versions of the branch.
shortened was became
  | Just wasF    <- was   ^.branching
  , Just becameF <- became^.branching
    =   wasF   ^.tilt `elem` [L1, R1]
    &&  becameF^.tilt   ==    M
shortened Branch{} Leaf{} = True
shortened _        _      = False

roll :: Tilt -> Side -> Tilt
-- | Change tilt depending on grown side.
roll tilt0 side =
    case side of
      L -> pred tilt0
      R -> succ tilt0

change
    :: Hash h k v
    => (Zipped h k v a)
    -> Zipped h k v a
change action = do
    modus <- use mode
    when (modus == ReadonlyMode) $ do
        error "change: calling this in ReadonlyMode is prohibited"

    mark
    res <- action
    rev <- newRevision
    locus.revision .= rev
    return res

replaceWith :: Hash h k v => Map h k v -> Zipped h k v ()
replaceWith newTree = do
    change (locus .= newTree)

rebalance :: Hash h k v => Zipped h k v ()
rebalance = do
    tree <- use locus
    rev1 <- newRevision
    rev2 <- newRevision
    rev3 <- newRevision

    let node1 = branch rev1 M
    let node2 = branch rev2 M
    let node3 = branch rev3 M
    let skewn2 = branch rev2
    let skewn3 = branch rev3

    newTree <- case tree of
      Node r1 L2 (Node r2 L1 a b) c -> do
        markAll [r1, r2]
        return $ node1 a (node2 b c)

      Node r1 R2 a (Node r2 R1 b c) -> do
        markAll [r1, r2]
        return $ node1 (node2 a b) c

      Node r1 R2 a (Node r2 M b c) -> do
        markAll [r1, r2]
        return $ skewn2 L1 (skewn3 R1 a b) c

      Node r1 L2 (Node r2 M a b) c -> do
        markAll [r1, r2]
        return $ skewn2 R1 a (skewn3 L1 b c)

      Node r1 L2 (Node r2 R1 a (Node r3 R1 b c)) d -> do
        markAll [r1, r2, r3]
        return $ node1 (skewn2 L1 a b) (node3 c d)

      Node r1 L2 (Node r2 R1 a (Node r3 L1 b c)) d -> do
        markAll [r1, r2, r3]
        return $ node1 (node2 a b) (skewn3 R1 c d)

      Node r1 L2 (Node r2 R1 a (Node r3 M  b c)) d -> do
        markAll [r1, r2, r3]
        return $ node1 (node2 a b) (node3 c d)

      Node r1 R2 a (Node r2 L1 (Node r3 R1 b c) d) -> do
        markAll [r1, r2, r3]
        return $ node1 (skewn2 L1 a b) (node2 c d)

      Node r1 R2 a (Node r2 L1 (Node r3 L1 b c) d) -> do
        markAll [r1, r2, r3]
        return $ node1 (node2 a b) (skewn3 R1 c d)

      Node r1 R2 a (Node r2 L1 (Node r3 M  b c) d) -> do
        markAll [r1, r2, r3]
        return $ node1 (node2 a b) (node3 c d)

      other ->
        return other

    replaceWith newTree

separately :: Zipped h k v a -> Zipped h k v a
separately action = do
    state0 <- get
    result <- action
    put state0
    return result

track :: Show a => String -> a -> Zipped h k v ()
track msg val = do
    Debug.trace (msg <> " " <> show val) $ return ()

goto :: Hash h k v => k -> Zipped h k v ()
goto key0 = do
    raiseUntilHaveInRange key0
    descentOnto key0

raiseUntilHaveInRange :: Hash h k v => k -> Zipped h k v ()
raiseUntilHaveInRange key0 = goUp
  where
    goUp = do
        range <- use keyRange
        unless (key0 `isInside` range) $ do
            _ <- up
            goUp

    k `isInside` (l, h) = k >= l && k <= h

descentOnto :: Hash h k v => k -> Zipped h k v ()
descentOnto key0 = continueDescent
  where
    continueDescent = do
        center <- use (locus.centerKey)
        if key0 >= center
        then descentRight
        else descentLeft
        continueDescent
      <|> return ()
