module Insertion (tests) where

import Common

import qualified Data.Tree.AVL as AVL
import qualified Data.Tree.AVL.Insertion as AVL
import qualified Data.Tree.AVL.Internal as AVL

tests :: Spec
tests = describe "Insert" $ do
    it' "toList . fromList == sort . unique" $ \list -> do
        tree <- AVL.fromList list :: StorageMonad M
        back <- AVL.toList tree
        let uniq = uniqued list
        return (back == uniq)

    it' "Tree is as balanced as possible" $ \list -> do
        tree <- AVL.fromList list :: StorageMonad M
        AVL.isBalancedToTheLeaves tree

    describe "Proofs" $ do
        it' "Insert proof is verifiable" $ \(k, v, list) -> do
            tree        <- AVL.fromList list :: StorageMonad M
            (proof,  _) <- AVL.insert' k v tree
            (proof1, _) <- AVL.insert' k v (AVL.unProof proof)

            return $ AVL.checkProof (AVL.rootHash tree) proof1

        it' "Insert proof is replayable" $ \(k, v, list) -> do
            tree        <- AVL.fromList list :: StorageMonad M
            (proof1, _) <- AVL.insert' k v tree
            (proof2, _) <- AVL.insert' k v (AVL.unProof proof1)

            return (proof1 == proof2)

        it' "Insert is idempotent" $ \(k, v, list) -> do
            tree <- AVL.fromList list :: StorageMonad M
            (_, tree1) <- AVL.insert' k v tree
            (_, tree2) <- AVL.insert' k v tree1
            return (tree1 == tree2)
